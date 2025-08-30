import SwiftUI

// Reusable group row/card used by Documents and Drawings screens

struct GroupRow: View {
    let groupKey: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(width: 24, height: 24)

            Text(groupKey)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#3B82F6"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#3B82F6").opacity(0.1))
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

// Small pill badge used for metadata chips
struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(hex: "#3B82F6"))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: "#3B82F6").opacity(0.1))
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

struct GroupCard: View {
    let groupKey: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(hex: "#3B82F6"))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#3B82F6"))
            }

            Spacer()

            Text(groupKey)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)

            Text("Items")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(hex: "#6B7280"))
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, idealHeight: 140, maxHeight: 150)
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}


