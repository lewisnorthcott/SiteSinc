import SwiftUI

struct ProjectSummaryView: View {
    let projectId: Int
    let token: String
    @State private var isLoading = false
    @State private var selectedTile: String?
    @State private var isAppearing = false
    @State private var showCreateRFI = false
    @State private var isOfflineModeEnabled: Bool = false
    @State private var downloadProgress: Double = 0.0
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header section
                    VStack(spacing: 8) {
                        Text("Project Summary")
                            .font(.title2)
                            .fontWeight(.regular)
                            .foregroundColor(.black)
                        
                        Text("Access project resources")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 16)
                    
                    // Stats Overview
                    HStack(spacing: 12) {
                        StatCard(title: "Documents", value: "23", trend: "+5")
                        StatCard(title: "Drawings", value: "45", trend: "+12")
                        StatCard(title: "RFIs", value: "8", trend: "+2")
                    }
                    .padding(.horizontal, 24)
                    
                    // Main navigation grid
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        NavigationLink(
                            destination: DrawingListView(projectId: projectId, token: token)
                        ) {
                            SummaryTile(
                                title: "Drawings",
                                subtitle: "Access project drawings",
                                icon: "pencil.ruler.fill",
                                color: Color(hex: "#635bff"),
                                isSelected: selectedTile == "Drawings"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTile = "Drawings"
                            }
                        })
                        
                        NavigationLink(
                            destination: RFIsView(projectId: projectId, token: token)
                        ) {
                            SummaryTile(
                                title: "RFIs",
                                subtitle: "Manage information requests",
                                icon: "questionmark.circle.fill",
                                color: Color(hex: "#635bff"),
                                isSelected: selectedTile == "RFIs"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTile = "RFIs"
                            }
                        })
                        
                        NavigationLink(
                            destination: FormsView(projectId: projectId, token: token)
                        ) {
                            SummaryTile(
                                title: "Forms",
                                subtitle: "View and submit forms",
                                icon: "doc.text.fill",
                                color: Color(hex: "#635bff"),
                                isSelected: selectedTile == "Forms"
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTile = "Forms"
                            }
                        })
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .opacity(isAppearing ? 1 : 0)
                    .offset(y: isAppearing ? 0 : 20)
                }
                
                // Floating Action Button with Menu
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Menu {
                            Button(action: {
                                showCreateRFI = true
                            }) {
                                Label("New RFI", systemImage: "doc.text")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color(hex: "#635bff"))
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                        .accessibilityLabel("Create new item")
                    }
                }
            }
            if isLoading && downloadProgress > 0 && downloadProgress < 1 {
                VStack {
                    ProgressView("Downloading Project Data...", value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                    Text("Progress: \(Int(downloadProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(8)
            }
            if let errorMessage = errorMessage {
                VStack {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                    Button("Retry") {
                        if isOfflineModeEnabled {
                            downloadAllResources()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }
                .padding()
                .background(Color.white.opacity(0.9))
                .cornerRadius(8)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Toggle(isOn: $isOfflineModeEnabled) {
                    Image(systemName: isOfflineModeEnabled ? "cloud.fill" : "cloud")
                        .foregroundColor(isOfflineModeEnabled ? .green : .gray)
                }
                .accessibilityLabel("Toggle offline mode for project")
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
            isOfflineModeEnabled = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        }
        .onChange(of: isOfflineModeEnabled) { oldValue, newValue in
            UserDefaults.standard.set(newValue, forKey: "offlineMode_\(projectId)")
            if newValue {
                downloadAllResources()
            } else {
                clearOfflineData()
            }
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, onSuccess: {
                showCreateRFI = false
            })
        }
    }
    
    private func downloadAllResources() {
        isLoading = true
        errorMessage = nil
        downloadProgress = 0.0
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true, attributes: nil)
            
            // Fetch all resources concurrently
            Task {
                async let drawingsResult = await fetchDrawings()
                async let rfisResult = await fetchRFIs()
                async let formsResult = await fetchForms()
                
                let (drawings, rfis, forms) = await (drawingsResult, rfisResult, formsResult)
                
                // Handle errors
                if case .failure(let error) = drawings {
                    DispatchQueue.main.async {
                        errorMessage = "Failed to fetch drawings: \(error.localizedDescription)"
                        isLoading = false
                    }
                    return
                }
                if case .failure(let error) = rfis {
                    DispatchQueue.main.async {
                        errorMessage = "Failed to fetch RFIs: \(error.localizedDescription)"
                        isLoading = false
                    }
                    return
                }
                if case .failure(let error) = forms {
                    DispatchQueue.main.async {
                        errorMessage = "Failed to fetch forms: \(error.localizedDescription)"
                        isLoading = false
                    }
                    return
                }
                
                // Unwrap successful results
                guard case .success(let drawingsData) = drawings,
                      case .success(let rfisData) = rfis,
                      case .success(let formsData) = forms else {
                    DispatchQueue.main.async {
                        errorMessage = "Unexpected error fetching resources"
                        isLoading = false
                    }
                    return
                }
                
                // Collect files to download
                let drawingFiles = drawingsData.flatMap { drawing in
                    drawing.revisions.flatMap { revision in
                        revision.drawingFiles.filter { $0.fileName.lowercased().hasSuffix(".pdf") }.map { file in
                            (file: file, localPath: projectFolder.appendingPathComponent("drawings/\(file.fileName)"))
                        }
                    }
                }
                
                let rfiFiles = rfisData.flatMap { rfi in
                    (rfi.attachments ?? []).map { attachment in
                        (file: attachment, localPath: projectFolder.appendingPathComponent("rfis/\(attachment.fileName)"))
                    }
                }
                
                let totalFiles = drawingFiles.count + rfiFiles.count
                guard totalFiles > 0 else {
                    DispatchQueue.main.async {
                        isLoading = false
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        print("No files to download for project \(projectId)")
                    }
                    return
                }
                
                var completedDownloads = 0
                
                // Download drawing files
                for (file, localPath) in drawingFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("drawings"), withIntermediateDirectories: true)
                    await downloadFile(from: file.downloadUrl, to: localPath) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                completedDownloads += 1
                                downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            case .failure(let error):
                                errorMessage = "Failed to download drawing file: \(error.localizedDescription)"
                                isLoading = false
                            }
                        }
                    }
                }
                
                // Download RFI files
                for (file, localPath) in rfiFiles {
                    try FileManager.default.createDirectory(at: projectFolder.appendingPathComponent("rfis"), withIntermediateDirectories: true)
                    await downloadFile(from: file.downloadUrl ?? file.fileUrl, to: localPath) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                completedDownloads += 1
                                downloadProgress = Double(completedDownloads) / Double(totalFiles)
                            case .failure(let error):
                                errorMessage = "Failed to download RFI file: \(error.localizedDescription)"
                                isLoading = false
                            }
                        }
                    }
                }
                
                // Cache metadata after all downloads
                DispatchQueue.main.async {
                    if completedDownloads == totalFiles {
                        isLoading = false
                        saveDrawingsToCache(drawingsData)
                        saveRFIsToCache(rfisData)
                        saveFormsToCache(formsData)
                        print("All files downloaded for project \(projectId)")
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                errorMessage = "Failed to create directory: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    private func fetchDrawings() async -> Result<[Drawing], Error> {
        await withCheckedContinuation { continuation in
            APIClient.fetchDrawings(projectId: projectId, token: token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func fetchRFIs() async -> Result<[RFI], Error> {
        await withCheckedContinuation { continuation in
            APIClient.fetchRFIs(projectId: projectId, token: token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func fetchForms() async -> Result<[FormModel], Error> {
        await withCheckedContinuation { continuation in
            APIClient.fetchForms(projectId: projectId, token: token) { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    private func downloadFile(from urlString: String, to localPath: URL, completion: @escaping (Result<Void, Error>) -> Void) async {
        APIClient.downloadFile(from: urlString, to: localPath, completion: completion)
    }
    
    private func clearOfflineData() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)", isDirectory: true)
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let drawingsCacheURL = cachesDirectory.appendingPathComponent("drawings_project_\(projectId).json")
        let rfisCacheURL = cachesDirectory.appendingPathComponent("rfis_project_\(projectId).json")
        let formsCacheURL = cachesDirectory.appendingPathComponent("forms_project_\(projectId).json")
        
        do {
            if FileManager.default.fileExists(atPath: projectFolder.path) {
                try FileManager.default.removeItem(at: projectFolder)
            }
            if FileManager.default.fileExists(atPath: drawingsCacheURL.path) {
                try FileManager.default.removeItem(at: drawingsCacheURL)
            }
            if FileManager.default.fileExists(atPath: rfisCacheURL.path) {
                try FileManager.default.removeItem(at: rfisCacheURL)
            }
            if FileManager.default.fileExists(atPath: formsCacheURL.path) {
                try FileManager.default.removeItem(at: formsCacheURL)
            }
            print("Offline data cleared for project \(projectId)")
        } catch {
            print("Error clearing offline data: \(error)")
        }
    }
    
    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(drawings.count) drawings to cache for project \(projectId)")
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
    
    private func saveFormsToCache(_ forms: [FormModel]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(forms) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("forms_project_\(projectId).json")
            try? data.write(to: cacheURL)
            print("Saved \(forms.count) forms to cache for project \(projectId)")
        }
    }
    
    struct StatCard: View {
        let title: String
        let value: String
        let trend: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                
                HStack(alignment: .bottom, spacing: 4) {
                    Text(value)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.black)
                    
                    Text(trend)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 80)
            .padding(12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    struct SummaryTile: View {
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        var isSelected: Bool
        
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(color)
                    )
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.black)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white)
                    .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
            )
            .scaleEffect(isSelected ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
    
    struct ProjectSummaryView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                ProjectSummaryView(projectId: 1, token: "sample_token")
            }
        }
    }
}
