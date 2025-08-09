//
//  DocumentListView.swift
//  SiteSinc
//
//  Created by Lewis Northcott on 24/05/2025.
//

import SwiftUI

struct DocumentListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added
    @StateObject private var progressManager = DownloadProgressManager.shared
    @State private var documents: [Document] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var groupByOption: GroupByOption = .company
    @State private var searchText: String = ""
    @State private var isGridView: Bool = false
    @State private var showCreateRFI = false
    @State private var isProjectOffline: Bool = false

    enum GroupByOption: String, CaseIterable, Identifiable {
        case company = "Company"
        case discipline = "Discipline"
        case type = "Type"
        case all = "All"
        var id: String { rawValue }
    }

    var filteredDocuments: [Document] {
        if searchText.isEmpty {
            return documents
        } else {
            return documents.filter {
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    private var groupedDocuments: [String: [Document]] {
        let documentsToGroup = filteredDocuments
        switch groupByOption {
        case .company:
            return Dictionary(grouping: documentsToGroup, by: { $0.company?.name ?? "Unknown Company" })
        case .discipline:
            return Dictionary(grouping: documentsToGroup, by: { $0.projectDocumentDiscipline?.name ?? "No Discipline" })
        case .type:
            return Dictionary(grouping: documentsToGroup, by: { $0.projectDocumentType?.name ?? "No Type" })
        case .all:
            return ["All Documents": documentsToGroup]
        }
    }

    private var groupKeys: [String] {
        groupedDocuments.keys.sorted()
    }

    private func documentsForGroup(key: String) -> [Document] {
        groupedDocuments[key] ?? []
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)
            mainContent
//            floatingActionButton
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button(action: { isGridView.toggle() }) {
                        Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "#3B82F6"))
                    }
                    Menu {
                        let state = progressManager.status(for: projectId)
                        if state.isLoading {
                            Button("Downloading… \(Int(state.progress * 100))%", action: {}).disabled(true)
                        }
                        Button("Sync now") { /* optional hook to trigger from summary */ }
                    } label: {
                        CloudProgressIcon(
                            isLoading: progressManager.status(for: projectId).isLoading,
                            progress: progressManager.status(for: projectId).progress,
                            baseIcon: progressManager.status(for: projectId).isOfflineEnabled ? "icloud.fill" : "icloud",
                            tint: progressManager.status(for: projectId).hasError ? Color.red : (progressManager.status(for: projectId).isOfflineEnabled ? Color.green : Color.gray)
                        )
                    }
                }
            }
        }
        .onAppear {
            fetchDocuments()
            updateOfflineStatus()
        }
        .onChange(of: networkStatusManager.isNetworkAvailable) { oldValue, newValue in
            updateOfflineStatus()
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
                showCreateRFI = false
            }, prefilledTitle: nil, prefilledAttachmentData: nil, prefilledDrawing: nil)
        }
    }

    private func updateOfflineStatus() {
        let offlineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        isProjectOffline = offlineModeEnabled && !networkStatusManager.isNetworkAvailable
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            headerSection
            if isLoading {
                ProgressView("Loading Documents...")
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                    .padding()
                    .frame(maxHeight: .infinity)
            } else if let errorMessage = errorMessage {
                errorView(errorMessage: errorMessage)
            } else if groupKeys.isEmpty && filteredDocuments.isEmpty {
                Text(searchText.isEmpty ? "No documents found for this project." : "No documents match your search.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .padding()
                    .frame(maxHeight: .infinity)
            } else {
                documentsScrollView
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Menu {
                    ForEach(GroupByOption.allCases) { option in
                        Button(action: { groupByOption = option }) {
                            Text(option.rawValue)
                        }
                    }
                } label: {
                    HStack {
                        Text("Group: \(groupByOption.rawValue)")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#1F2A44"))
                        Image(systemName: "chevron.down")
                            .foregroundColor(Color(hex: "#3B82F6"))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            SearchBar(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(Color(hex: "#FFFFFF"))
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private func errorView(errorMessage: String) -> some View {
        VStack {
            Text(errorMessage)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.red)
                .padding()
                .multilineTextAlignment(.center)
            Button("Retry") { fetchDocuments() }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#3B82F6"))
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    private var documentsScrollView: some View {
        ScrollView {
            if isGridView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                    ForEach(groupKeys, id: \.self) { groupKey in
                        NavigationLink(destination: FilteredDocumentsView(
                            documents: documentsForGroup(key: groupKey),
                            groupName: groupKey,
                            token: token,
                            projectId: projectId,
                            projectName: projectName,
                            isGridView: $isGridView,
                            onRefresh: fetchDocuments,
                            isProjectOffline: isProjectOffline
                        ).environmentObject(networkStatusManager)) { // Pass NetworkStatusManager
                            GroupCard(groupKey: groupKey, count: documentsForGroup(key: groupKey).count)
                        }
                    }
                }
                .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(groupKeys, id: \.self) { groupKey in
                        NavigationLink(destination: FilteredDocumentsView(
                            documents: documentsForGroup(key: groupKey),
                            groupName: groupKey,
                            token: token,
                            projectId: projectId,
                            projectName: projectName,
                            isGridView: $isGridView,
                            onRefresh: fetchDocuments,
                            isProjectOffline: isProjectOffline
                        ).environmentObject(networkStatusManager)) { // Pass NetworkStatusManager
                            GroupRow(groupKey: groupKey, count: documentsForGroup(key: groupKey).count)
                        }
                    }
                }
                .padding()
            }
        }
        .refreshable { fetchDocuments() }
    }

//    private var floatingActionButton: some View {
//        VStack {
//            Spacer()
//            HStack {
//                Spacer()
//                Menu {
//                    Button(action: { showCreateRFI = true }) {
//                        Label("New RFI", systemImage: "doc.text.fill")
//                    }
//                } label: {
//                    Image(systemName: "plus")
//                        .font(.system(size: 24, weight: .semibold))
//                        .foregroundColor(.white)
//                        .frame(width: 56, height: 56)
//                        .background(Color(hex: "#3B82F6"))
//                        .clipShape(Circle())
//                        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
//                }
//                .padding(.trailing, 20)
//                .padding(.bottom, 20)
//            }
//        }
//    }

    private func fetchDocuments() {
        isLoading = true
        errorMessage = nil
        Task {
            // Offline-first: try local first
            if let cachedDocuments = loadDocumentsFromCache(), !cachedDocuments.isEmpty {
                await MainActor.run {
                    documents = cachedDocuments.map { var doc = $0; doc.isOffline = checkOfflineStatus(for: doc); return doc }
                    isLoading = false
                }
            }
            do {
                let d = try await APIClient.fetchDocuments(projectId: projectId, token: token)
                await MainActor.run {
                    documents = d.map {
                        var document = $0
                        document.isOffline = checkOfflineStatus(for: document)
                        return document
                    }
                    saveDocumentsToCache(documents)
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet, let cachedDocuments = loadDocumentsFromCache() {
                        documents = cachedDocuments.map {
                            var document = $0
                            document.isOffline = checkOfflineStatus(for: document)
                            return document
                        }
                        errorMessage = nil
                    } else {
                        if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                            errorMessage = isProjectOffline
                                ? "Offline: No cached documents available. Ensure the project was downloaded while online."
                                : "Offline: Offline mode not enabled. Please enable offline mode and download the project while online."
                        } else {
                            errorMessage = "Failed to load documents: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func checkOfflineStatus(for document: Document) -> Bool {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)/documents")
        
        let pdfFiles: [DocumentFile] = document.revisions.compactMap { revision in
            if let documentFiles = revision.documentFiles {
                return documentFiles.filter { $0.fileName.lowercased().hasSuffix(".pdf") }
            } else {
                guard !revision.fileUrl.isEmpty else { return nil }
                let fileName = revision.fileUrl.split(separator: "/").last?.removingPercentEncoding ?? "document.pdf"
                return [DocumentFile(
                    id: revision.id,
                    fileName: fileName,
                    fileUrl: revision.fileUrl,
                    downloadUrl: revision.downloadUrl
                )].filter { $0.fileName.lowercased().hasSuffix(".pdf") }
            }
        }.flatMap { $0 }
        
        if pdfFiles.isEmpty { return false }
        
        return pdfFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(file.fileName).path)
        }
    }

    private func saveDocumentsToCache(_ documents: [Document]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(documents) {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let cacheURL = base.appendingPathComponent("documents_project_\(projectId).json")
            try? data.write(to: cacheURL)
        }
    }

    private func loadDocumentsFromCache() -> [Document]? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("SiteSincCache", isDirectory: true)
        let cacheURL = base.appendingPathComponent("documents_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL), let cachedDocuments = try? JSONDecoder().decode([Document].self, from: data) {
            return cachedDocuments
        }
        return nil
    }
}
