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
        NavigationSplitView {
            settingsForm
                .navigationSplitViewColumnWidth(min: 320, ideal: 360)
        } detail: {
            logView
        }
        .navigationTitle("IconFinder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if model.isRunning {
                    Button("Stop", systemImage: "stop.fill") {
                        model.stop()
                    }
                } else {
                    Button("Extract Icons", systemImage: "play.fill") {
                        model.start()
                    }
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
                        description: Text("Choose your search locations and output folder, then click Extract Icons.")
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
