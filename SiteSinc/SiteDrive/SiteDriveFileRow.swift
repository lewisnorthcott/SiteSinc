import SwiftUI

struct SiteDriveFolderRow: View {
    let folder: SiteDriveFolder
    var isPinnedOffline: Bool = false

    private var subfolderCount: Int { folder.subfolders?.count ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: folder.isPrivate ? "folder.fill.badge.person.crop" : "folder.fill")
                .font(.system(size: 22))
                .foregroundColor(BrandChrome.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(folder.name)
                        .font(.system(.body, design: BrandChrome.bodyDesign).weight(.medium))
                        .lineLimit(1)
                    if folder.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(BrandChrome.mutedLabel)
                    }
                }
                if subfolderCount > 0 {
                    Text(subfolderCount == 1 ? "1 subfolder" : "\(subfolderCount) subfolders")
                        .font(.caption)
                        .foregroundColor(BrandChrome.mutedLabel)
                }
            }
            if isPinnedOffline {
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SiteDriveFileRow: View {
    let item: SiteDriveItem
    var isAvailableOffline: Bool = false

    private var subtitle: String {
        var parts: [String] = []
        if let version = item.latestRevision?.versionNumber, version > 1 {
            parts.append("v\(version)")
        }
        if let size = item.latestRevision?.formattedSize {
            parts.append(size)
        }
        parts.append(Self.dateFormatter.string(from: item.updatedAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: item.iconColor))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(.body, design: BrandChrome.bodyDesign))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(BrandChrome.mutedLabel)
            }
            if isAvailableOffline {
                Spacer()
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 2)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
