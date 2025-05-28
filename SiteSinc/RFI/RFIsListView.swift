import Foundation
import SwiftUI
import SwiftData

struct RFIsListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @State private var unifiedRFIs: [UnifiedRFI] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SortOption = .title
    @State private var showCreateRFI = false
    @Environment(\.modelContext) private var modelContext

    enum SortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case date = "Date"
        var id: String { rawValue }
    }

    var body: some View {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text("RFIs")
                        .font(.title2)
                        .fontWeight(.regular)
                        .foregroundColor(.black)
                        .padding(.top, 16)

                    HStack {
                        TextField("Search", text: $searchText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(.gray)
                                        .padding(.leading, 8)
                                    Spacer()
                                }
                            )
                    }

                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 24)

                    if isLoading {
                        ProgressView("Loading RFIs...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else if let errorMessage = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                    } else if filteredUnifiedRFIs.isEmpty {
                        Text("No RFIs available")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredUnifiedRFIs) { unifiedRFI in
                                    NavigationLink(destination: destinationView(for: unifiedRFI)) {
                                        RFIRow(unifiedRFI: unifiedRFI)
                                            .background(
                                                Color.white
                                                    .cornerRadius(8)
                                                    .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
                                            )
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 4)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                            .padding(.vertical, 10)
                        }
                        .scrollIndicators(.visible)
                        .refreshable {
                            fetchRFIs()
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)

                FloatingActionButton(showCreateRFI: $showCreateRFI) {
                        Group { // Wrap the Buttons in a Group to return a single View
                            Button(action: { showCreateRFI = true }) {
                                Label("New RFI", systemImage: "doc.text")
                            }
                            Button(action: {
                                print("Another action for RFI page")
                            }) {
                                Label("Another Action", systemImage: "plus.circle")
                            }
                        }
                    }
                }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                fetchRFIs()
            }
            .sheet(isPresented: $showCreateRFI) {
                CreateRFIView(projectId: projectId, token: token,projectName: projectName,onSuccess: {
                    showCreateRFI = false
                    fetchRFIs()
                })
            }
        }

    private func destinationView(for unifiedRFI: UnifiedRFI) -> some View {
        if unifiedRFI.draftObject != nil {
            return AnyView(RFIDraftDetailView(draft: unifiedRFI.draftObject!, token: token, onSubmit: { draft in
                submitDraft(draft)
            }))
        } else {
            return AnyView(RFIDetailView(rfi: unifiedRFI.serverRFI!, token: token))
        }
    }

    private var filteredUnifiedRFIs: [UnifiedRFI] {
        var sortedRFIs = unifiedRFIs
        switch sortOption {
        case .title:
            sortedRFIs.sort(by: { ($0.title ?? "").lowercased() < ($1.title ?? "").lowercased() })
        case .date:
            sortedRFIs.sort { rfi1, rfi2 in
                let date1 = ISO8601DateFormatter().date(from: rfi1.createdAt ?? "") ?? Date.distantPast
                let date2 = ISO8601DateFormatter().date(from: rfi2.createdAt ?? "") ?? Date.distantPast
                return date1 > date2
            }
        }
        if searchText.isEmpty {
            return sortedRFIs
        } else {
            return sortedRFIs.filter {
                ($0.title ?? "").lowercased().contains(searchText.lowercased()) ||
                String($0.number).lowercased().contains(searchText.lowercased())
            }
        }
    }

    private func fetchRFIs() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        let drafts = (try? modelContext.fetch(fetchDescriptor)) ?? []
        let draftRFIs = drafts.map { UnifiedRFI.draft($0) }

        isLoading = true
        errorMessage = nil
        Task {
            do {
                let r = try await APIClient.fetchRFIs(projectId: projectId, token: token)
                await MainActor.run {
                    let serverRFIs = r.map { UnifiedRFI.server($0) }
                    unifiedRFIs = draftRFIs + serverRFIs
                    saveRFIsToCache(r)
                    if r.isEmpty {
                        print("No RFIs returned for projectId: \(projectId)")
                    } else {
                        print("Fetched \(r.count) RFIs for projectId: \(projectId)")
                    }
                    syncDrafts()
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                        if let cachedRFIs = loadRFIsFromCache() {
                            unifiedRFIs = draftRFIs + cachedRFIs.map { UnifiedRFI.server($0) }
                            errorMessage = "Loaded cached RFIs (offline mode)"
                        } else {
                            unifiedRFIs = draftRFIs
                            errorMessage = "No internet connection and no cached data available"
                        }
                    } else {
                        unifiedRFIs = draftRFIs
                        errorMessage = "Failed to load RFIs: \(error.localizedDescription)"
                        print("Error fetching RFIs: \(error)")
                    }
                }
            }
        }
    }

    private func saveRFIsToCache(_ rfis: [RFI]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(rfis) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(rfis.count) RFIs to cache for project \(projectId)")
        }
    }

    private func loadRFIsFromCache() -> [RFI]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("rfis_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL) {
            let decoder = JSONDecoder()
            if let cachedRFIs = try? decoder.decode([RFI].self, from: data) {
                print("Loaded \(cachedRFIs.count) RFIs from cache for project \(projectId)")
                return cachedRFIs
            }
        }
        return nil
    }

    private func syncDrafts() {
        let fetchDescriptor = FetchDescriptor<RFIDraft>(predicate: #Predicate { $0.projectId == projectId })
        guard let drafts = try? modelContext.fetch(fetchDescriptor), !drafts.isEmpty else { return }
        
        for draft in drafts {
            submitDraft(draft)
        }
    }

    private func submitDraft(_ draft: RFIDraft) {
        Task {
            do {
                // Step 1: Upload files
                var uploadedFiles: [[String: Any]] = []
                let fileURLs = draft.selectedFiles.compactMap { URL(fileURLWithPath: $0) }
                
                for fileURL in fileURLs {
                    guard let uploadData = try? Data(contentsOf: fileURL) else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to read file data"])
                    }
                    let fileName = fileURL.lastPathComponent
                    let url = URL(string: "\(APIClient.baseURL)/rfis/upload-file")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    let boundary = "Boundary-\(UUID().uuidString)"
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    
                    var body = Data()
                    let boundaryPrefix = "--\(boundary)\r\n"
                    body.append(boundaryPrefix.data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
                    body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                    body.append(uploadData)
                    body.append("\r\n".data(using: .utf8)!)
                    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
                    request.httpBody = body
                    
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        if statusCode == 403 {
                            throw APIError.tokenExpired
                        }
                        throw NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
                    }
                    guard let fileData = try? JSONDecoder().decode(UploadedFileResponse.self, from: data) else {
                        throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode upload response"])
                    }
                    uploadedFiles.append([
                        "fileUrl": fileData.fileUrl,
                        "fileName": fileData.fileName,
                        "fileType": fileData.fileType
                    ])
                }

                // Step 2: Submit RFI
                let body: [String: Any] = [
                    "title": draft.title,
                    "query": draft.query,
                    "description": draft.query,
                    "projectId": draft.projectId,
                    "managerId": draft.managerId!,
                    "assignedUserIds": draft.assignedUserIds,
                    "returnDate": draft.returnDate?.ISO8601Format() ?? "",
                    "attachments": uploadedFiles,
                    "drawings": draft.selectedDrawings.map { ["drawingId": $0.drawingId, "revisionId": $0.revisionId] }
                ]

                guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode request"])
                }

                let url = URL(string: "\(APIClient.baseURL)/rfis")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData

                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, (200...201).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    if statusCode == 403 {
                        throw APIError.tokenExpired
                    }
                    throw NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to sync draft RFI"])
                }

                await MainActor.run {
                    self.modelContext.delete(draft)
                    try? self.modelContext.save()
                    fetchRFIs()
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to sync draft RFI: \(error.localizedDescription)"
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RFIsListView(projectId: 1, token: "sample_token", projectName: "Sample Project")
            .environmentObject(SessionManager())
    }
}
