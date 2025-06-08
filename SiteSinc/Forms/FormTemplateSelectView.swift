import SwiftUI

struct FormTemplateSelectionView: View {
    let projectId: Int
    let token: String
    let onSelect: (FormModel) -> Void
    @EnvironmentObject var sessionManager: SessionManager
    @State private var forms: [FormModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss
    
    private var filteredForms: [FormModel] {
        if searchText.isEmpty {
            return forms
        } else {
            return forms.filter { form in
                form.title.localizedCaseInsensitiveContains(searchText) ||
                (form.reference?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (form.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
    }

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
                } else if filteredForms.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No forms found")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Try adjusting your search terms")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    VStack(spacing: 0) {
                        // Search results header
                        if !searchText.isEmpty {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text("\(filteredForms.count) form\(filteredForms.count == 1 ? "" : "s") found")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                        }
                        
                        List {
                            ForEach(filteredForms) { form in
                            Button(action: {
                                onSelect(form)
                                dismiss()
                            }) {
                                HStack(spacing: 12) {
                                    // Form icon
                                    Image(systemName: "doc.text.fill")
                                        .font(.title2)
                                        .foregroundColor(.blue)
                                        .frame(width: 32, height: 32)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(form.title)
                                            .font(.headline)
                                            .foregroundColor(.black)
                                            .multilineTextAlignment(.leading)
                                        
                                        if let reference = form.reference, !reference.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "number.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Text(reference)
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        if let description = form.description, !description.isEmpty {
                                            Text(description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
            }
        }
            .navigationTitle("New Form")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search forms...")
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
