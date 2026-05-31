import SwiftUI

struct SeverityPickerView: View {
    @Binding var selectedBand: SeverityBand?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Severity")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(SeverityBand.allCases) { band in
                    Button {
                        if selectedBand == band {
                            selectedBand = nil
                        } else {
                            selectedBand = band
                        }
                    } label: {
                        Text(band.label)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(selectedBand == band ? band.color : Color(.systemGray5))
                            .foregroundColor(selectedBand == band ? .white : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
