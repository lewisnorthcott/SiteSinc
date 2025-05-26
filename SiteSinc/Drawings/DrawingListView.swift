import SwiftUI
import WebKit

struct DrawingListView: View {
    let projectId: Int
    let token: String
    @State private var drawings: [Drawing] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var groupByOption: GroupByOption = .company
    @State private var searchText: String = ""
    @State private var isGridView: Bool = false // For tablet grid view toggle

    enum GroupByOption: String, CaseIterable, Identifiable {
        case company = "Company"
        case folder = "Folder"
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

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Filter Bar
                VStack(spacing: 8) {
                    Picker("Group By", selection: $groupByOption) {
                        ForEach(GroupByOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityLabel("Group drawings by")
                    
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
                } else if let errorMessage = errorMessage {
                    VStack {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.red)
                            .padding()
                        Button("Retry") {
                            fetchDrawings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#3B82F6"))
                        .accessibilityLabel("Retry loading drawings")
                    }
                } else if groupKeys.isEmpty {
                    Text("No drawings found for Project \(projectId)")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#6B7280"))
                        .padding()
                } else {
                    ScrollView {
                        if isGridView {
                            // Grid View for Tablets
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                                ForEach(groupKeys.sorted(), id: \.self) { groupKey in
                                    NavigationLink(destination: FilteredDrawingsView(
                                        drawings: self.filteredDrawings(for: groupKey),
                                        groupName: groupKey,
                                        token: token,
                                        isGridView: $isGridView,
                                        onRefresh: fetchDrawings
                                    )) {
                                        GroupCard(groupKey: groupKey, count: filteredDrawings(for: groupKey).count)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                        } else {
                            // List View
                            ForEach(groupKeys.sorted(), id: \.self) { groupKey in
                                NavigationLink(destination: FilteredDrawingsView(
                                    drawings: filteredDrawings(for: groupKey),
                                    groupName: groupKey,
                                    token: token,
                                    isGridView: $isGridView,
                                    onRefresh: fetchDrawings
                                )) {
                                    GroupRow(groupKey: groupKey, count: filteredDrawings(for: groupKey).count)
                                }
                                .padding(.vertical, 4)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .refreshable {
                        fetchDrawings()
                    }
                }
            }
        }
        .navigationTitle("Drawings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .accessibilityLabel(isGridView ? "Switch to list view" : "Switch to grid view")
            }
        }
        .onAppear {
            fetchDrawings()
        }
    }

    private var groupedDrawings: [String: [Drawing]] {
        switch groupByOption {
        case .company:
            return Dictionary(grouping: filteredDrawings, by: { $0.company?.name ?? "Unknown Company" })
        case .folder:
            return Dictionary(grouping: filteredDrawings, by: { _ in "Project \(projectId)" })
        case .discipline:
            let hasDiscipline = filteredDrawings.contains { $0.projectDiscipline?.name != nil }
            return Dictionary(grouping: filteredDrawings, by: {
                $0.projectDiscipline?.name ?? (hasDiscipline ? "Unknown Discipline" : "No Discipline Available")
            })
        case .type:
            let hasType = filteredDrawings.contains { $0.projectDrawingType?.name != nil }
            return Dictionary(grouping: filteredDrawings, by: {
                $0.projectDrawingType?.name ?? (hasType ? "Unknown Type" : "No Type Available")
            })
        case .all:
            return ["All Drawings": filteredDrawings] // Group all drawings under a single key
        }
    }

    private var groupKeys: [String] {
        groupedDrawings.keys.sorted()
    }

    private func filteredDrawings(for groupKey: String) -> [Drawing] {
        filteredDrawings.filter { drawing in
            switch groupByOption {
            case .company:
                return drawing.company?.name == groupKey
            case .folder:
                return "Project \(projectId)" == groupKey
            case .discipline:
                return drawing.projectDiscipline?.name == groupKey || (groupKey == "No Discipline Available" && drawing.projectDiscipline?.name == nil)
            case .type:
                return drawing.projectDrawingType?.name == groupKey || (groupKey == "No Type Available" && drawing.projectDrawingType?.name == nil)
            case .all:
                return groupKey == "All Drawings" // Return all drawings for the "All Drawings" group
            }
        }
    }

    private func fetchDrawings() {
        isLoading = true
        errorMessage = nil
        APIClient.fetchDrawings(projectId: projectId, token: token) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let d):
                    drawings = d.map {
                        var drawing = $0
                        drawing.isOffline = checkOfflineStatus(for: drawing)
                        return drawing
                    }
                    saveDrawingsToCache(drawings)
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorNotConnectedToInternet, let cachedDrawings = loadDrawingsFromCache() {
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
        return drawing.revisions.flatMap { $0.drawingFiles }.allSatisfy { file in
            guard file.fileName.lowercased().hasSuffix(".pdf") else { return true }
            return FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(file.fileName).path)
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
        HStack {
            Image(systemName: "folder.fill")
                .foregroundColor(Color(hex: "#3B82F6"))
            Text(groupKey)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            Spacer()
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "#3B82F6"))
                .padding(6)
                .background(Color(hex: "#3B82F6").opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct GroupCard: View {
    let groupKey: String
    let count: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#3B82F6"))
            Text(groupKey)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("\(count) Drawings")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(hex: "#6B7280"))
        }
        .frame(width: 160, height: 120)
        .padding(12)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(hex: "#6B7280"))
            TextField("Search drawings...", text: $text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(hex: "#6B7280"))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(hex: "#F1F5F9"))
        .cornerRadius(8)
    }
}

struct FilteredDrawingsView: View {
    let drawings: [Drawing]
    let groupName: String
    let token: String
    @Binding var isGridView: Bool
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            Color(hex: "#F7F9FC").edgesIgnoringSafeArea(.all)

