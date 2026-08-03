import SwiftUI

/// Version history for a SiteDrive file. Tapping a revision previews it.
struct SiteDriveVersionsSheet: View {
    let revisions: [SiteDriveRevision]
    let selectedRevisionId: Int?
    let onSelect: (SiteDriveRevision) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(revisions) { revision in
                Button {
                    onSelect(revision)
                } label: {
                    HStack(spacing: 12) {
                        Text("v\(revision.versionNumber)")
                            .font(.system(.subheadline, design: BrandChrome.bodyDesign).weight(.semibold))
                            .foregroundColor(BrandChrome.accent)
                            .frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.dateFormatter.string(from: revision.createdAt))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            HStack(spacing: 6) {
                                if let size = revision.formattedSize {
                                    Text(size)
                                }
                                if let uploader = revision.uploadedBy?.email {
                                    Text(uploader)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(BrandChrome.mutedLabel)
                            if let notes = revision.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundColor(BrandChrome.mutedLabel)
                                    .lineLimit(2)
                            }
                        }
                        Spacer()
                        if revision.id == selectedRevisionId {
                            Image(systemName: "checkmark")
                                .foregroundColor(BrandChrome.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Version History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
