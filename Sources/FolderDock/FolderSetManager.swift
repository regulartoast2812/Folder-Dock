import SwiftUI

struct FolderSetManager: View {
    @ObservedObject var store: FolderStore
    @ObservedObject var controller: DockController
    @State private var newSetName = ""
    @State private var editingSetID: UUID?
    @State private var editingName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Sets")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Keep shared assets and each project’s folders separate.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: controller.closeBrowser) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Close manager")
            }
            .padding(.horizontal, 16)
            .frame(height: 62)

            Divider()

            List {
                ForEach(store.folderSets) { set in
                    HStack(spacing: 10) {
                        Button {
                            store.selectSet(set)
                        } label: {
                            Image(systemName: set.id == store.selectedSetID ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(set.id == store.selectedSetID ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Use \(set.name)")

                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)

                        if editingSetID == set.id {
                            TextField("Set name", text: $editingName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { finishEditing(set) }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(set.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(set.folders.count) saved folder\(set.folders.count == 1 ? "" : "s")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if editingSetID == set.id {
                            Button(action: { finishEditing(set) }) {
                                Image(systemName: "checkmark")
                            }
                            .buttonStyle(.plain)
                            .help("Save name")
                        } else {
                            Button {
                                editingSetID = set.id
                                editingName = set.name
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.plain)
                            .help("Rename \(set.name)")
                        }

                        Button(role: .destructive) {
                            store.deleteSet(set)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .disabled(store.folderSets.count == 1)
                        .help(store.folderSets.count == 1 ? "Keep at least one folder set" : "Delete \(set.name)")
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)

            Divider()

            HStack(spacing: 10) {
                TextField("New folder set (e.g. Client A)", text: $newSetName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addSet)
                Button("Add", action: addSet)
                    .disabled(newSetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 720, height: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private func addSet() {
        store.createSet(named: newSetName)
        newSetName = ""
    }

    private func finishEditing(_ set: FolderSet) {
        store.renameSet(set, to: editingName)
        editingSetID = nil
    }
}
