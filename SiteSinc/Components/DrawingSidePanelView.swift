import SwiftUI

struct DrawingSidePanelView: View {
    let drawing: Drawing
    let selectedRevision: Revision?
    @Binding var isSidePanelOpen: Bool

    private let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private func formatDate(_ dateString: String?) -> String {
        guard let dateString = dateString, !dateString.isEmpty else { return "N/A" }
        if let date = isoDateFormatter.date(from: dateString) {
            return displayDateFormatter.string(from: date)
        }
        let simplerIsoFormatter = ISO8601DateFormatter()
        simplerIsoFormatter.formatOptions = .withInternetDateTime
        if let date = simplerIsoFormatter.date(from: dateString) {
            return displayDateFormatter.string(from: date)
        }
        return "Invalid Date"
    }
    
    private var revisionToDisplay: Revision? {
        selectedRevision ?? drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber })
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack {
            Text("Drawing Information")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            Spacer()
            Button(action: {
                withAnimation(.easeInOut) { isSidePanelOpen = false }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(hex: "#9CA3AF"))
            }
        }
        .padding([.top, .horizontal])
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var revisionDetailsSection: some View {
        if let revision = revisionToDisplay {
            InfoRow(label: "Revision Number", value: revision.revisionNumber ?? String(revision.versionNumber))
            InfoRow(label: "Revision Status", value: revision.status)
            InfoRow(label: "Revision Date", value: formatDate(revision.uploadedAt))
        } else {
            InfoRow(label: "Revision", value: "Not Available")
        }
    }
    
    @ViewBuilder
    private var uploaderInfoSection: some View {
        let uploaderNameValue: String = {
            if let rev = revisionToDisplay, let uploadedBy = rev.uploadedBy, !uploadedBy.isEmpty {
                return uploadedBy
            } else if let user = drawing.user {
                let name = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? "N/A" : name
            }
            return "N/A"
        }()
        
        let uploadedAtValue = formatDate(revisionToDisplay?.uploadedAt ?? drawing.createdAt)

        InfoRow(label: "Uploaded By", value: uploaderNameValue)
        InfoRow(label: "Uploaded At", value: uploadedAtValue)
    }

    @ViewBuilder
    private var disciplineAndTypeSection: some View {
        if let discipline = drawing.projectDiscipline?.name, !discipline.isEmpty {
            InfoRow(label: "Discipline", value: discipline)
        }
        if let type = drawing.projectDrawingType?.name, !type.isEmpty {
            InfoRow(label: "Type", value: type)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    Divider().padding(.horizontal)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            revisionDetailsSection
                            
                            InfoRow(label: "Drawing Title", value: drawing.title)
                            InfoRow(label: "Drawing Number", value: drawing.number)
                            
                            uploaderInfoSection
                            disciplineAndTypeSection
                            
                            InfoRow(label: "Project ID", value: "\(drawing.projectId)")
                            InfoRow(label: "Offline Available", value: drawing.isOffline ?? false ? "Yes" : "No")
                        }
                        .padding()
                    }
                }
                .frame(width: min(geometry.size.width * 0.85, 350))
                .background(Color(hex: "#F9FAFB"))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: -5, y: 0)
                .transition(.move(edge: .trailing))
                .frame(height: geometry.size.height - (geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom))
                .padding(.top, geometry.safeAreaInsets.top)
                .padding(.bottom, geometry.safeAreaInsets.bottom)
            }
        }
        .background(
            Color.black.opacity(isSidePanelOpen ? 0.4 : 0)
                .ignoresSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut) {
                        isSidePanelOpen = false
                    }
                }
        )
        .animation(.easeInOut, value: isSidePanelOpen)
    }
}
