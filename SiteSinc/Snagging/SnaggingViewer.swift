import SwiftUI
import PDFKit
import PhotosUI

struct SnaggingViewer: View {
    let projectId: Int
    let token: String
    let drawing: Drawing
    let drawingFileId: Int

    @EnvironmentObject var networkStatusManager: NetworkStatusManager
    @EnvironmentObject var sessionManager: SessionManager

    @State private var pdfURL: URL?
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var pageIndex: Int = 0
    @State private var pdfViewRef: PDFView? = nil
    @State private var snags: [APIClient.Snag] = []
    @State private var creatingPin: CGPoint? = nil
    @State private var creatingPage: Int = 1
    @State private var newTitle: String = ""
    @State private var newDescription: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var isAddingSnag: Bool = false
    @State private var selectedSnag: APIClient.Snag? = nil
    @State private var pdfViewVersion: Int = 0 // Forces pin overlay to update on scroll/zoom
    
    // Enhanced create snag state
    @State private var newPriority: String = "medium"
    @State private var selectedCompanyIds: [Int] = []
    @State private var selectedUserId: Int? = nil
    @State private var newSnagPhotos: [Data] = []
    @State private var companies: [APIClient.CompanyListItem] = []
    @State private var projectUsers: [User] = []
    @State private var isLoadingCompanies: Bool = false
    @State private var isLoadingUsers: Bool = false
    @State private var isCreatingSnag: Bool = false

    var canCreateSnags: Bool {
        sessionManager.hasPermission("snag_manager") || sessionManager.hasPermission("create_snags")
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let url = pdfURL {
                GeometryReader { geo in
                    ZStack {
                        PDFRepresentedView(url: url, pageIndex: $pageIndex, onCreated: { view in
                            // Avoid modifying state during view update
                            DispatchQueue.main.async { self.pdfViewRef = view }
                        }, onTap: handleTap, onViewChanged: {
                            // Increment version to force pin overlay refresh
                            pdfViewVersion += 1
                        })
                        pinOverlay(in: geo.size).zIndex(1)
                    }
                    .contentShape(Rectangle())
                }
            } else if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                Text(error).foregroundColor(.red)
            }

