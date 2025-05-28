import SwiftUI

struct RFIDetailView: View {
    let rfi: RFI
    let token: String

    private var formattedCreatedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let createdAtDateStr = rfi.createdAt, let date = ISO8601DateFormatter().date(from: createdAtDateStr) {
            return formatter.string(from: date)
        }
        return rfi.createdAt ?? "Unknown"
    }

    private var formattedDueDate: String {
        if let dueDateStr = rfi.returnDate, let date = ISO8601DateFormatter().date(from: dueDateStr) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
        return rfi.returnDate ?? "Not set"
    }

    private func statusColor(_ status: String?) -> Color {
        switch status?.lowercased() {
        case "open": return .green
        case "answered": return .blue
        case "closed": return .gray
        case "draft": return .orange
        default: return .purple
        }
    }

    private struct InfoRow: View {
        let label: String
        let value: String
        var body: some View {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#4B5563"))
                    .frame(width: 100, alignment: .leading)
                Text(value)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))
                    .textSelection(.enabled)
            }
        }
    }

    private struct ResponseRow: View {
        let response: RFI.RFIResponseItem
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(response.content)
                    .foregroundColor(Color(hex: "#4B5563"))
                Text("By \(response.user.firstName) \(response.user.lastName)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(response.createdAt)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
    
    private func iconForFileType(_ fileType: String) -> String {
        switch fileType.lowercased() {
        case "pdf": return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "doc", "docx": return "doc.richtext.fill"
        case "xls", "xlsx": return "tablecells.fill"
        default: return "doc.fill"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("RFI-\(String(format: "%03d", rfi.number)): ")
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#4B5563"))
                    Text(rfi.title ?? "Untitled")
                        .font(.title2.bold())
                        .foregroundColor(Color(hex: "#1F2A44"))
                        .lineLimit(3)
                    Spacer()
                    Text(rfi.status?.capitalized ?? "UNKNOWN")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor(rfi.status).opacity(0.15))
                        .foregroundColor(statusColor(rfi.status))
                        .cornerRadius(6)
                }

                Divider()

                // Description
                Text("Description")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#4B5563"))
                Text(rfi.description ?? rfi.query ?? "Not provided")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))

                if let query = rfi.query, query != rfi.description {
                    Text("Query")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#4B5563"))
                        .padding(.top, 8)
                    Text(query)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#1F2A44"))
                }

                if let accepted = rfi.acceptedResponse {
                    Text("Accepted Response")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#4B5563"))
                        .padding(.top, 8)
                    ResponseRow(response: accepted)
                } else if let responses = rfi.responses, !responses.isEmpty {
                    Text("Responses")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#4B5563"))
                        .padding(.top, 8)
                    ForEach(responses, id: \.id) { resp in
                        ResponseRow(response: resp)
                        Divider()
                    }
                }

                Divider()

                // Details
                Text("Details")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#4B5563"))
                InfoRow(label: "Created", value: formattedCreatedAt)
                InfoRow(label: "Due", value: formattedDueDate)

                if let closed = rfi.closedDate {
                    InfoRow(label: "Closed", value: closed)
                }

                if let users = rfi.assignedUsers, !users.isEmpty {
                    Text("Assigned Users")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#4B5563"))
                        .padding(.top, 8)
                    ForEach(users, id: \.user.id) { au in
                        Label("\(au.user.firstName) \(au.user.lastName)", systemImage: "person.fill")
                            .font(.subheadline)
                            .foregroundColor(Color(hex: "#1F2A44"))
                            .underline()
                    }
                }
                if let attachments = rfi.attachments, !attachments.isEmpty {
                    Text("Files")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#4B5563"))
                        .padding(.top, 8)
                    ForEach(attachments, id: \.id) { attachment in
                        if ["jpg", "jpeg", "png", "gif"].contains(attachment.fileType.lowercased()) {
                            let urlString = (attachment.downloadUrl?.isEmpty == false ? attachment.downloadUrl : attachment.fileUrl) ?? ""
                            // Debug print to check URL
                            let _ = print("Image URL for \(attachment.fileName): \(urlString)")
                            if let url = URL(string: urlString), !urlString.isEmpty {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        ProgressView()
                                            .frame(width: 100, height: 100)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 100, height: 100)
                                            .cornerRadius(8)
                                            .onTapGesture {
                                                // Handle image preview
                                            }
                                    case .failure:
                                        Text("Failed to load image")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    @unknown default:
                                        Text("Image unavailable")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                            } else {
                                Text("Image unavailable")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Label(attachment.fileName, systemImage: iconForFileType(attachment.fileType))
                                .font(.system(size: 15, weight: .regular, design: .rounded))
                                .foregroundColor(Color(hex: "#1F2A44"))
                                .underline()
                                .onTapGesture {
                                    // Handle file preview/download
                                }
                        }
                        Divider()
                    }
                }
            }
            .padding()
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("RFI-\(String(format: "%03d", rfi.number)): \(rfi.title ?? "Untitled")")
        .navigationBarTitleDisplayMode(.inline)
    }
}
