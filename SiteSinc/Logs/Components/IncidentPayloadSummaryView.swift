import SwiftUI

struct IncidentPayloadSummaryView: View {
    let log: Log

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let band = log.severityBand {
                HStack {
                    Text("Severity")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(band.label)
                        .font(.body)
                        .foregroundColor(band.color)
                }
            }

            if let occurredAt = log.occurredAt {
                row("Occurred", formatDate(occurredAt))
            }
            if let reportedAt = log.reportedAt {
                row("Reported", formatDate(reportedAt))
            }

            if let injury = log.injuryInvolved {
                row("Injury involved", injury ? "Yes" : "No")
            }

            if log.regulatoryNotifiable == true {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("HSE reportable (RIDDOR)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }
            }

            if let riddor = log.incidentPayload?.riddor, !riddor.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RIDDOR criteria")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(riddor, id: \.self) { key in
                        Text("• \(riddorLabels[key] ?? key)")
                            .font(.subheadline)
                    }
                }
            }

            if let bodyMap = log.incidentPayload?.bodyMap, !bodyMap.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Injury locations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(bodyMap.map { bodyRegionLabel($0) }.joined(separator: ", "))
                        .font(.subheadline)
                }
            }

            if let rootCause = log.rootCauseSummary, !rootCause.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Root cause")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(rootCause)
                        .font(.subheadline)
                }
            }

            if let fiveWhys = log.incidentPayload?.fiveWhys, !fiveWhys.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("5 Whys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(Array(fiveWhys.enumerated()), id: \.offset) { index, why in
                        Text("\(index + 1). \(why)")
                            .font(.subheadline)
                    }
                }
            }

            if let url = log.incidentPayload?.relatedToolboxTalkUrl, !url.isEmpty {
                row("Toolbox talk", url)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