            if canCreateSnags {
                Button(action: { 
                    isAddingSnag.toggle()
                    if !isAddingSnag {
                        creatingPin = nil
                        showCreateSheet = false
                    }
                }) {
                    Image(systemName: isAddingSnag ? "mappin.circle.fill" : "mappin")
                        .font(.system(size: 20))
                        .foregroundColor(isAddingSnag ? .blue : .primary)
                        .padding(10)
                        .background(isAddingSnag ? Color.blue.opacity(0.2) : Color.clear)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(8)
            }
        }
        .navigationTitle(drawing.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPDFAndSnags() }
        .sheet(isPresented: $showCreateSheet) { createSnagSheet }
        .sheet(item: $selectedSnag) { snag in
            SnagDetailSheet(
                snag: snag,
                token: token,
                sessionManager: sessionManager,
                onClose: { selectedSnag = nil },
                onUpdate: { updatedSnag in
                    // Update the snag in the list
                    if let index = snags.firstIndex(where: { $0.id == updatedSnag.id }) {
                        snags[index] = updatedSnag
                    }
                    selectedSnag = nil
                }
            )
        }
    }

    private func pinOverlay(in size: CGSize) -> some View {
        // Use pdfViewVersion to force refresh when PDF scrolls/zooms
        let _ = pdfViewVersion
        
        return ZStack {
            // Existing snags - tappable
            ForEach(snags, id: \.id) { snag in
                if let pdfView = pdfViewRef,
                   snag.position.page == pageIndex + 1,
                   let page = pdfView.document?.page(at: pageIndex) {
                    let viewPoint = pdfView.convert(CGPoint(x: snag.position.x, y: snag.position.y), from: page)
                    
                    Button(action: {
                        selectedSnag = snag
                    }) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(snagColor(for: snag))
                            .frame(width: 44, height: 44)
                    }
                    .position(x: viewPoint.x, y: viewPoint.y)
                }
            }
            
            // New pin preview (only when adding)
            if isAddingSnag, let creatingPin = creatingPin {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.blue)
                    .position(x: creatingPin.x, y: creatingPin.y)
                    .allowsHitTesting(false)
            }
        }
    }

    private func snagColor(for snag: APIClient.Snag) -> Color {
        switch snag.status.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .yellow
        case "CLOSED": return .green
        default: return .gray
        }
    }

    private func handleTap(location: CGPoint) {
        // Only create new snags when in adding mode
        guard isAddingSnag, canCreateSnags, let pdfView = pdfViewRef, pdfView.document?.page(at: pageIndex) != nil else { return }
        creatingPin = location
        creatingPage = pageIndex + 1
        showCreateSheet = true
    }

    private var createSnagSheet: some View {
        CreateSnagSheet(
            projectId: projectId,
            token: token,
            drawingId: drawing.id,
            drawingFileId: drawingFileId,
            drawingTitle: drawing.title,
            drawingNumber: drawing.number,
            creatingPin: creatingPin,
            creatingPage: creatingPage,
            pdfView: pdfViewRef,
            pageIndex: pageIndex,
            sessionManager: sessionManager,
            onCancel: {
                showCreateSheet = false
                creatingPin = nil
                resetCreateForm()
            },
            onCreate: { snag in
                snags.append(snag)
                showCreateSheet = false
                creatingPin = nil
                isAddingSnag = false
                resetCreateForm()
            }
        )
    }
    
    private func resetCreateForm() {
        newTitle = ""
        newDescription = ""
        newPriority = "medium"
        selectedCompanyIds = []
        selectedUserId = nil
        newSnagPhotos = []
    }

    private func loadPDFAndSnags() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            // Try offline path first (project offline cache)
            if let localURL = try findOfflinePDF() {
                await MainActor.run { self.pdfURL = localURL }
            } else {
                let url = try await APIClient.fetchDrawingPDFViaProxy(drawingFileId: drawingFileId, token: token)
                await MainActor.run { self.pdfURL = url }
            }
            // Fetch with file filter and without, then merge unique by id
            async let withFileTask = APIClient.fetchSnagsForDrawing(projectId: projectId, drawingId: drawing.id, drawingFileId: drawingFileId, page: nil, token: token)
            async let withoutFileTask = APIClient.fetchSnagsForDrawing(projectId: projectId, drawingId: drawing.id, drawingFileId: nil, page: nil, token: token)
            var combined: [APIClient.Snag] = []
            do {
                let (withFile, withoutFile) = try await (withFileTask, withoutFileTask)
                var seen: Set<Int> = []
                for s in (withFile + withoutFile) {
                    if !seen.contains(s.id) { combined.append(s); seen.insert(s.id) }
                }
            } catch {
                // If one fails, try the other
                do { combined = try await withFileTask } catch { combined = try await withoutFileTask }
            }
            print("SnaggingViewer: fetched snags merged count=\(combined.count) for drawingId=\(drawing.id), fileId=\(drawingFileId)")
            await MainActor.run { self.snags = combined; self.isLoading = false }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription; self.isLoading = false }
        }
    }

    private func findOfflinePDF() throws -> URL? {
        // Match ProjectSummaryView offline storage (revision-keyed with legacy fallback)
        if let pdfFile = drawing.revisions
            .flatMap({ $0.drawingFiles })
            .first(where: { $0.id == drawingFileId }) {
            return DrawingFileCache.cachedURL(projectId: projectId, file: pdfFile, allowLegacy: true)
        }
        return nil
    }

}

// MARK: - Create Snag Sheet
private struct CreateSnagSheet: View {
    let projectId: Int
    let token: String
    let drawingId: Int
    let drawingFileId: Int
    let drawingTitle: String
    let drawingNumber: String
    let creatingPin: CGPoint?
    let creatingPage: Int
    let pdfView: PDFView?
    let pageIndex: Int
    let sessionManager: SessionManager
    let onCancel: () -> Void
    let onCreate: (APIClient.Snag) -> Void
    
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: String = "medium"
    @State private var selectedCompanyIds: [Int] = []
    @State private var selectedUserId: Int? = nil
    @State private var photos: [Data] = []
    @State private var companies: [APIClient.CompanyListItem] = []
    @State private var users: [User] = []
    @State private var isLoadingCompanies: Bool = false
    @State private var isLoadingUsers: Bool = false
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showCamera: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var focusedField: FocusedField?
    
    private enum FocusedField {
        case title, description
    }
    
    private let priorities = ["low", "medium", "high", "critical"]
    
    /// Users filtered by selected companies (if any companies selected)
    private var filteredUsers: [User] {
        if selectedCompanyIds.isEmpty {
            return users
        }
        return users.filter { user in
            guard let userCompanyId = user.companyId else { return false }
            return selectedCompanyIds.contains(userCompanyId)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Details Section
                Section(header: Text("Snag Details")) {
                    TextField("Title *", text: $title)
                        .focused($focusedField, equals: .title)
                    
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .description)
                    
                    // Priority Picker
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { p in
                            HStack {
                                Circle()
                                    .fill(priorityColor(p))
                                    .frame(width: 10, height: 10)
                                Text(p.capitalized)
                            }
                            .tag(p)
                        }
                    }
                }
                
