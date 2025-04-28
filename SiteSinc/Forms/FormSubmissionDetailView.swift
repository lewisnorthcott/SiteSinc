import SwiftUI

struct FormSubmissionDetailView: View {
    let submissionId: Int
    let projectId: Int
    let token: String
    @State private var submission: FormSubmission?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshedResponses: [String: FormResponseValue] = [:]

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if isLoading {
                ProgressView()
                    .padding()
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            } else if let submission = submission {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        Text(submission.templateTitle)
                            .font(.title2)
                            .fontWeight(.bold)

                        // Submission Info
                        HStack {
                            Text("Submission #\(submission.id)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                            Text(submission.status.capitalized)
                                .font(.caption)
                                .padding(4)
                                .background(submission.status.lowercased() == "submitted" ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                .foregroundColor(submission.status.lowercased() == "submitted" ? .blue : .green)
                                .cornerRadius(4)
                        }
                        HStack {
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                            Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.gray)
                            Text(formatDate(submission.submittedAt))
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Divider()

                        // Form Responses
                        if !submission.fields.isEmpty {
                            ForEach(submission.fields, id: \.id) { field in
                                renderFormField(field: field, response: refreshedResponses)
                            }
                        } else {
                            Text("No form fields found")
                                .foregroundColor(.gray)
                                .padding()
                        }
                    }
                    .padding()
                }
            } else {
                Text("Submission not found")
                    .foregroundColor(.gray)
                    .padding()
            }
        }
        .navigationTitle("Submission Details")
        .onAppear {
            fetchSubmission()
        }
    }

    private func fetchSubmission() {
        APIClient.fetchFormSubmissions(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let submissions):
                    if let fetchedSubmission = submissions.first(where: { $0.id == submissionId }) {
                        submission = fetchedSubmission
                        refreshAttachmentURLs(fields: fetchedSubmission.fields, responses: fetchedSubmission.responses ?? [:])
                    } else {
                        errorMessage = "Submission not found"
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func refreshAttachmentURLs(fields: [FormField], responses: [String: FormResponseValue]) {
        let attachmentFields = fields.filter { ["image", "attachment", "camera", "signature"].contains($0.type) }
        var updatedResponses = responses

        let group = DispatchGroup()

        for field in attachmentFields {
            if let response = responses[field.id] {
                switch response {
                case .string(let fileKey):
                    if fileKey.starts(with: "tenants/") || fileKey.contains("/forms/") {
                        group.enter()
                        var request = URLRequest(url: URL(string: "\(APIClient.baseURL)/forms/refresh-attachment-url")!)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        let params = ["fileKey": fileKey]
                        request.httpBody = try? JSONEncoder().encode(params)

                        URLSession.shared.dataTask(with: request) { data, response, error in
                            defer { group.leave() }
                            if let data = data, let json = try? JSONDecoder().decode([String: String].self, from: data), let fileUrl = json["fileUrl"] {
                                updatedResponses[field.id] = .string(fileUrl)
                            }
                        }.resume()
                    }
                default:
                    break
                }
            }
        }

        group.notify(queue: .main) {
            refreshedResponses = updatedResponses
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "dd/MM/yyyy, HH:mm:ss"
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Field Rendering Views
struct TextFieldDisplay: View {
    let field: FormField
    let value: FormResponseValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)
            switch value {
            case .string(let stringValue):
                Text(stringValue.isEmpty ? "Not provided" : stringValue)
                    .font(.body)
                    .foregroundColor(stringValue.isEmpty ? .gray : .black)
            case .stringArray(let values):
                Text(values.joined(separator: ", ").isEmpty ? "Not provided" : values.joined(separator: ", "))
                    .font(.body)
                    .foregroundColor(values.isEmpty ? .gray : .black)
            case .null:
                Text("Not provided")
                    .font(.body)
                    .foregroundColor(.gray)
            case .none:
                Text("Not provided")
                    .font(.body)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

struct YesNoNAFieldDisplay: View {
    let field: FormField
    let value: FormResponseValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)
            switch value {
            case .string(let stringValue):
                Text(stringValue.lowercased() == "yes" ? "Yes" :
                     stringValue.lowercased() == "no" ? "No" :
                     stringValue.lowercased() == "na" ? "N/A" : "Not answered")
                    .font(.body)
                    .foregroundColor(stringValue.isEmpty ? .gray : .black)
            case .null, .none:
                Text("Not answered")
                    .font(.body)
                    .foregroundColor(.gray)
            default:
                Text("Not answered")
                    .font(.body)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SubheadingDisplay: View {
    let field: FormField

    var body: some View {
        Text(field.label)
            .font(.title3)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .padding(.vertical, 8)
    }
}

struct AttachmentDisplay: View {
    let field: FormField
    let value: FormResponseValue?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.subheadline)
                .fontWeight(.medium)

            if let error = error {
                Text(error)
                    .font(.body)
                    .foregroundColor(.red)
            } else {
                switch value {
                case .string(let fileUrl):
                    if fileUrl.isEmpty || fileUrl == "Not provided" {
                        Text("No attachment provided")
                            .font(.body)
                            .foregroundColor(.gray)
                    } else if field.type == "image" || field.type == "camera" || field.type == "signature" ||
                              fileUrl.contains(".jpg") || fileUrl.contains(".jpeg") || fileUrl.contains(".png") {
                        AsyncImage(url: URL(string: fileUrl)) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: 300)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            case .failure:
                                Text("Failed to load image")
                                    .font(.body)
                                    .foregroundColor(.red)
                                    .onAppear {
                                        error = "Failed to load image"
                                    }
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Link(destination: URL(string: fileUrl)!) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.blue)
                                Text(fileUrl.contains(".pdf") ? "View PDF Document" : "View Attachment")
                                    .font(.body)
                                    .foregroundColor(.blue)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                case .null, .none:
                    Text("No attachment provided")
                        .font(.body)
                        .foregroundColor(.gray)
                default:
                    Text("Invalid attachment format")
                        .font(.body)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private func renderFormField(field: FormField, response: [String: FormResponseValue]) -> some View {
    let value = response[field.id]
    switch field.type {
    case "text", "textarea", "number", "phone", "email", "date":
        return AnyView(TextFieldDisplay(field: field, value: value))
    case "yesNoNA":
        return AnyView(YesNoNAFieldDisplay(field: field, value: value))
    case "dropdown", "checkbox", "radio":
        return AnyView(TextFieldDisplay(field: field, value: value))
    case "subheading":
        return AnyView(SubheadingDisplay(field: field))
    case "image", "attachment", "camera", "signature":
        return AnyView(AttachmentDisplay(field: field, value: value))
    default:
        return AnyView(TextFieldDisplay(field: field, value: value))
    }
}

struct FormSubmissionDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FormSubmissionDetailView(submissionId: 1, projectId: 1, token: "sample_token")
        }
    }
}
