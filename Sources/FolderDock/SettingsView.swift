import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: FolderStore

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
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .padding()
    }
}
