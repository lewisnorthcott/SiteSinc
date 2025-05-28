//
//  RFIDraftDetailView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI
import WebKit // Import WebKit for WebView

struct RFIDraftDetailView: View {
    let draft: RFIDraft
    let token: String // Token might be needed if submitting requires re-authentication or specific headers
    let onSubmit: (RFIDraft) -> Void

    // Date formatter for display
    private var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: draft.createdAt)
    }

    // MARK: - Sub-views for Body Sections
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) { // Added alignment and consistent spacing
            Text(draft.title)
                .font(.title2.bold()) // Bolder title
                .foregroundColor(Color.primary) // Use primary color for better adaptability
                .lineLimit(3) // Allow title to wrap
                .multilineTextAlignment(.leading)


            HStack {
                Text("Draft RFI")
                    .font(.headline)
                    .foregroundColor(.orange) // More prominent "Draft" status
                Spacer()
                Text("Created: \(formattedCreatedAt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var querySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Query / Description")
                .font(.callout.weight(.semibold)) // Clearer section label
                .foregroundColor(.secondary)
            Text(draft.query)
                .font(.body)
                .foregroundColor(Color.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading) // Ensure it takes width
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var selectedDrawingsSection: some View {
        // Corrected to use draft.selectedDrawings, assuming this is the correct
        // property name in your RFIDraft model.
        if !draft.selectedDrawings.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Linked Drawings (\(draft.selectedDrawings.count))")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.secondary)
                ForEach(draft.selectedDrawings) { drawing in // Assuming SelectedDrawing is Identifiable
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text("\(drawing.number) - Rev \(drawing.revisionNumber)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        if !draft.selectedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Attachments (\(draft.selectedFiles.count))")
                    .font(.callout.weight(.semibold))
                    .foregroundColor(.secondary)
                
                ForEach(draft.selectedFiles, id: \.self) { filePath in
                    let fileURL = URL(fileURLWithPath: filePath)
                    HStack {
                        Image(systemName: "paperclip")
                            .foregroundColor(Color(hex: "#3B82F6"))
                        Text(fileURL.lastPathComponent)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var submitButtonSection: some View {
        Button(action: {
            onSubmit(draft)
        }) {
            HStack {
                Spacer()
                Image(systemName: "paperplane.fill")
                Text("Submit Draft")
                    .fontWeight(.semibold)
                Spacer()
            }
        }
        .padding()
        .background(Color.accentColor) // Use accent color for primary actions
        .foregroundColor(.white)
        .cornerRadius(10)
        .shadow(radius: 3)
        .padding(.top) // Add some space before the button
    }

    var body: some View {
        ZStack {
            // Use a grouped background for a more standard iOS form appearance
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) { // Increased spacing between sections
                    headerSection
                    Divider()
                    querySection
                    Divider()
                    selectedDrawingsSection // This now uses draft.selectedDrawings
                    Divider()
                    attachmentsSection
                    Divider()
                    submitButtonSection
                }
                .padding() // Add overall padding to the VStack content
            }
        }
        .navigationTitle("Draft RFI Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
