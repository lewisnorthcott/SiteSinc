import SwiftUI

// Wrapper for Int to conform to Identifiable
struct FormID: Identifiable {
    let id: Int
}

struct FormsView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var submissions: [FormSubmission] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showingFormTemplates = false
    @State private var selectedFormId: FormID?

    private var groupedSubmissions: [(templateTitle: String, submissions: [(index: Int, submission: FormSubmission)])] {
        let grouped = Dictionary(grouping: submissions, by: { $0.templateTitle })
        return grouped.map { (templateTitle, submissions) in
            let sortedSubmissions = submissions.sorted { $0.submittedAt > $1.submittedAt }
            let numberedSubmissions = sortedSubmissions.enumerated().map { (index, submission) in
                (index: index + 1, submission: submission)
            }
            return (templateTitle: templateTitle, submissions: numberedSubmissions)
        }.sorted { $0.templateTitle < $1.templateTitle }
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack {
                if isLoading {
                    ProgressView()
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if submissions.isEmpty {
                    Text("No form submissions found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        HStack {
                            Text("ID")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 30, alignment: .leading)
                            Text("Type")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Form #")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 50, alignment: .leading)
                            Text("Status")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 80, alignment: .leading)
                            Text("Date Submitted")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 120, alignment: .leading)
                            Text("Submitted By")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 100, alignment: .leading)
                            Text("Actions")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(width: 60, alignment: .leading)
                        }
                        .padding(.vertical, 4)

                        ForEach(groupedSubmissions, id: \.templateTitle) { group in
                            ForEach(group.submissions, id: \.submission.id) { numberedSubmission in
                                let submission = numberedSubmission.submission
                                let formNumber = numberedSubmission.index
                                HStack {
                                    Text("\(submission.id)")
                                        .font(.caption)
                                        .frame(width: 30, alignment: .leading)
                                    Text(submission.templateTitle)
                                        .font(.caption)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(formNumber)")
                                        .font(.caption)
                                        .frame(width: 50, alignment: .leading)
                                    Text(submission.status.capitalized)
                                        .font(.caption)
                                        .padding(4)
                                        .background(submission.status.lowercased() == "submitted" ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                        .foregroundColor(submission.status.lowercased() == "submitted" ? .blue : .green)
                                        .cornerRadius(4)
                                        .frame(width: 80, alignment: .leading)
                                    Text(formatDate(submission.submittedAt))
                                        .font(.caption)
                                        .frame(width: 120, alignment: .leading)
                                    Text("\(submission.submittedBy.firstName) \(submission.submittedBy.lastName)")
                                        .font(.caption)
                                        .frame(width: 100, alignment: .leading)
                                    HStack(spacing: 8) {
                                        NavigationLink(destination: FormSubmissionDetailView(submissionId: submission.id, projectId: projectId, token: token)) {
                                            Image(systemName: "eye")
                                                .foregroundColor(.gray)
                                        }
                                        Button(action: {
                                            downloadSubmission(submissionId: submission.id)
                                        }) {
                                            Image(systemName: "square.and.arrow.down")
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .frame(width: 60, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Forms")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingFormTemplates = true
                    }) {
                        Text("Add New Form")
                            .foregroundColor(.blue)
                    }
                }
            }
            .onAppear {
                fetchSubmissions()
            }
            .sheet(isPresented: $showingFormTemplates) {
                FormTemplateSelectionView(projectId: projectId, token: token) { formId in
                    selectedFormId = FormID(id: formId)
                    showingFormTemplates = false
                }
            }
            .sheet(item: $selectedFormId) { formId in
                FormSubmissionCreateView(formId: formId.id, projectId: projectId, token: token)
                    .onDisappear {
                        selectedFormId = nil
                        fetchSubmissions()
                    }
            }
        }
    }

    private func fetchSubmissions() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetchedSubmissions = try await APIClient.fetchFormSubmissions(projectId: projectId, token: token)
                await MainActor.run {
                    submissions = fetchedSubmissions
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
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

    private func downloadSubmission(submissionId: Int) {
        let urlString = "\(APIClient.baseURL)/forms/submissions/\(submissionId)/download?projectId=\(projectId)"
        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.downloadTask(with: request) { tempURL, response, error in
            if let error = error {
                print("Download error: \(error)")
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("Download failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            guard let tempURL = tempURL else {
                print("No file downloaded")
                return
            }
            print("Downloaded file to: \(tempURL)")
        }.resume()
    }
}

struct FormsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FormsView(projectId: 1, token: "sample_token", projectName: "Sample Project")
        }
    }
}
