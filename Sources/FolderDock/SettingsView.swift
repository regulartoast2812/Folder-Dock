import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var updateController: UpdateController

    var body: some View {
        Form {
            Section("Saved Folders") {
                if store.folders.isEmpty {
                    Text("No folders saved yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.folders) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading) {
                            Text(folder.name)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            store.remove(folder)
                        }
                    }
                }
            }

            Section("How it works") {
                Text("Move the pointer to the top-center edge of any display to reveal Folder Dock. It hides shortly after the pointer leaves.")
                    .font(.callout)
            }

            Section("Updates") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Folder Dock \(versionText)")
                        Text(updateStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updateController.isUpdateAvailable ? "Update" : "Check Now") {
                        if updateController.isUpdateAvailable {
                            updateController.checkForUpdates()
                        } else {
                            updateController.probeForUpdate()
                        }
                    }
                    .disabled(updateController.isChecking)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .padding()
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        return "\(version) (B\(build))"
    }

    private var updateStatusText: String {
        if updateController.isChecking { return "Checking for updates…" }
        if let availableVersion = updateController.availableVersion {
            return "Version \(availableVersion) is available."
        }
        return "Updates are checked securely from GitHub Releases."
    }
}
