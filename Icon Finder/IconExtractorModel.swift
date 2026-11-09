import Foundation
import Observation

struct SearchFolder: Identifiable, Hashable {
    let path: String
    let isDefault: Bool
    var isEnabled: Bool

    var id: String { path }
    var url: URL { URL(filePath: path, directoryHint: .isDirectory) }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
}

@Observable
final class IconExtractorModel {
    /// The search locations from the original script.
    static let defaultFolderPaths = [
        "/Applications",
        "/System/Applications",
        "/Library",
        "/System/Library",
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads").path,
    ]

    private enum DefaultsKey {
        static let customFolders = "customSearchFolders"
        static let disabledFolders = "disabledSearchFolders"
        static let outputFolder = "outputFolder"
    }

    var folders: [SearchFolder] {
        didSet { saveFolders() }
    }

    var outputFolder: URL {
        didSet { UserDefaults.standard.set(outputFolder.path, forKey: DefaultsKey.outputFolder) }
    }

    private(set) var log: [LogEntry] = []
    private(set) var summary: ExtractionSummary?
    private(set) var isRunning = false

    private var runTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let custom = defaults.stringArray(forKey: DefaultsKey.customFolders) ?? []
        let disabled = Set(defaults.stringArray(forKey: DefaultsKey.disabledFolders) ?? [])

        folders = Self.defaultFolderPaths.map {
            SearchFolder(path: $0, isDefault: true, isEnabled: !disabled.contains($0))
        } + custom.map {
            SearchFolder(path: $0, isDefault: false, isEnabled: !disabled.contains($0))
        }

        if let savedOutput = defaults.string(forKey: DefaultsKey.outputFolder) {
            outputFolder = URL(filePath: savedOutput, directoryHint: .isDirectory)
        } else {
            outputFolder = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Desktop/MacAppIcons", directoryHint: .isDirectory)
        }
    }

    // MARK: - Folders

    func addFolders(_ urls: [URL]) {
        for url in urls where !folders.contains(where: { $0.path == url.path }) {
            folders.append(SearchFolder(path: url.path, isDefault: false, isEnabled: true))
        }
    }

    func removeFolder(_ folder: SearchFolder) {
        folders.removeAll { $0.id == folder.id && !$0.isDefault }
    }

    private func saveFolders() {
        let defaults = UserDefaults.standard
        defaults.set(folders.filter { !$0.isDefault }.map(\.path), forKey: DefaultsKey.customFolders)
        defaults.set(folders.filter { !$0.isEnabled }.map(\.path), forKey: DefaultsKey.disabledFolders)
    }

    // MARK: - Running

    var canStart: Bool {
        !isRunning && folders.contains(where: \.isEnabled)
    }

    func start() {
        guard canStart else { return }

        log.removeAll()
        summary = nil
        isRunning = true

        let stream = IconExtractor.run(
            searchFolders: folders.filter(\.isEnabled).map(\.url),
            outputFolder: outputFolder
        )

        runTask = Task {
            for await event in stream {
                switch event {
                case .log(let message):
                    log.append(LogEntry(message: message))
                case .finished(let result):
                    summary = result
                }
            }
            isRunning = false
        }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        log.append(LogEntry(message: "⏹ Extraction stopped."))
    }
}
