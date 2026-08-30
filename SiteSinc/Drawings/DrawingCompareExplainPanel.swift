import SwiftUI

struct DrawingCompareLegendCard: View {
    let currentRevision: Revision?
    let comparisonRevision: Revision?
    let baseIsNewer: Bool
    let isComputing: Bool
    let isLoadingComparison: Bool
    let error: String?
    let drawingId: Int
    let token: String
    let pageNumber: Int
    let overlayJPEG: String?
    let fromPageText: String
    let toPageText: String

    private var olderRevision: Revision? {
        baseIsNewer ? comparisonRevision : currentRevision
    }

    private var newerRevision: Revision? {
        baseIsNewer ? currentRevision : comparisonRevision
    }

    private func shortRev(_ revision: Revision?, fallback: String) -> String {
        guard let revision else { return fallback }
        return revision.revisionNumber ?? String(revision.versionNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(color: Color(hex: "#111827"), label: "Unchanged")
            legendRow(color: Color(hex: "#ef4444"), label: shortRev(olderRevision, fallback: "Older"))
            legendRow(color: Color(hex: "#2563eb"), label: shortRev(newerRevision, fallback: "Newer"))

            if isLoadingComparison || isComputing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(isLoadingComparison ? "Loading…" : "Redline…")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
            }

            if let error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#DC2626"))
                    .lineLimit(2)
            }

            DrawingCompareExplainPanel(
                drawingId: drawingId,
                fromRevisionId: currentRevision?.id,
                toRevisionId: comparisonRevision?.id,
                token: token,
                page: pageNumber,
                overlayJPEG: overlayJPEG,
                fromPageText: fromPageText,
                toPageText: toPageText
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#D1D5DB"), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
    }

    private func legendRow(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(hex: "#9CA3AF"), lineWidth: 0.5)
                )
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(hex: "#4B5563"))
                .lineLimit(1)
        }
    }
}

struct DrawingCompareExplainPanel: View {
    let drawingId: Int
    let fromRevisionId: Int?
    let toRevisionId: Int?
    let token: String
    let page: Int
    let overlayJPEG: String?
    let fromPageText: String
    let toPageText: String

    @State private var isLoading = false
    @State private var error: String?
    @State private var result: DrawingChangeExplanation?
    @State private var showResult = false

    private var canExplain: Bool {
        guard let fromRevisionId, let toRevisionId else { return false }
        return fromRevisionId != toRevisionId && !token.isEmpty
    }

    var body: some View {
        if canExplain {
            VStack(alignment: .leading, spacing: 4) {
                Button(action: explain) {
                    HStack(spacing: 3) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.55)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(isLoading ? "Reading…" : (result == nil ? "Explain" : "Results"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(hex: "#2563EB"))
                .disabled(isLoading)

                if let error {
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#DC2626"))
                        .lineLimit(3)
                }
            }
            .onChange(of: fromRevisionId) { _, _ in result = nil; error = nil }
            .onChange(of: toRevisionId) { _, _ in result = nil; error = nil }
            .onChange(of: page) { _, _ in result = nil; error = nil }
            .sheet(isPresented: $showResult) {
                NavigationStack {
                    ScrollView {
                        if let result {
                            explanationContent(result)
                                .padding()
                        }
                    }
                    .navigationTitle("Drawing changes")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Re-explain") {
                                showResult = false
                                result = nil
                                explain()
                            }
                            .disabled(isLoading)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showResult = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func explain() {
        if result != nil, !isLoading {
            showResult = true
            return
        }
        guard let fromRevisionId, let toRevisionId else { return }
        isLoading = true
        error = nil
        Task {
            do {
                let data = try await APIClient.compareExplainDrawing(
                    drawingId: drawingId,
                    fromRevisionId: fromRevisionId,
                    toRevisionId: toRevisionId,
                    page: page,
                    overlayImage: overlayJPEG,
                    fromPageText: fromPageText.isEmpty ? nil : fromPageText,
                    toPageText: toPageText.isEmpty ? nil : toPageText,
                    token: token
                )
                await MainActor.run {
                    result = data
                    isLoading = false
                    showResult = true
                }
            } catch {
                await MainActor.run {
                    self.error = (error as? APIError)?.displayMessage ?? error.localizedDescription
                    result = nil
                    isLoading = false
                }
            }
        }
    }

    @ViewBuilder
    private func explanationContent(_ result: DrawingChangeExplanation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#374151"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !result.visualChanges.isEmpty {
                sectionTitle("Visual changes")
                ForEach(Array(result.visualChanges.enumerated()), id: \.offset) { _, change in
                    bullet(change, color: Color(hex: "#374151"))
                }
            }

            if result.likelyCauses.isEmpty {
                Text("No likely cause found in project records for this revision pair.")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#6B7280"))
            } else {
                sectionTitle("Likely causes")
                ForEach(Array(result.likelyCauses.enumerated()), id: \.offset) { _, cause in
                    causeCard(cause)
                }
            }

            if !result.unmatchedChanges.isEmpty {
                sectionTitle("Unmatched")
                ForEach(Array(result.unmatchedChanges.enumerated()), id: \.offset) { _, change in
                    bullet(change, color: Color(hex: "#6B7280"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(hex: "#6B7280"))
            .tracking(0.4)
    }

    private func bullet(_ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 14))
        .foregroundColor(color)
    }

    private func causeCard(_ cause: ChangeExplanationCause) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Text(cause.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "#1F2937"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(cause.confidence.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(confidenceBackground(cause.confidence))
                    .foregroundColor(confidenceForeground(cause.confidence))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(cause.explanation)
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#4B5563"))
                .fixedSize(horizontal: false, vertical: true)
            if !cause.sources.isEmpty {
                Text(cause.sources.map(\.label).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#4B5563"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(hex: "#F9FAFB"))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#E5E7EB"), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func confidenceBackground(_ confidence: ChangeExplanationConfidence) -> Color {
        switch confidence {
        case .high: return Color(hex: "#D1FAE5")
        case .medium: return Color(hex: "#FEF3C7")
        case .low: return Color(hex: "#F3F4F6")
        }
    }

    private func confidenceForeground(_ confidence: ChangeExplanationConfidence) -> Color {
        switch confidence {
        case .high: return Color(hex: "#065F46")
        case .medium: return Color(hex: "#92400E")
        case .low: return Color(hex: "#4B5563")
        }
    }
}
