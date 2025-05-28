//
//  SidePanelView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI

struct DocumentSidePanelView: View {
    let document: Document
    let selectedRevision: DocumentRevision?
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
    
    private var revisionToDisplay: DocumentRevision? {
        selectedRevision ?? document.revisions.max(by: { $0.versionNumber < $1.versionNumber })
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack {
            Text("Document Information")
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
            InfoRow(label: "Revision Number", value: "\(revision.versionNumber)")
            InfoRow(label: "Revision Status", value: revision.status ?? "N/A")
            InfoRow(label: "Revision Date", value: formatDate(revision.createdAt))
        } else {
            InfoRow(label: "Revision", value: "Not Available")
        }
    }
    
    @ViewBuilder
    private var uploaderInfoSection: some View {
        let uploaderNameValue: String = {
            if let rev = revisionToDisplay, let uploadedBy = rev.uploadedBy, !uploadedBy.isEmpty {
                return uploadedBy
            } else if let user = document.uploadedBy {
                let name = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? "N/A" : name
            }
            return "N/A"
        }()
        
        let uploadedAtValue = formatDate(revisionToDisplay?.createdAt ?? document.createdAt)

        InfoRow(label: "Uploaded By", value: uploaderNameValue)
        InfoRow(label: "Uploaded At", value: uploadedAtValue)
    }

    @ViewBuilder
    private var disciplineAndTypeSection: some View {
        if let discipline = document.projectDocumentDiscipline?.name, !discipline.isEmpty {
            InfoRow(label: "Discipline", value: discipline)
        }
        if let type = document.projectDocumentType?.name, !type.isEmpty {
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
                            
                            InfoRow(label: "Document Name", value: document.name)
                            InfoRow(label: "Document ID", value: "\(document.id)")
                            
                            uploaderInfoSection
                            disciplineAndTypeSection
                            
                            InfoRow(label: "Project ID", value: "\(document.projectId)")
                            InfoRow(label: "Offline Available", value: document.isOffline ?? false ? "Yes" : "No")
                        }
                        .padding()
                    }
                }
                .frame(width: min(geometry.size.width * 0.85, 350))
                .background(Color(hex: "#F9FAFB").edgesIgnoringSafeArea(.bottom))
                .cornerRadius(12, corners: [.topLeft, .bottomLeft])
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: -5, y: 0)
                .transition(.move(edge: .trailing))
            }
        }
        .background(
            Color.black.opacity(isSidePanelOpen ? 0.4 : 0)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut) { isSidePanelOpen = false }
                }
        )
        .animation(.easeInOut, value: isSidePanelOpen)
        .edgesIgnoringSafeArea(.all)
    }
}
