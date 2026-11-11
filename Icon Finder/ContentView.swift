import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = IconExtractorModel()
    @State private var importTarget: ImportTarget = .searchFolders
    @State private var isImporterPresented = false

    private enum ImportTarget {
        case searchFolders
        case outputFolder
    }

    var body: some View {
        HStack(spacing: 0) {
            brandingPanel

            NavigationSplitView {
                settingsForm
                    .navigationSplitViewColumnWidth(min: 320, ideal: 360)
            } detail: {
                logView
            }
        }
        .navigationTitle("IconFinder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        model.stop()
                    }
                } else {
                    Button("Start Scan", systemImage: "magnifyingglass") {
                        model.start()
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canStart)
                }
            }
        }
        // importTarget is kept separate from the presentation flag because the
        // importer resets isPresented before the completion handler runs.
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: importTarget == .searchFolders
        ) { result in
            guard case .success(let urls) = result else { return }
            switch importTarget {
            case .searchFolders:
                model.addFolders(urls)
            case .outputFolder:
                if let url = urls.first {
                    model.outputFolder = url
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsForm: some View {
        Form {
            Section("Search Locations") {
                ForEach($model.folders) { $folder in
                    HStack {
                        Toggle(isOn: $folder.isEnabled) {
                            Text(folder.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if !folder.isDefault {
                            Button("Remove", systemImage: "minus.circle.fill") {
                                model.removeFolder(folder)
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                Button("Add Folder…", systemImage: "plus") {
                    importTarget = .searchFolders
                    isImporterPresented = true
                }
            }
            .disabled(model.isRunning)

            Section("Output Folder") {
                Text(model.outputFolder.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack {
                    Button("Choose…") {
                        importTarget = .outputFolder
                        isImporterPresented = true
                    }
                    .disabled(model.isRunning)

                    Button("Show in Finder") {
                        NSWorkspace.shared.open(model.outputFolder)
                    }
                    .disabled(!FileManager.default.fileExists(atPath: model.outputFolder.path))
                }
            }

            if let summary = model.summary {
                Section("Summary") {
                    LabeledContent("Total extracted", value: summary.totalExtracted, format: .number)
                    LabeledContent("From .app bundles", value: summary.fromApps, format: .number)
                    LabeledContent("From .pkg installers", value: summary.fromPackages, format: .number)
                    LabeledContent("From .dmg images", value: summary.fromDiskImages, format: .number)
                    LabeledContent("Skipped (duplicates)", value: summary.skipped, format: .number)
                    LabeledContent("Missing or not found", value: summary.missing, format: .number)

                    if let fileURL = summary.summaryFileURL {
                        Button("Open Summary Report") {
                            NSWorkspace.shared.open(fileURL)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Branding

    /// Version string built from the bundle's marketing version and build number, e.g. "Version 1.0 (1)".
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    private var brandingPanel: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                .accessibilityHidden(true)

            Text("IconFinder")
                .font(.title2.bold())

            Spacer()

            Text(versionText)
                .font(.caption.weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.top, 60)
        .padding(.bottom, 20)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        // Light sky blue to deep navy, so the blue logo sits on the lighter end.
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.62, green: 0.82, blue: 1.00),
                    Color(red: 0.22, green: 0.52, blue: 0.95),
                    Color(red: 0.06, green: 0.17, blue: 0.50),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Log

    private var logView: some View {
        ScrollViewReader { proxy in
            List(model.log) { entry in
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .id(entry.id)
            }
            .overlay {
                if model.log.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "app.dashed",
                        description: Text("Choose your search locations and output folder, then click Start Scan.")
                    )
                }
            }
            .onChange(of: model.log.last?.id) { _, lastID in
                if let lastID {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Extracting icons…")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(.bar)
            }
        }
    }
}

#Preview {
    ContentView()
}
