import SwiftUI

struct BodyMapRegion: Identifiable {
    let id: String
    let label: String
    let rect: CGRect
}

struct BodyMapSelectorView: View {
    @Binding var selectedRegions: Set<String>
    @State private var viewSide: BodyViewSide = .front

    private var regions: [BodyMapRegion] {
        layout(for: viewSide)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("View", selection: $viewSide) {
                Text("Front").tag(BodyViewSide.front)
                Text("Back").tag(BodyViewSide.back)
            }
            .pickerStyle(.segmented)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                    ForEach(regions) { region in
                        let scaled = CGRect(
                            x: region.rect.minX * w,
                            y: region.rect.minY * h,
                            width: region.rect.width * w,
                            height: region.rect.height * h
                        )
                        Button {
                            if selectedRegions.contains(region.id) {
                                selectedRegions.remove(region.id)
                            } else {
                                selectedRegions.insert(region.id)
                            }
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(selectedRegions.contains(region.id) ? Color.red.opacity(0.6) : Color.blue.opacity(0.15))
                                .overlay(
                                    Text(region.label)
                                        .font(.system(size: 8))
                                        .foregroundColor(selectedRegions.contains(region.id) ? .white : .secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(2)
                                )
                        }
                        .buttonStyle(.plain)
                        .frame(width: scaled.width, height: scaled.height)
                        .position(x: scaled.midX, y: scaled.midY)
                    }
                }
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if !selectedRegions.isEmpty {
                Text("Selected: \(selectedRegions.sorted().map { bodyRegionLabel($0) }.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func layout(for side: BodyViewSide) -> [BodyMapRegion] {
        let positions: [String: CGRect] = [
            "head": CGRect(x: 0.35, y: 0.02, width: 0.30, height: 0.10),
            "neck": CGRect(x: 0.40, y: 0.12, width: 0.20, height: 0.05),
            "chest": CGRect(x: 0.30, y: 0.17, width: 0.40, height: 0.12),
            "abdomen": CGRect(x: 0.32, y: 0.29, width: 0.36, height: 0.10),
            "left_upper_arm": CGRect(x: 0.12, y: 0.18, width: 0.16, height: 0.14),
            "right_upper_arm": CGRect(x: 0.72, y: 0.18, width: 0.16, height: 0.14),
            "left_forearm": CGRect(x: 0.08, y: 0.32, width: 0.14, height: 0.14),
            "right_forearm": CGRect(x: 0.78, y: 0.32, width: 0.14, height: 0.14),
            "left_hand": CGRect(x: 0.04, y: 0.46, width: 0.12, height: 0.08),
            "right_hand": CGRect(x: 0.84, y: 0.46, width: 0.12, height: 0.08),
            "left_thigh": CGRect(x: 0.30, y: 0.40, width: 0.18, height: 0.16),
            "right_thigh": CGRect(x: 0.52, y: 0.40, width: 0.18, height: 0.16),
            "left_shin": CGRect(x: 0.30, y: 0.56, width: 0.18, height: 0.16),
            "right_shin": CGRect(x: 0.52, y: 0.56, width: 0.18, height: 0.16),
            "left_foot": CGRect(x: 0.28, y: 0.72, width: 0.20, height: 0.08),
            "right_foot": CGRect(x: 0.52, y: 0.72, width: 0.20, height: 0.08)
        ]
        return bodyParts.compactMap { part -> BodyMapRegion? in
            guard let rect = positions[part] else { return nil }
            let id = bodyRegionId(view: side, part: part)
            return BodyMapRegion(id: id, label: bodyRegionLabel(id), rect: rect)
        }
    }
}
