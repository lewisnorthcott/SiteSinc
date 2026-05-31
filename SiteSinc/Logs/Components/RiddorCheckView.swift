import SwiftUI

struct RiddorCheckView: View {
    @Binding var selectedKeys: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RIDDOR reportability check")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            if !selectedKeys.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Likely RIDDOR reportable — report online at hse.gov.uk/riddor. A competent person should confirm before submitting.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            ForEach(riddorCriteria) { criterion in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { selectedKeys.contains(criterion.key) },
                        set: { on in
                            if on { selectedKeys.insert(criterion.key) }
                            else { selectedKeys.remove(criterion.key) }
                        }
                    )) {
                        Text(criterion.label)
                            .font(.subheadline)
                    }
                    if let hint = criterion.hint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(criterion.deadline)
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