            if drawings.isEmpty {
                Text("No drawings found for \(groupName)")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#6B7280"))
                    .padding()
            } else {
                ScrollView {
                    if isGridView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(drawings.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }, id: \.id) { drawing in
                                NavigationLink(destination: DrawingGalleryView(drawings: drawings, initialDrawing: drawing)) {
                                    DrawingCard(drawing: drawing)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    } else {
                        ForEach(drawings.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }, id: \.id) { drawing in
                            NavigationLink(destination: DrawingGalleryView(drawings: drawings, initialDrawing: drawing)) {
                                DrawingRow(drawing: drawing)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 16)
                            .swipeActions(edge: .leading) {
                                Button(action: { /* Toggle offline status */ }) {
                                    Label("Offline", systemImage: drawing.isOffline ?? false ? "cloud.fill" : "cloud")
                                }
                                .tint(Color(hex: "#10B981"))
                            }
                        }
                    }
                }
                .refreshable {
                    onRefresh()
                }
            }
        }
        .navigationTitle("\(groupName)")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isGridView.toggle() }) {
                    Image(systemName: isGridView ? "list.bullet" : "square.grid.2x2")
                        .foregroundColor(Color(hex: "#3B82F6"))
                }
                .accessibilityLabel(isGridView ? "Switch to list view" : "Switch to grid view")
            }
        }
    }
}

struct DrawingRow: View {
    let drawing: Drawing

    var body: some View {
        HStack {
            Image(systemName: "doc.text.fill")
                .foregroundColor(Color(hex: "#3B82F6"))
            VStack(alignment: .leading, spacing: 4) {
                Text(drawing.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#1F2A44"))
                Text(drawing.number)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(hex: "#6B7280"))
                if let latestRevision = drawing.revisions.max(by: { $0.versionNumber < $1.versionNumber }) {
                    Text("Rev \(latestRevision.revisionNumber ?? "N/A")")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7280"))
                }
            }
            Spacer()
            Image(systemName: drawing.isOffline ?? false ? "cloud.fill" : "cloud")
                .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#6B7280"))
            Text("\(drawing.revisions.count)")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#3B82F6"))
                .padding(6)
                .background(Color(hex: "#3B82F6").opacity(0.1))
                .clipShape(Circle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

struct DrawingCard: View {
    let drawing: Drawing

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 24))
                .foregroundColor(Color(hex: "#3B82F6"))
            Text(drawing.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(Color(hex: "#1F2A44"))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(drawing.number)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color(hex: "#6B7280"))
            HStack {
                Image(systemName: drawing.isOffline ?? false ? "cloud.fill" : "cloud")
                    .foregroundColor(drawing.isOffline ?? false ? Color(hex: "#10B981") : Color(hex: "#6B7280"))
                Text("\(drawing.revisions.count) Rev")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#6B7280"))
            }
        }
        .frame(width: 160, height: 140)
        .padding(12)
        .background(Color(hex: "#FFFFFF"))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    DrawingListView(projectId: 2, token: "sample-token")
}
