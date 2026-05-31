import SwiftUI
import Charts

struct HSEDashboardView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @State private var summary: HSESummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading HSE summary...")
                    .padding(.top, 40)
            } else if let summary {
                VStack(spacing: 16) {
                    kpiGrid(summary)
                    if let monthly = summary.monthly, !monthly.isEmpty {
                        monthlyChart(monthly)
                    }
                    breakdownSection("By type", items: summary.byType ?? [])
                    breakdownSection("By severity", items: summary.bySeverity ?? [])
                    breakdownSection("By location", items: summary.byLocation ?? [])
                    if let repeatHazards = summary.repeatHazards, !repeatHazards.isEmpty {
                        breakdownSection("Repeat hazards", items: repeatHazards)
                    }
                }
                .padding()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle("HSE Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadSummary() }
        .task { await loadSummary() }
    }

    private func kpiGrid(_ summary: HSESummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiCard("Total", value: summary.total, color: .blue)
            kpiCard("Open", value: summary.open, color: .orange)
            kpiCard("Closed", value: summary.closed, color: .green)
            kpiCard("Overdue", value: summary.overdue, color: .red)
            kpiCard("Injuries", value: summary.injuries, color: .red)
            kpiCard("RIDDOR", value: summary.notifiable, color: .orange)
            kpiCard("Near misses", value: summary.nearMisses, color: .purple)
            kpiCard("Open CAPA", value: summary.openCorrectiveActions, color: .orange)
            kpiCard("Overdue CAPA", value: summary.overdueCorrectiveActions, color: .red)
            if let ratio = summary.nearMissToIncidentRatio {
                kpiCard("NM ratio", value: Int(ratio), color: .indigo, suffix: ":1")
            }
            if let avgDays = summary.avgDaysToClose {
                kpiCard("Avg close", value: Int(avgDays), color: .teal, suffix: " days")
            }
        }
    }

    private func kpiCard(_ title: String, value: Int, color: Color, suffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value)\(suffix)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func monthlyChart(_ items: [HSEMonthlyItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monthly trend")
                .font(.headline)
            Chart(items) { item in
                BarMark(
                    x: .value("Month", item.month),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(Color.accentColor)
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func breakdownSection(_ title: String, items: [HSEBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if items.isEmpty {
                Text("No data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                            .font(.subheadline)
                        Spacer()
                        Text("\(item.count)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func loadSummary() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let fetched = try await APIClient.fetchProjectHSESummary(projectId: projectId, token: token)
            await MainActor.run {
                summary = fetched
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}