                // MARK: - Assignment Section
                Section(header: Text("Assignment")) {
                    // Company Selection
                    NavigationLink {
                        CompanySelectionView(
                            companies: companies,
                            selectedIds: $selectedCompanyIds,
                            isLoading: isLoadingCompanies
                        )
                    } label: {
                        HStack {
                            Text("Assign to Company")
                            Spacer()
                            if isLoadingCompanies {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if selectedCompanyIds.isEmpty {
                                Text("None")
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(selectedCompanyIds.count) selected")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // User Selection (optional) - filtered by selected companies
                    NavigationLink {
                        SnagUserSelectionView(
                            users: filteredUsers,
                            selectedUserId: $selectedUserId,
                            isLoading: isLoadingUsers
                        )
                    } label: {
                        HStack {
                            Text("Assign to User")
                            Spacer()
                            if isLoadingUsers {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if let userId = selectedUserId,
                                      let user = filteredUsers.first(where: { $0.id == userId }) {
                                Text(user.displayName)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(selectedCompanyIds.isEmpty ? "Select company first" : "Optional")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(selectedCompanyIds.isEmpty)
                }
                
                // MARK: - Photos Section
                Section(header: Text("Photos")) {
                    if !photos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(photos.indices, id: \.self) { index in
                                    ZStack(alignment: .topTrailing) {
                                        if let uiImage = UIImage(data: photos[index]) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 80, height: 80)
                                                .clipped()
                                                .cornerRadius(8)
                                        }
                                        
                                        Button(action: {
                                            photos.remove(at: index)
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                        }
                                        .offset(x: 4, y: -4)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            focusedField = nil
                            showCamera = true
                        }) {
                            Label("Camera", systemImage: "camera.fill")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        PhotosPicker(
                            selection: $selectedPhotoItems,
                            maxSelectionCount: 5,
                            matching: .images
                        ) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .simultaneousGesture(TapGesture().onEnded {
                            focusedField = nil
                        })
                    }
                }
                
                // MARK: - Location Section
                Section(header: Text("Location")) {
                    HStack {
                        Text("Drawing")
                        Spacer()
                        Text("\(drawingNumber) – \(drawingTitle)")
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Error message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Snag")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .disabled(isCreating)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { Task { await createSnag() } }) {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .sheet(isPresented: $showCamera) {
                SnagCameraView { imageData in
                    if let data = imageData {
                        photos.append(data)
                    }
                    showCamera = false
                }
            }
            .onChange(of: selectedPhotoItems) {
                Task {
                    for item in selectedPhotoItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                photos.append(data)
                            }
                        }
                    }
                    await MainActor.run {
                        selectedPhotoItems = []
                    }
                }
            }
            .onChange(of: selectedCompanyIds) {
                // Clear selected user if they're no longer in a selected company
                if let userId = selectedUserId {
                    let userStillValid = filteredUsers.contains { $0.id == userId }
                    if !userStillValid {
                        selectedUserId = nil
                    }
                }
            }
            .onAppear {
                loadAssignmentOptions()
            }
        }
    }
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical": return .purple
        case "high": return .red
        case "medium": return .orange
        case "low": return .green
        default: return .gray
        }
    }
    
    /// Loads companies and users from the snag assignment-options endpoint (project companies + users who can view/respond to snags).
    private func loadAssignmentOptions() {
        guard companies.isEmpty && users.isEmpty else { return }
        isLoadingCompanies = true
        isLoadingUsers = true
        Task {
            do {
                let (loadedCompanies, loadedUsers) = try await APIClient.fetchSnagAssignmentOptions(projectId: projectId, token: token)
                await MainActor.run {
                    self.companies = loadedCompanies
                    self.users = loadedUsers
                    self.isLoadingCompanies = false
                    self.isLoadingUsers = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingCompanies = false
                    self.isLoadingUsers = false
                }
            }
        }
    }
    
    private func createSnag() async {
        guard let pin = creatingPin,
              let view = pdfView,
              let page = view.document?.page(at: pageIndex) else { return }
        
        await MainActor.run {
            isCreating = true
            errorMessage = nil
        }
        
        let pdfPoint = view.convert(pin, to: page)
        let position = APIClient.SnagPosition(x: Double(pdfPoint.x), y: Double(pdfPoint.y), page: creatingPage)
        
        do {
            let created = try await APIClient.createSnag(
                projectId: projectId,
                drawingId: drawingId,
                drawingFileId: drawingFileId,
                page: creatingPage,
                position: position,
                title: title,
                description: description.isEmpty ? nil : description,
                companyIds: selectedCompanyIds,
                assigneeId: selectedUserId,
                priority: priority,
                status: "OPEN",
                responseDate: nil,
                photos: photos,
                token: token
            )
            await MainActor.run {
                isCreating = false
                onCreate(created)
            }
        } catch {
            await MainActor.run {
                isCreating = false
                errorMessage = "Failed to create snag: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Company Selection View
private struct CompanySelectionView: View {
    let companies: [APIClient.CompanyListItem]
    @Binding var selectedIds: [Int]
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading companies...")
            } else if companies.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No companies available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(companies) { company in
                        Button(action: {
                            if let index = selectedIds.firstIndex(of: company.id) {
                                selectedIds.remove(at: index)
                            } else {
                                selectedIds.append(company.id)
                            }
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(company.name)
                                        .foregroundColor(.primary)
                                    if let email = company.email, !email.isEmpty {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedIds.contains(company.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Select Company")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Snag User Selection View
private struct SnagUserSelectionView: View {
    let users: [User]
    @Binding var selectedUserId: Int?
    let isLoading: Bool
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading users...")
            } else if users.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No users available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // None option
                    Button(action: {
                        selectedUserId = nil
                    }) {
                        HStack {
                            Text("None")
                                .foregroundColor(.secondary)
                            Spacer()
                            if selectedUserId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    ForEach(users) { user in
                        Button(action: {
                            selectedUserId = user.id
                        }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(user.displayName)
                                        .foregroundColor(.primary)
                                    if let email = user.email {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedUserId == user.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Select User")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFRepresentedView: UIViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int
    var onCreated: ((PDFView) -> Void)? = nil
    var onTap: ((CGPoint) -> Void)? = nil
    var onViewChanged: (() -> Void)? = nil

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        if let page = view.document?.page(at: pageIndex) { view.go(to: page) }
        onCreated?(view)
        
        // Observe PDF view changes for scroll/zoom
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewChanged),
            name: .PDFViewScaleChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewChanged),
            name: .PDFViewPageChanged,
            object: view
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pdfViewChanged),
            name: .PDFViewVisiblePagesChanged,
            object: view
        )
        
        // Use a display link to track scroll changes without hijacking the delegate
        context.coordinator.setupDisplayLink(for: view)
        
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if let current = uiView.currentPage, uiView.document?.index(for: current) != pageIndex {
            if let page = uiView.document?.page(at: pageIndex) { uiView.go(to: page) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.displayLink?.invalidate()
    }

    class Coordinator: NSObject {
        let parent: PDFRepresentedView
        var displayLink: CADisplayLink?
        weak var pdfView: PDFView?
        var lastContentOffset: CGPoint = .zero
        var lastScale: CGFloat = 1.0
        
        init(_ parent: PDFRepresentedView) { self.parent = parent }
        
        func setupDisplayLink(for pdfView: PDFView) {
            self.pdfView = pdfView
            displayLink = CADisplayLink(target: self, selector: #selector(checkForChanges))
            displayLink?.add(to: .main, forMode: .common)
        }
        
        @objc func checkForChanges() {
            guard let pdfView = pdfView else { return }
            
            // Find the scroll view
            if let scrollView = pdfView.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
                let currentOffset = scrollView.contentOffset
                let currentScale = scrollView.zoomScale
                
                if currentOffset != lastContentOffset || currentScale != lastScale {
                    lastContentOffset = currentOffset
                    lastScale = currentScale
                    parent.onViewChanged?()
                }
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let point = gesture.location(in: view)
            parent.onTap?(point)
        }
        
        @objc func pdfViewChanged() {
            parent.onViewChanged?()
        }
    }
}

private struct SnagDetailSheet: View {
    let snag: APIClient.Snag
    let token: String
    let sessionManager: SessionManager
    let onClose: () -> Void
    let onUpdate: (APIClient.Snag) -> Void
    
    @State private var isUpdating: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showCamera: Bool = false
    @State private var resolutionPhotos: [Data] = []
    @State private var showResolveConfirmation: Bool = false
    @State private var selectedAttachment: APIClient.SnagAttachment? = nil
    @State private var resolutionComment: String = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    
    // MARK: - Permission Checks
    
    /// User has snag_manager permission (full access)
    private var hasSnagManager: Bool {
        sessionManager.hasPermission("snag_manager")
    }
    
    /// User has accept_snags permission (can start work)
    private var hasAcceptSnags: Bool {
        sessionManager.hasPermission("accept_snags") || hasSnagManager
    }
    
    /// User has submit_completion_snag permission (can mark resolved)
    private var hasSubmitCompletion: Bool {
        sessionManager.hasPermission("submit_completion_snag") || hasSnagManager
    }
    
    /// User has verify_snag permission (can verify & close)
    private var hasVerifySnag: Bool {
        sessionManager.hasPermission("verify_snag") || hasSnagManager
    }
    
    /// User's company is one of the assigned companies
    private var isAssignedCompany: Bool {
        guard let userCompanyId = sessionManager.user?.companyId,
              let assignments = snag.assignments else { return false }
        return assignments.contains { $0.companyId == userCompanyId }
    }
    
    /// User raised this snag
    private var isCreator: Bool {
        guard let userId = sessionManager.user?.id,
              let snagUserId = snag.userId else { return false }
        return userId == snagUserId
    }
    
    /// Can Start Work: Assigned company OR accept_snags permission (when status is OPEN)
    private var canStartWork: Bool {
        snag.status.uppercased() == "OPEN" && (isAssignedCompany || hasAcceptSnags)
    }
    
    /// Can Mark Resolved: Assigned company OR submit_completion_snag permission (when status is IN_PROGRESS)
    private var canMarkResolved: Bool {
        snag.status.uppercased() == "IN_PROGRESS" && (isAssignedCompany || hasSubmitCompletion)
    }
    
    /// Can Verify & Close: Creator OR verify_snag permission (when status is RESOLVED)
    private var canVerifyClose: Bool {
        snag.status.uppercased() == "RESOLVED" && (isCreator || hasVerifySnag)
    }
    
    // Separate initial photos from resolution photos
    private var initialPhotos: [APIClient.SnagAttachment] {
        guard let attachments = snag.attachments else { return [] }
        // Photos explicitly marked as initial
        let explicitInitial = attachments.filter { $0.photoType?.lowercased() == "initial" }
        if !explicitInitial.isEmpty {
            return explicitInitial
        }
        // If snag is still open/in progress, show all non-resolution photos
        if !hasBeenResolved {
            return attachments.filter { $0.photoType?.lowercased() != "resolution" }
        }
        // If resolved but no explicit initial photos, don't show any here (they go to work complete)
        return []
    }
    
    private var resolutionAttachments: [APIClient.SnagAttachment] {
        guard let attachments = snag.attachments else { return [] }
        // Photos explicitly marked as resolution
        let explicitResolution = attachments.filter { $0.photoType?.lowercased() == "resolution" }
        if !explicitResolution.isEmpty {
            return explicitResolution
        }
        // If resolved/closed and no explicit resolution photos, show all photos here
        if hasBeenResolved {
            return attachments.filter { $0.photoType?.lowercased() != "initial" }
        }
        return []
    }
    
    private var hasBeenResolved: Bool {
        let status = snag.status.uppercased()
        return status == "RESOLVED" || status == "CLOSED"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Header Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snag.title)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                if let description = snag.description, !description.isEmpty {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            SnagStatusBadge(status: snag.status)
                        }
                        
                        HStack(spacing: 16) {
                            if let priority = snag.priority {
                                Label(priority.capitalized, systemImage: "flag.fill")
                                    .font(.caption)
                                    .foregroundColor(priorityColor(priority))
                            }
                            if let assignments = snag.assignments, !assignments.isEmpty {
                                Label(assignments.map { $0.company?.name ?? "Company" }.joined(separator: ", "), systemImage: "building.2")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if let assigned = snag.assignedUser ?? (snag.userId != nil ? APIClient.SnagAssignedUser(id: snag.userId!, email: nil, tenants: nil) : nil) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Assigned to \(assigned.displayName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // MARK: - Timeline
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PROGRESS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                        
                        SnagTimelineView(currentStatus: snag.status, createdAt: snag.createdAt, updatedAt: snag.updatedAt)
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                    }
                    .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // MARK: - Location & Initial Photo
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LOCATION")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(.blue)
                                    Text("Page \(snag.page)")
                                        .font(.subheadline)
                                }
                                HStack {
                                    Image(systemName: "mappin.circle")
                                        .foregroundColor(.red)
                                    Text(String(format: "%.0f, %.0f", snag.position.x, snag.position.y))
                                        .font(.subheadline)
                                }
                                if let createdAt = snag.createdAt {
                                    HStack {
                                        Image(systemName: "calendar")
                                            .foregroundColor(.orange)
                                        Text(formattedDate(createdAt))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Initial photo thumbnail
                            if let firstPhoto = initialPhotos.first {
                                Button(action: { selectedAttachment = firstPhoto }) {
                                    SnagAttachmentThumbnail(attachment: firstPhoto)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Additional initial photos
                        if initialPhotos.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(initialPhotos.dropFirst()) { attachment in
                                        Button(action: { selectedAttachment = attachment }) {
                                            SnagAttachmentThumbnail(attachment: attachment)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    
                    // MARK: - Work Complete Section (Resolution Photos)
                    if hasBeenResolved || !resolutionAttachments.isEmpty || canMarkResolved {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver.fill")
                                    .foregroundColor(.orange)
                                Text("WORK COMPLETE")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if hasBeenResolved {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            
                            // Show resolution info if resolved
                            if hasBeenResolved {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let resolvedAt = snag.resolvedAt {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text("Resolved: \(formattedDate(resolvedAt))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if let resolvedBy = snag.resolvedBy {
                                        HStack(spacing: 6) {
                                            Image(systemName: "person.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text("By: \(resolvedBy.firstName ?? "") \(resolvedBy.lastName ?? "")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                // Show comments from resolution
                                if let comments = snag.comments, !comments.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(comments) { comment in
                                            SnagCommentBubble(comment: comment, formattedDate: formattedDate)
                                        }
                                    }
                                }
                            }
                            
                            // Resolution photos
                            if !resolutionAttachments.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(resolutionAttachments) { attachment in
                                            Button(action: { selectedAttachment = attachment }) {
                                                SnagAttachmentThumbnail(attachment: attachment)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                }
                            } else if hasBeenResolved {
                                Text("Work completed")
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                            
                            if canMarkResolved {
                                // Show photo capture UI
                                VStack(spacing: 12) {
                                    if !resolutionPhotos.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(resolutionPhotos.indices, id: \.self) { index in
                                                    ZStack(alignment: .topTrailing) {
                                                        if let uiImage = UIImage(data: resolutionPhotos[index]) {
                                                            Image(uiImage: uiImage)
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fill)
                                                                .frame(width: 80, height: 80)
                                                                .clipped()
                                                                .cornerRadius(8)
                                                        }
                                                        
                                                        // Remove button
                                                        Button(action: {
                                                            resolutionPhotos.remove(at: index)
                                                        }) {
                                                            Image(systemName: "xmark.circle.fill")
                                                                .font(.system(size: 18))
                                                                .foregroundColor(.white)
                                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                                        }
                                                        .offset(x: 4, y: -4)
                                                    }
                                                }
                                                
                                                // Add more - Camera button
                                                Button(action: { showCamera = true }) {
                                                    VStack(spacing: 4) {
                                                        Image(systemName: "camera.fill")
                                                            .font(.system(size: 20))
                                                        Text("Camera")
                                                            .font(.caption2)
                                                    }
                                                    .foregroundColor(.blue)
                                                    .frame(width: 70, height: 80)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(8)
                                                }
                                                
                                                // Add more - Library button
                                                PhotosPicker(
                                                    selection: $selectedPhotoItems,
                                                    maxSelectionCount: 5,
                                                    matching: .images
                                                ) {
                                                    VStack(spacing: 4) {
                                                        Image(systemName: "photo.on.rectangle")
                                                            .font(.system(size: 20))
                                                        Text("Library")
                                                            .font(.caption2)
                                                    }
                                                    .foregroundColor(.blue)
                                                    .frame(width: 70, height: 80)
                                                    .background(Color.blue.opacity(0.1))
                                                    .cornerRadius(8)
                                                }
                                            }
                                        }
                                    } else {
                                        // Camera and Photo Library buttons
                                        HStack(spacing: 12) {
                                            Button(action: { showCamera = true }) {
                                                HStack {
                                                    Image(systemName: "camera.fill")
                                                    Text("Take Photo")
                                                }
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color.blue)
                                                .cornerRadius(10)
                                            }
                                            
                                            PhotosPicker(
                                                selection: $selectedPhotoItems,
                                                maxSelectionCount: 5,
                                                matching: .images
                                            ) {
                                                HStack {
                                                    Image(systemName: "photo.on.rectangle")
                                                    Text("Library")
                                                }
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.blue)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(Color.blue.opacity(0.1))
                                                .cornerRadius(10)
                                            }
                                        }
                                    }
                                    
                                    // Comment field for resolution
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Resolution Notes")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        TextField("Describe the work completed...", text: $resolutionComment, axis: .vertical)
                                            .textFieldStyle(.roundedBorder)
                                            .lineLimit(3...6)
                                    }
                                    
                                    if !resolutionPhotos.isEmpty {
                                        Button(action: { Task { await resolveWithPhotos() } }) {
                                            HStack {
                                                if isUpdating {
                                                    ProgressView()
                                                        .tint(.white)
                                                } else {
                                                    Image(systemName: "checkmark.seal.fill")
                                                    Text("Submit & Mark Resolved")
                                                }
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.orange)
                                            .cornerRadius(10)
                                        }
                                        .disabled(isUpdating)
                                    } else {
                                        Text("Photo required to mark as resolved")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    
                    // MARK: - Start Work Action (when OPEN)
                    if canStartWork {
                        Divider()
                        
                        VStack(spacing: 12) {
                            Button(action: { Task { await updateStatus(to: "IN_PROGRESS") } }) {
                                HStack {
                                    if isUpdating {
                                        ProgressView()
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "play.fill")
                                        Text("Start Work")
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange)
                                .cornerRadius(12)
                            }
                            .disabled(isUpdating)
                            
                            Text("Begin working on this snag")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    
                    // MARK: - Verification Section (when RESOLVED or showing closed info)
                    if canVerifyClose || snag.status.uppercased() == "CLOSED" {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.green)
                                Text("VERIFICATION")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                if snag.status.uppercased() == "CLOSED" {
                                    Text("Verified")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green)
                                        .cornerRadius(8)
                                }
                            }
                            
                            // Show closed info if closed
                            if snag.status.uppercased() == "CLOSED" {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let closedAt = snag.closedAt {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text("Closed: \(formattedDate(closedAt))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    if let closedBy = snag.closedBy {
                                        HStack(spacing: 6) {
                                            Image(systemName: "person.fill")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                            Text("By: \(closedBy.firstName ?? "") \(closedBy.lastName ?? "")")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Text("This snag has been verified and closed.")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                        .padding(.top, 4)
                                }
                            } else if canVerifyClose {
                                Text("Review the resolution and verify the work is complete.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Button(action: { Task { await updateStatus(to: "CLOSED") } }) {
                                    HStack {
                                        if isUpdating {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "checkmark.circle.fill")
                                            Text("Verify & Close Snag")
                                        }
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.green)
                                    .cornerRadius(12)
                                }
                                .disabled(isUpdating)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Snag Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .sheet(isPresented: $showCamera) {
                SnagCameraView { imageData in
                    if let data = imageData {
                        resolutionPhotos.append(data)
                    }
                    showCamera = false
                }
            }
            .fullScreenCover(item: $selectedAttachment) { attachment in
                SnagAttachmentFullScreen(attachment: attachment) {
                    selectedAttachment = nil
                }
            }
            .onChange(of: selectedPhotoItems) {
                Task {
                    for item in selectedPhotoItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                resolutionPhotos.append(data)
                            }
                        }
                    }
                    await MainActor.run {
                        selectedPhotoItems = []
                    }
                }
            }
        }
    }
    
    private func updateStatus(to newStatus: String) async {
        await MainActor.run { 
            isUpdating = true 
            errorMessage = nil
        }
        
        do {
            let updatedSnag = try await APIClient.updateSnag(
                snagId: snag.id,
                fields: ["status": newStatus],
                token: token
            )
            await MainActor.run {
                isUpdating = false
                onUpdate(updatedSnag)
            }
        } catch {
            await MainActor.run {
                isUpdating = false
                errorMessage = "Failed to update: \(error.localizedDescription)"
            }
        }
    }
    
    private func resolveWithPhotos() async {
        await MainActor.run { 
            isUpdating = true 
            errorMessage = nil
        }
        
        do {
            let updatedSnag = try await APIClient.updateSnagWithPhotos(
                snagId: snag.id,
                status: "RESOLVED",
                photos: resolutionPhotos,
                comment: resolutionComment.isEmpty ? nil : resolutionComment,
                token: token
            )
            await MainActor.run {
                isUpdating = false
                onUpdate(updatedSnag)
            }
        } catch {
            await MainActor.run {
                isUpdating = false
                errorMessage = "Failed to resolve: \(error.localizedDescription)"
            }
        }
    }
    
    private func formattedDate(_ dateString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        // Try without fractional seconds
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) {
            return formatter.string(from: date)
        }
        return dateString
    }
    
    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "high", "urgent": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .gray
        }
    }
}

// MARK: - Timeline View
private struct SnagTimelineView: View {
    let currentStatus: String
    let createdAt: String?
    let updatedAt: String?
    
    private let stages = ["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"]
    private let stageLabels = ["Raised", "In Progress", "Resolved", "Closed"]
    private let stageIcons = ["exclamationmark.circle", "wrench.and.screwdriver", "checkmark.seal", "checkmark.circle"]
    
    private var currentIndex: Int {
        stages.firstIndex(of: currentStatus.uppercased()) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 6) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(circleColor(for: index))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: stageIcons[index])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(iconColor(for: index))
                    }
                    
                    // Label
                    Text(stageLabels[index])
                        .font(.system(size: 10, weight: index <= currentIndex ? .semibold : .regular))
                        .foregroundColor(index <= currentIndex ? .primary : .secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                
                // Connector line
                if index < 3 {
                    Rectangle()
                        .fill(index < currentIndex ? stageColor(for: index + 1) : Color.gray.opacity(0.3))
                        .frame(height: 3)
                        .offset(y: -12)
                }
            }
        }
    }
    
    private func circleColor(for index: Int) -> Color {
        if index < currentIndex {
            return stageColor(for: index).opacity(0.2)
        } else if index == currentIndex {
            return stageColor(for: index)
        } else {
            return Color.gray.opacity(0.15)
        }
    }
    
    private func iconColor(for index: Int) -> Color {
        if index <= currentIndex {
            return index == currentIndex ? .white : stageColor(for: index)
        } else {
            return .gray.opacity(0.5)
        }
    }
    
    private func stageColor(for index: Int) -> Color {
        switch index {
        case 0: return .red
        case 1: return .orange
        case 2: return .yellow
        case 3: return .green
        default: return .gray
        }
    }
}

// MARK: - Comment Bubble View
private struct SnagCommentBubble: View {
    let comment: APIClient.SnagComment
    let formattedDate: (String) -> String
    
    private var userName: String {
        if let tenants = comment.user?.tenants, let tenant = tenants.first {
            let firstName = tenant.firstName ?? ""
            let lastName = tenant.lastName ?? ""
            if !firstName.isEmpty || !lastName.isEmpty {
                return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
            }
        }
        return comment.user?.email ?? "Unknown"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "person.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text(userName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                if let createdAt = comment.createdAt {
                    Text(formattedDate(createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(comment.comment)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
}

// MARK: - Simple Camera View for Snag Resolution
private struct SnagCameraView: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void
        
        init(onCapture: @escaping (Data?) -> Void) {
            self.onCapture = onCapture
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onCapture(data)
            } else {
                onCapture(nil)
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

private struct SnagStatusBadge: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(formattedStatus)
                .font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .cornerRadius(12)
    }
    
    private var statusColor: Color {
        switch status.uppercased() {
        case "OPEN": return .red
        case "IN_PROGRESS": return .orange
        case "RESOLVED": return .yellow
        case "CLOSED": return .green
        default: return .gray
        }
    }
    
    private var formattedStatus: String {
        switch status.uppercased() {
        case "OPEN": return "Open"
        case "IN_PROGRESS": return "In Progress"
        case "RESOLVED": return "Resolved"
        case "CLOSED": return "Closed"
        default: return status
        }
    }
}

// MARK: - Attachment Thumbnail View
private struct SnagAttachmentThumbnail: View {
    let attachment: APIClient.SnagAttachment
    
    private var imageURL: URL? {
        if let presignedUrl = attachment.presignedUrl {
            return URL(string: presignedUrl)
        }
        return URL(string: attachment.fileUrl)
    }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 80, height: 80)
            
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: 80, height: 80)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipped()
                            .cornerRadius(8)
                    case .failure:
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                            Text("Error")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(width: 80, height: 80)
                    @unknown default:
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                            .frame(width: 80, height: 80)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                    Text(attachment.fileName.prefix(10) + "...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 80, height: 80)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Full Screen Attachment Viewer
private struct SnagAttachmentFullScreen: View {
    let attachment: APIClient.SnagAttachment
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    private var imageURL: URL? {
        if let presignedUrl = attachment.presignedUrl {
            return URL(string: presignedUrl)
        }
        return URL(string: attachment.fileUrl)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let url = imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { value in
                                            lastScale = scale
                                            // Limit zoom
                                            if scale < 1.0 {
                                                withAnimation {
                                                    scale = 1.0
                                                    lastScale = 1.0
                                                }
                                            } else if scale > 4.0 {
                                                withAnimation {
                                                    scale = 4.0
                                                    lastScale = 4.0
                                                }
                                            }
                                        }
                                )
                                .gesture(
                                    TapGesture(count: 2)
                                        .onEnded {
                                            withAnimation {
                                                if scale > 1.0 {
                                                    scale = 1.0
                                                    lastScale = 1.0
                                                } else {
                                                    scale = 2.0
                                                    lastScale = 2.0
                                                }
                                            }
                                        }
                                )
                        case .failure:
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.yellow)
                                Text("Failed to load image")
                                    .foregroundColor(.white)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Text("Unable to load attachment")
                        .foregroundColor(.white)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(attachment.fileName)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

