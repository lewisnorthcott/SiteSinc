import SwiftUI
import WebKit

struct DrawingListView: View {
    let projectId: Int
    let token: String
    let projectName: String
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Add to access NetworkStatusManager
    @State private var drawings: [Drawing] = []
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

    var filteredDrawings: [Drawing] {
        if searchText.isEmpty {
            return drawings
        } else {
            return drawings.filter {
                $0.title.lowercased().contains(searchText.lowercased()) ||
                $0.number.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    private var groupedDrawings: [String: [Drawing]] {
        let drawingsToGroup = filteredDrawings
        switch groupByOption {
        case .company:
            return Dictionary(grouping: drawingsToGroup, by: { $0.company?.name ?? "Unknown Company" })
        case .discipline:
            return Dictionary(grouping: drawingsToGroup, by: { $0.projectDiscipline?.name ?? "No Discipline" })
        case .type:
            return Dictionary(grouping: drawingsToGroup, by: { $0.projectDrawingType?.name ?? "No Type" })
        case .all:
            return ["All Drawings": drawingsToGroup]
        }
    }

    private var groupKeys: [String] {
        groupedDrawings.keys.sorted()
    }

    private func drawingsForGroup(key: String) -> [Drawing] {
        groupedDrawings[key] ?? []
    }

    private var groupMenuLabel: some View {
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

    private var groupMenuContent: some View {
        ForEach(GroupByOption.allCases) { option in
            Button(action: {
                groupByOption = option
            }) {
                Text(option.rawValue)
            }
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack {
                        Menu {
                            groupMenuContent
                        } label: {
                            groupMenuLabel
                        }
                        .accessibilityLabel("Group drawings by \(groupByOption.rawValue)")
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
                
                if isLoading {
                    ProgressView("Loading Drawings...")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#3B82F6")))
                        .padding()
                        .frame(maxHeight: .infinity)
                } else if let errorMessage = errorMessage {
                    VStack {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.red)
                            .padding()
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            fetchDrawings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#3B82F6"))
                        .accessibilityLabel("Retry loading drawings")
                    }
                    .padding()
                    .frame(maxHeight: .infinity)
                } else if groupKeys.isEmpty && filteredDrawings.isEmpty {
                    Text(searchText.isEmpty ? "No drawings found for this project." : "No drawings match your search.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding()
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        if isGridView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                                ForEach(groupKeys, id: \.self) { groupKey in
                                    NavigationLink(destination: FilteredDrawingsView(
                                        drawings: drawingsForGroup(key: groupKey),
                                        groupName: groupKey,
                                        token: token,
                                        projectName: projectName,
                                        projectId: projectId,
                                        isGridView: $isGridView,
                                        onRefresh: fetchDrawings,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(sessionManager).environmentObject(networkStatusManager)) { // Pass both environment objects
                                        GroupCard(groupKey: groupKey, count: drawingsForGroup(key: groupKey).count)
                                    }
                                }
                            }
                            .padding()
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(groupKeys, id: \.self) { groupKey in
                                    NavigationLink(destination: FilteredDrawingsView(
                                        drawings: drawingsForGroup(key: groupKey),
                                        groupName: groupKey,
                                        token: token,
                                        projectName: projectName,
                                        projectId: projectId,
                                        isGridView: $isGridView,
                                        onRefresh: fetchDrawings,
                                        isProjectOffline: isProjectOffline
                                    ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                        GroupRow(groupKey: groupKey, count: drawingsForGroup(key: groupKey).count)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .refreshable {
                        fetchDrawings()
                    }
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Menu {
                        Button(action: { showCreateRFI = true }) {
                            Label("New RFI", systemImage: "doc.text.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color(hex: "#3B82F6"))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                            .contentShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Create new item")
                }
            }
        }
        .navigationTitle("Drawings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .accessibilityLabel(isGridView ? "Switch to list view" : "Switch to grid view")
            }
        }
        .onAppear {
            print("DrawingListView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
            fetchDrawings()
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad && drawings.count > 0 {
                isGridView = true
            }
            #endif
            isProjectOffline = UserDefaults.standard.bool(forKey: "offlineMode_\(projectId)")
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName, onSuccess: {
                showCreateRFI = false
            })
        }
    }

    private func fetchDrawings() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                print("DrawingListView: Fetching drawings for project \(projectId)")
                let d = try await APIClient.fetchDrawings(projectId: projectId, token: token)
                print("DrawingListView: Successfully fetched \(d.count) drawings")
                await MainActor.run {
                    drawings = d.map {
                        var drawing = $0
                        drawing.isOffline = checkOfflineStatus(for: drawing)
                        return drawing
                    }
                    saveDrawingsToCache(drawings)
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad && !drawings.isEmpty && !isGridView {
                        // isGridView = true
                    }
                    #endif
                    isLoading = false
                }
            } catch APIError.tokenExpired {
                print("DrawingListView: Token expired error")
                await MainActor.run {
                    sessionManager.handleTokenExpiration()
                }
            } catch {
                print("DrawingListView: Error fetching drawings: \(error.localizedDescription), code: \((error as NSError).code)")
                await MainActor.run {
                    isLoading = false
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet, let cachedDrawings = loadDrawingsFromCache() {
                        print("DrawingListView: Offline mode - loaded \(cachedDrawings.count) cached drawings")
                        drawings = cachedDrawings.map {
                            var drawing = $0
                            drawing.isOffline = checkOfflineStatus(for: drawing)
                            return drawing
                        }
                        errorMessage = "Loaded cached drawings (offline)"
                    } else {
                        errorMessage = "Failed to load drawings: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func checkOfflineStatus(for drawing: Drawing) -> Bool {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let projectFolder = documentsDirectory.appendingPathComponent("Project_\(projectId)/drawings")
        
        let pdfFiles = drawing.revisions.flatMap { $0.drawingFiles }.filter { $0.fileName.lowercased().hasSuffix(".pdf") }
        if pdfFiles.isEmpty { return false }
        
        return pdfFiles.allSatisfy { file in
            FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(file.fileName).path)
        }
    }

    private func saveDrawingsToCache(_ drawings: [Drawing]) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(drawings) {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
            try? data.write(to: cacheURL)
        }
    }

    private func loadDrawingsFromCache() -> [Drawing]? {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("drawings_project_\(projectId).json")
        if let data = try? Data(contentsOf: cacheURL), let cachedDrawings = try? JSONDecoder().decode([Drawing].self, from: data) {
            return cachedDrawings
        }
        return nil
    }
}

struct GroupRow: View {
    let groupKey: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(width: 24, height: 24)

            Text(groupKey)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            Spacer()
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#3B82F6"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "#3B82F6").opacity(0.1))
                .clipShape(Capsule())
        }
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct GroupCard: View {
    let groupKey: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Color(hex: "#3B82F6"))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "#3B82F6"))
            }
            
            Spacer()
            
            Text(groupKey)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)

            Text("Drawings")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(Color(hex: "#6B7280"))
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, idealHeight: 140, maxHeight: 150)
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct SearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? Color(hex: "#3B82F6") : Color(hex: "#9CA3AF"))

            TextField("Search drawings by title or number...", text: $text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .focused($isFocused)
                .submitLabel(.search)

            if !text.isEmpty {
                Button(action: {
                    text = ""
                    isFocused = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(hex: "#9CA3AF"))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(isFocused ? Color.white : Color(hex: "#EFF2F7"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? Color(hex: "#3B82F6").opacity(0.7) : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct FilteredDrawingsView: View {
    let drawings: [Drawing]
    let groupName: String
    let token: String
    let projectName: String
    let projectId: Int
    @Binding var isGridView: Bool
    let onRefresh: () -> Void
    let isProjectOffline: Bool
    @EnvironmentObject var sessionManager: SessionManager // Added
    @EnvironmentObject var networkStatusManager: NetworkStatusManager // Added for debugging
    
    @State private var showCreateRFI = false

    private var sortedDrawings: [Drawing] {
        drawings.sorted { (lhs, rhs) in
            let lhsDate = lhs.updatedAt ?? lhs.createdAt ?? ""
            let rhsDate = rhs.updatedAt ?? rhs.createdAt ?? ""
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)

            if drawings.isEmpty {
                Text("No drawings found for \(groupName)")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .padding()
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)], spacing: 16) {
                            ForEach(sortedDrawings, id: \.id) { drawing in
                                NavigationLink(destination: DrawingGalleryView(
                                    drawings: drawings,
                                    initialDrawing: drawing,
                                    isProjectOffline: isProjectOffline
                                ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                    DrawingCard(drawing: drawing)
                                }
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedDrawings, id: \.id) { drawing in
                                NavigationLink(destination: DrawingGalleryView(
                                    drawings: drawings,
                                    initialDrawing: drawing,
                                    isProjectOffline: isProjectOffline
                                ).environmentObject(sessionManager).environmentObject(networkStatusManager)) {
                                    DrawingRow(drawing: drawing)
                                }
                            }
                        }
                        .padding()
                    }
                }
                .refreshable {
                    onRefresh()
                }
            }
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Menu {
                        Button(action: { showCreateRFI = true }) {
                            Label("New RFI", systemImage: "doc.text.fill")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color(hex: "#3B82F6"))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                            .contentShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .accessibilityLabel("Create new item")
                }
            }
        }
        .navigationTitle("\(groupName)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .accessibilityLabel(isGridView ? "Switch to list view" : "Switch to grid view")
            }
        }
        .sheet(isPresented: $showCreateRFI) {
            CreateRFIView(projectId: projectId, token: token, projectName: projectName ,onSuccess: {
                showCreateRFI = false
            })
        }
        .onAppear {
            print("FilteredDrawingsView: onAppear - NetworkStatusManager available: \(networkStatusManager.isNetworkAvailable)")
        }
    }
}

struct DrawingRow: View {
    let drawing: Drawing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(drawing.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))
                    .lineLimit(1)

                Text("No: \(drawing.number)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .lineLimit(1)

                if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    Text("Rev: \(latestRevision.revisionNumber ?? String(latestRevision.versionNumber))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#4B5563"))
                }
            }
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: drawing.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                    .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                    .font(.system(size: 18))

                Text("\(drawing.revisions.count) Revs")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(hex: "#3B82F6").opacity(0.8))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct DrawingCard: View {
    let drawing: Drawing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 32))
                .foregroundColor(Color(hex: "#3B82F6"))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 4)

            Text(drawing.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)

            Text("No: \(drawing.number)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#6B7280"))
            
            Spacer()

            HStack {
                Image(systemName: drawing.isOffline ?? false ? "checkmark.icloud.fill" : "icloud")
                    .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#9CA3AF"))
                    .font(.system(size: 16))
                Spacer()
                Text("\(drawing.revisions.count) Revs")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#4B5563"))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, idealHeight: 160, maxHeight: 170)
        .padding()
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    DrawingListView(projectId: 2, token: "sample-token", projectName: "Sample Project")
        .environmentObject(SessionManager())
        .environmentObject(NetworkStatusManager.shared)
}
