import SwiftUI

struct FormTemplateSelectionView: View {
    let projectId: Int
    let token: String
    let onSelect: (FormModel) -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var forms: [FormModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .padding()
                } else if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                } else if forms.isEmpty {
                    Text("No form templates available")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        ForEach(forms) { form in
                            Button(action: {
                                onSelect(form)
                                dismiss()
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(form.title)
                                        .font(.headline)
                                        .foregroundColor(.black)
                                    if let reference = form.reference {
                                        Text("Ref: \(reference)")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                    }
                                    if let description = form.description {
                                        Text(description)
                                            .font(.body)
                                            .foregroundColor(.gray)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Form")
            .navigationBarItems(
                leading: Button("Cancel") {
                    dismiss()
                }
            )
            .onAppear {
                fetchForms()
            }
        }
    }

    private func fetchForms() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetchedForms = try await APIClient.fetchForms(projectId: projectId, token: token)
                await MainActor.run {
                    forms = fetchedForms
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
}

struct FormTemplateSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        FormTemplateSelectionView(projectId: 1, token: "sample_token", onSelect: { _ in })
    }
}
