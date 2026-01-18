//
//  UserQualificationsView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 18/01/2026.
//

import SwiftUI

struct UserQualificationsView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss
    
    @State private var qualifications: [UserQualificationGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var totalQualifications: Int = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if qualifications.isEmpty {
                    emptyStateView
                } else {
                    qualificationsList
                }
            }
            .navigationTitle("My Qualifications")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .task {
            await loadQualifications()
        }
    }
    
    // MARK: - Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading qualifications...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Unable to Load")
                .font(.headline)
            
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button("Try Again") {
                Task {
                    await loadQualifications()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 56))
                .foregroundColor(Color(hex: "#3B82F6").opacity(0.6))
            
            Text("No Qualifications")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("You don't have any qualifications assigned yet. Contact your administrator to add qualifications.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    private var qualificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Summary Card
                summaryCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                
                ForEach(qualifications) { group in
                    qualificationCard(group)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 24)
        }
    }
    
    private var summaryCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(qualifications.count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#3B82F6"))
                Text("Active")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(expiredCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(expiredCount > 0 ? Color(hex: "#EF4444") : .secondary)
                Text("Expired")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(expiringSoonCount)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(expiringSoonCount > 0 ? Color(hex: "#F59E0B") : .secondary)
                Text("Expiring Soon")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func qualificationCard(_ group: UserQualificationGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(group.qualification.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                statusBadge(for: group)
            }
            
            // Current record details
            if let currentRecord = group.records.first(where: { $0.isCurrent == true }) ?? group.records.first {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    if let obtainedAt = currentRecord.obtainedAt {
                        infoRow(icon: "calendar.badge.checkmark", label: "Obtained", value: formatDate(obtainedAt))
                    }
                    
                    if let expiresAt = currentRecord.expiresAt {
                        infoRow(
                            icon: "calendar.badge.clock",
                            label: "Expires",
                            value: formatDate(expiresAt),
                            valueColor: currentRecord.isExpired ? Color(hex: "#EF4444") : (isExpiringSoon(expiresAt) ? Color(hex: "#F59E0B") : .primary)
                        )
                    }
                    
                    if let cscsCardNumber = currentRecord.cscsCardNumber, !cscsCardNumber.isEmpty {
                        infoRow(icon: "creditcard", label: "CSCS Card", value: cscsCardNumber)
                        
                        if let status = currentRecord.cscsValidationStatus {
                            infoRow(
                                icon: validationStatusIcon(status),
                                label: "Validation",
                                value: validationStatusText(status),
                                valueColor: validationStatusColor(status)
                            )
                        }
                    }
                    
                    if let notes = currentRecord.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "note.text")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            
                            Text(notes)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                        }
                    }
                    
                    if let fileName = currentRecord.fileName {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#3B82F6"))
                                .frame(width: 20)
                            
                            Text(fileName)
                                .font(.system(size: 13))
                                .foregroundColor(Color(hex: "#3B82F6"))
                                .lineLimit(1)
                        }
                    }
                }
                
                // Show renewal history count if there are multiple records
                if group.records.count > 1 {
                    Divider()
                    
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Text("\(group.records.count - 1) previous record\(group.records.count > 2 ? "s" : "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func statusBadge(for group: UserQualificationGroup) -> some View {
        let currentRecord = group.records.first(where: { $0.isCurrent == true }) ?? group.records.first
        
        if let record = currentRecord {
            if record.isExpired {
                return AnyView(
                    Text("EXPIRED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#EF4444"))
                        .cornerRadius(4)
                )
            } else if let expiresAt = record.expiresAt, isExpiringSoon(expiresAt) {
                return AnyView(
                    Text("EXPIRING SOON")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#F59E0B"))
                        .cornerRadius(4)
                )
            } else {
                return AnyView(
                    Text("VALID")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "#10B981"))
                        .cornerRadius(4)
                )
            }
        }
        
        return AnyView(EmptyView())
    }
    
    private func infoRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(valueColor)
        }
    }
    
    // MARK: - Helper Functions
    
    private var expiredCount: Int {
        qualifications.filter { group in
            let current = group.records.first(where: { $0.isCurrent == true }) ?? group.records.first
            return current?.isExpired == true
        }.count
    }
    
    private var expiringSoonCount: Int {
        qualifications.filter { group in
            let current = group.records.first(where: { $0.isCurrent == true }) ?? group.records.first
            guard let record = current, !record.isExpired, let expiresAt = record.expiresAt else { return false }
            return isExpiringSoon(expiresAt)
        }.count
    }
    
    private func isExpiringSoon(_ dateString: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return false
        }
        
        let thirtyDaysFromNow = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        return date <= thirtyDaysFromNow && date > Date()
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: date)
    }
    
    private func validationStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "valid": return "checkmark.seal.fill"
        case "invalid", "expired": return "xmark.seal.fill"
        case "pending": return "clock.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }
    
    private func validationStatusText(_ status: String) -> String {
        switch status.lowercased() {
        case "valid": return "Verified"
        case "invalid": return "Invalid"
        case "expired": return "Expired"
        case "pending": return "Pending"
        case "error": return "Error"
        default: return status.capitalized
        }
    }
    
    private func validationStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "valid": return Color(hex: "#10B981")
        case "invalid", "expired", "error": return Color(hex: "#EF4444")
        case "pending": return Color(hex: "#F59E0B")
        default: return .secondary
        }
    }
    
    // MARK: - Data Loading
    
    private func loadQualifications() async {
        guard let token = sessionManager.token else {
            errorMessage = "Not authenticated"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await APIClient.fetchMyQualifications(token: token)
            await MainActor.run {
                self.qualifications = response.qualifications
                self.totalQualifications = response.totalQualifications
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

#Preview {
    UserQualificationsView()
        .environmentObject(SessionManager())
}
