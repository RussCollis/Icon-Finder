import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Counts and per-item details collected during an extraction run.
nonisolated struct ExtractionSummary: Sendable {
    var fromApps = 0
    var fromPackages = 0
    var fromDiskImages = 0
    var skipped = 0
    var missing = 0
    var details: [String] = []
    var summaryFileURL: URL?

    var totalExtracted: Int { fromApps + fromPackages + fromDiskImages }
}

/// Port of `extract_mac_app_icons.sh`: extracts icons from .app bundles,
/// .pkg installers and .dmg disk images into PNG files.
nonisolated enum IconExtractor {
    enum Event: Sendable {
        case log(String)
        case finished(ExtractionSummary)
    }

    /// Starts an extraction run on a background task. Cancelling the consumer
    /// of the stream cancels the run.
    static func run(searchFolders: [URL], outputFolder: URL) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var job = ExtractionJob(outputFolder: outputFolder) { message in
                    continuation.yield(.log(message))
                }
                let summary = job.run(searchFolders: searchFolders)
                continuation.yield(.finished(summary))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated private struct ExtractionJob {
    private enum Source {
        case app, package, diskImage
    }

    let outputFolder: URL
    let emit: @Sendable (String) -> Void

    private let fileManager = FileManager.default
    private var summary = ExtractionSummary()

    init(outputFolder: URL, emit: @escaping @Sendable (String) -> Void) {
        self.outputFolder = outputFolder
        self.emit = emit
    }

    mutating func run(searchFolders: [URL]) -> ExtractionSummary {
        do {
            try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        } catch {
            log("❌ Could not create output folder \(outputFolder.path): \(error.localizedDescription)")
            return summary
        }

        log("📦 Extracting icons from .app bundles...")
        for folder in searchFolders {
            for app in findItems(in: folder, withExtension: "app", maxDepth: 2) {
                guard !Task.isCancelled else { break }
                let name = Self.safeName(app.deletingPathExtension().lastPathComponent)
                extractAppIcon(
                    app,
                    to: outputFolder.appending(path: name).appending(path: "\(name).png"),
                    label: name,
                    source: .app
                )
            }
        }

        log("📦 Scanning for .pkg files...")
        for folder in searchFolders {
            for package in findItems(in: folder, withExtension: "pkg", maxDepth: 2) {
                guard !Task.isCancelled else { break }
                extractPackageIcons(package)
            }
        }

        log("📦 Scanning for .dmg files...")
        for folder in searchFolders {
            for diskImage in findItems(in: folder, withExtension: "dmg", maxDepth: 2) {
                guard !Task.isCancelled else { break }
                extractDiskImageIcons(diskImage)
            }
        }

        if Task.isCancelled {
            log("⏹ Extraction cancelled.")
        }

        logFinalSummary()
        writeSummaryFile()
        return summary
    }

    // MARK: - Sources

    private mutating func extractAppIcon(_ app: URL, to outputIcon: URL, label: String, source: Source) {
        if fileManager.fileExists(atPath: outputIcon.path) {
            log("⏩ Icon already exists, skipping: \(label)")
            record("Skipped (duplicate): \(label)")
            summary.skipped += 1
            return
        }

        // Same lookup as the script: CFBundleIconFile, with ".icns" appended if missing.
        let infoPlist = app.appending(path: "Contents/Info.plist")
        var iconFile = (NSDictionary(contentsOf: infoPlist)?["CFBundleIconFile"] as? String) ?? ""
        if !iconFile.hasSuffix(".icns") {
            iconFile += ".icns"
        }
        let iconURL = app.appending(path: "Contents/Resources").appending(path: iconFile)

        guard fileManager.fileExists(atPath: iconURL.path) else {
            log("❌ Icon file not found for \(label) at \(iconURL.path)")
            record("Missing icon: \(label)")
            summary.missing += 1
            return
        }

        if convert(iconURL, to: outputIcon) {
            increment(source)
            log("✅ Extracted icon for \(label)")
            record("Extracted: \(label)")
        } else {
            log("❌ Failed to convert icon for \(label)")
            record("Missing icon: \(label)")
            summary.missing += 1
        }
    }

    private mutating func extractPackageIcons(_ package: URL) {
        let packageName = Self.safeName(package.deletingPathExtension().lastPathComponent)
        guard let workDir = makeTemporaryDirectory(prefix: "pkg_extract_\(packageName)") else { return }
        defer { try? fileManager.removeItem(at: workDir) }

        // pkgutil requires that the destination does not exist yet.
        let expandedDir = workDir.appending(path: "expanded")
        log("Expanding \(package.path)...")
        guard runTool("/usr/sbin/pkgutil", ["--expand-full", package.path, expandedDir.path]) else {
            log("❌ Failed to expand \(package.path)")
            return
        }

        for icns in findItems(in: expandedDir, withExtension: "icns", maxDepth: nil) {
            guard !Task.isCancelled else { break }
            let iconName = icns.deletingPathExtension().lastPathComponent
            let outputIcon = outputFolder.appending(path: packageName).appending(path: "\(iconName).png")
            extractStandaloneIcon(
                icns,
                to: outputIcon,
                label: "\(packageName) - \(iconName)",
                sourceDescription: package.lastPathComponent,
                source: .package
            )
        }
    }

    private mutating func extractDiskImageIcons(_ diskImage: URL) {
        let imageName = Self.safeName(diskImage.deletingPathExtension().lastPathComponent)
        guard let mountPoint = makeTemporaryDirectory(prefix: "\(imageName)_mnt") else { return }
        defer { try? fileManager.removeItem(at: mountPoint) }

        log("Mounting \(diskImage.path)...")
        guard runTool("/usr/bin/hdiutil", [
            "attach", diskImage.path,
            "-mountpoint", mountPoint.path,
            "-nobrowse", "-readonly", "-noautoopen", "-quiet",
        ]) else {
            log("❌ Failed to mount \(diskImage.path)")
            return
        }
        defer {
            if !runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) {
                runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force", "-quiet"])
            }
        }

        // .app bundles are not descended into, so only their main icon and
        // loose .icns files on the image are extracted.
        let items = findItems(in: mountPoint, withExtensions: ["app", "icns"], maxDepth: nil)
        for item in items {
            guard !Task.isCancelled else { break }
            if item.pathExtension == "app" {
                let appName = Self.safeName(item.deletingPathExtension().lastPathComponent)
                let outputIcon = outputFolder
                    .appending(path: "\(imageName)_\(appName)")
                    .appending(path: "\(appName).png")
                extractAppIcon(item, to: outputIcon, label: "\(imageName) - \(appName)", source: .diskImage)
            } else {
                let iconName = item.deletingPathExtension().lastPathComponent
                let outputIcon = outputFolder.appending(path: imageName).appending(path: "\(iconName).png")
                extractStandaloneIcon(
                    item,
                    to: outputIcon,
                    label: "\(imageName) - \(iconName)",
                    sourceDescription: diskImage.lastPathComponent,
                    source: .diskImage
                )
            }
        }
    }

    private mutating func extractStandaloneIcon(
        _ icns: URL,
        to outputIcon: URL,
        label: String,
        sourceDescription: String,
        source: Source
    ) {
        if fileManager.fileExists(atPath: outputIcon.path) {
            log("⏩ Icon already exists, skipping: \(outputIcon.path)")
            record("Skipped (duplicate): \(outputIcon.path)")
            summary.skipped += 1
            return
        }

        if convert(icns, to: outputIcon) {
            increment(source)
            log("✅ Extracted icon from \(sourceDescription): \(outputIcon.lastPathComponent)")
            record("Extracted: \(label)")
        } else {
            log("❌ Failed to convert \(icns.path)")
            record("Missing icon: \(icns.path)")
            summary.missing += 1
        }
    }

    // MARK: - Helpers

    /// Equivalent of `find <folder> -name "*.<ext>" -maxdepth <depth>`, except
    /// that matched bundles are not descended into.
    private func findItems(in folder: URL, withExtension ext: String, maxDepth: Int?) -> [URL] {
        findItems(in: folder, withExtensions: [ext], maxDepth: maxDepth)
    }

    private func findItems(in folder: URL, withExtensions extensions: Set<String>, maxDepth: Int?) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if extensions.contains(url.pathExtension.lowercased()) {
                results.append(url)
                enumerator.skipDescendants()
            } else if let maxDepth, enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }
        return results
    }

    /// Converts the largest representation in an .icns file to PNG.
    private func convert(_ icns: URL, to png: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(icns as CFURL, nil) else { return false }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return false }
        let largestIndex = (0..<count).max { lhs, rhs in
            pixelWidth(of: source, at: lhs) < pixelWidth(of: source, at: rhs)
        } ?? 0

        guard let image = CGImageSourceCreateImageAtIndex(source, largestIndex, nil) else { return false }

        do {
            try fileManager.createDirectory(at: png.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return false
        }
        guard let destination = CGImageDestinationCreateWithURL(
            png as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    private func pixelWidth(of source: CGImageSource, at index: Int) -> Int {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        return properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
    }

    @discardableResult
    private func runTool(_ path: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func makeTemporaryDirectory(prefix: String) -> URL? {
        let url = fileManager.temporaryDirectory.appending(path: "\(prefix)_\(UUID().uuidString)")
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            log("❌ Could not create temporary folder: \(error.localizedDescription)")
            return nil
        }
    }

    /// Mirrors `tr -cd '[:alnum:] _-'`.
    static func safeName(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-")
        let filtered = String(name.filter { allowed.contains($0) })
        return filtered.isEmpty ? "Unnamed" : filtered
    }

    private mutating func increment(_ source: Source) {
        switch source {
        case .app: summary.fromApps += 1
        case .package: summary.fromPackages += 1
        case .diskImage: summary.fromDiskImages += 1
        }
    }

    private func log(_ message: String) {
        emit(message)
    }

    private mutating func record(_ detail: String) {
        summary.details.append(detail)
    }

    private func logFinalSummary() {
        log("🧮 Summary:")
        log("   ✔️ Total icons added from scan: \(summary.totalExtracted)")
        log("       - From .app bundles: \(summary.fromApps)")
        log("       - From .pkg installers: \(summary.fromPackages)")
        log("       - From .dmg images: \(summary.fromDiskImages)")
        log("   ⏩ Icons skipped (duplicates): \(summary.skipped)")
        log("   ❌ Icons missing or not found: \(summary.missing)")
    }

    private mutating func writeSummaryFile() {
        let date = Date.now.formatted(.iso8601.year().month().day())
        let fileURL = outputFolder.appending(path: "_\(date)_icon_extraction_summary.txt")

        let report = """
        ======== SUMMARY REPORT ========
        ✔️  Total icons added from scan: \(summary.totalExtracted)
            - From .app bundles: \(summary.fromApps)
            - From .pkg installers: \(summary.fromPackages)
            - From .dmg images: \(summary.fromDiskImages)
        ⏩ Icons skipped (duplicates): \(summary.skipped)
        ❌ Icons missing or not found: \(summary.missing)
        ----------------------------------------

        Detailed log:

        \(summary.details.joined(separator: "\n"))

        """

        do {
            try report.write(to: fileURL, atomically: true, encoding: .utf8)
            summary.summaryFileURL = fileURL
            log("📄 Summary report written to: \(fileURL.path)")
        } catch {
            log("❌ Could not write summary report: \(error.localizedDescription)")
        }
    }
}
