import SwiftUI

struct RFIRow: View {
    let unifiedRFI: UnifiedRFI

    var body: some View {
        HStack {
            Circle()
                .fill(unifiedRFI.status?.lowercased() == "open" ? Color.green : (unifiedRFI.status?.lowercased() == "draft" ? Color.orange : Color.blue.opacity(0.2)))
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(unifiedRFI.title ?? "Untitled RFI")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Text(unifiedRFI.number == 0 ? "Draft" : "RFI-\(unifiedRFI.number)")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.leading, 8)

            Spacer()

            Text(unifiedRFI.status?.uppercased() ?? "UNKNOWN")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(unifiedRFI.status?.lowercased() == "draft" ? .orange : .blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((unifiedRFI.status?.lowercased() == "draft" ? Color.orange : Color.blue).opacity(0.1))
                .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .accessibilityLabel("RFI \(unifiedRFI.number == 0 ? "Draft" : "Number \(unifiedRFI.number)"), Title: \(unifiedRFI.title ?? "Untitled RFI"), Status: \(unifiedRFI.status?.uppercased() ?? "UNKNOWN")")
    }
}

