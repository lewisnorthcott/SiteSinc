import SwiftUI

/// Destination picker for moving a file or folder. Shows the full folder tree
/// (indented); moving a folder hides its own subtree so it can't be moved
/// into itself.
struct SiteDriveMoveSheet: View {
    let folderTree: [SiteDriveFolder]
    let target: SiteDriveMoveTarget
    let onSelect: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    private struct FlatFolder: Identifiable {
        let folder: SiteDriveFolder
        let depth: Int
        var id: Int { folder.id }
    }

    private var movedFolderId: Int? {
        if case .folder(let folder) = target { return folder.id }
        return nil
    }

    private var flattened: [FlatFolder] {
        var result: [FlatFolder] = []
        func walk(_ folders: [SiteDriveFolder], depth: Int) {
            for folder in folders.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
                if folder.id == movedFolderId { continue }
                result.append(FlatFolder(folder: folder, depth: depth))
                walk(folder.subfolders ?? [], depth: depth + 1)
            }
        }
        walk(folderTree, depth: 0)
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onSelect(nil)
                    } label: {
                        Label("Root", systemImage: "externaldrive")
                            .foregroundColor(.primary)
                    }
                }
                if !flattened.isEmpty {
                    Section("Folders") {
                        ForEach(flattened) { entry in
                            Button {
                                onSelect(entry.folder.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: entry.folder.isPrivate ? "folder.fill.badge.person.crop" : "folder.fill")
                                        .foregroundColor(BrandChrome.accent)
                                    Text(entry.folder.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, CGFloat(entry.depth) * 20)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move \"\(target.displayName)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
