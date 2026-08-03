import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Google Drive-style file browser for a project (and the tenant-wide company
/// drive). Mirrors the web app's SiteDrive page. Drills into folders by
/// pushing itself with a `folderId`.
struct SiteDriveBrowserView: View {
    let projectId: Int
    let token: String
    let projectName: String
    var folderId: Int? = nil
    var folderName: String? = nil
    /// Set when pushed into a folder so the scope can no longer change.
    var fixedScope: SiteDriveScope? = nil

    @EnvironmentObject var sessionManager: SessionManager

    @State private var scope: SiteDriveScope = .project
    @State private var capabilities: SiteDriveCapabilities?
    @State private var showCompanyTab = false
    @State private var folderTree: [SiteDriveFolder] = []
    @State private var items: [SiteDriveItem] = []
    @State private var totalItems = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var sortOption: SiteDriveSortOption = .nameAsc

    // Uploads
    @State private var showFileImporter = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadProgressText = ""
    @State private var uploadResultMessage: String?

    // Offline
    @ObservedObject private var offlineActivity = SiteDriveOfflineActivity.shared
    @State private var pinState = SiteDrivePinState()
    @State private var isShowingCachedData = false
    @State private var isPreparingFolderPin = false
    @State private var pendingFolderPin: SiteDrivePendingFolderPin?

    // Folder / item mutations
    @State private var showNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var folderBeingRenamed: SiteDriveFolder?
    @State private var itemBeingRenamed: SiteDriveItem?
    @State private var renameText = ""
    @State private var folderPendingDelete: SiteDriveFolder?
    @State private var itemPendingDelete: SiteDriveItem?
    @State private var moveTarget: SiteDriveMoveTarget?

    private var effectiveToken: String { sessionManager.token ?? token }
    private var isRoot: Bool { folderId == nil }

    private var currentSubfolders: [SiteDriveFolder] {
        if let folderId {
            return SiteDriveFolder.find(id: folderId, in: folderTree)?.subfolders ?? []
        }
        return folderTree
    }

    private var filteredFolders: [SiteDriveFolder] {
        let folders = currentSubfolders.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !searchText.isEmpty else { return folders }
        return folders.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var filteredItems: [SiteDriveItem] {
        let sorted = sortOption.sort(items)
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        content
            .navigationTitle(folderName ?? "SiteDrive")
            .navigationBarTitleDisplayMode(.inline)
            .brandPageBackground(useGrouped: true)
            .searchable(text: $searchText, prompt: "Search this folder")
            .refreshable { await loadData() }
            .task(id: scope) { await loadData() }
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .onChange(of: photoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                handlePhotoPickerSelection(newItems)
            }
            .alert("New Folder", isPresented: $showNewFolderAlert) {
                TextField("Folder name", text: $newFolderName)
                Button("Cancel", role: .cancel) { newFolderName = "" }
                Button("Create") { createFolder() }
            }
            .alert("Rename", isPresented: renameAlertBinding) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { clearRenameState() }
                Button("Rename") { performRename() }
            }
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) { folderPendingDelete = nil; itemPendingDelete = nil }
            } message: {
                if folderPendingDelete != nil {
                    Text("This deletes the folder and everything inside it.")
                }
            }
            .sheet(item: $moveTarget) { target in
                SiteDriveMoveSheet(
                    folderTree: folderTree,
                    target: target,
                    onSelect: { destinationId in performMove(target: target, destinationId: destinationId) }
                )
            }
            .alert("SiteDrive", isPresented: uploadResultBinding) {
                Button("OK", role: .cancel) { uploadResultMessage = nil }
            } message: {
                Text(uploadResultMessage ?? "")
            }
            .confirmationDialog(
                pendingFolderPin.map { "Download \"\($0.folder.name)\" for offline use?" } ?? "Download folder?",
                isPresented: folderPinConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button("Download") { confirmFolderPin() }
                Button("Cancel", role: .cancel) { pendingFolderPin = nil }
            } message: {
                if let pending = pendingFolderPin {
                    Text(pending.summary)
                }
            }
            .overlay { uploadOverlay }
            .safeAreaInset(edge: .bottom) { offlineStatusBanner }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && items.isEmpty && folderTree.isEmpty {
            ProgressView("Loading SiteDrive…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage, items.isEmpty && currentSubfolders.isEmpty {
            errorView(errorMessage)
        } else {
            listView
        }
    }

    private var listView: some View {
        List {
            if isRoot && showCompanyTab && fixedScope == nil {
                Section {
                    Picker("Drive", selection: $scope) {
                        Text(projectName).tag(SiteDriveScope.project)
                        Text("Company").tag(SiteDriveScope.company)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
            }

            if scope == .company, capabilities?.isCompanyReadOnly == true {
                Section {
                    Label("Company drive is view-only", systemImage: "eye")
                        .font(.footnote)
                        .foregroundColor(BrandChrome.mutedLabel)
                        .listRowBackground(Color.clear)
                }
            }

            if isShowingCachedData {
                Section {
                    Label("Offline — showing saved data. Only downloaded files can be opened.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundColor(BrandChrome.mutedLabel)
                        .listRowBackground(Color.clear)
                }
            }

            if !filteredFolders.isEmpty {
                Section {
                    ForEach(filteredFolders) { folder in
                        folderRow(folder)
                    }
                } header: {
                    BrandSectionLabel(title: "Folders")
                }
            }

            if !filteredItems.isEmpty {
                Section {
                    ForEach(filteredItems) { item in
                        fileRow(item)
                            .onAppear {
                                if item.id == filteredItems.last?.id { loadMoreIfNeeded() }
                            }
                    }
                    if isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    BrandSectionLabel(title: "Files")
                }
            }

            if filteredFolders.isEmpty && filteredItems.isEmpty && !isLoading {
                emptyState
            }
        }
        .listStyle(.insetGrouped)
        .brandListChrome()
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: searchText.isEmpty ? "externaldrive" : "magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundColor(BrandChrome.mutedLabel)
                Text(searchText.isEmpty ? "This folder is empty" : "No matches")
                    .font(.headline)
                if searchText.isEmpty, capabilities?.canWrite == true {
                    Text("Use the + button to upload files or create folders.")
                        .font(.subheadline)
                        .foregroundColor(BrandChrome.mutedLabel)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .listRowBackground(Color.clear)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await loadData() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandChrome.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rows

    private func folderRow(_ folder: SiteDriveFolder) -> some View {
        NavigationLink(
            destination: SiteDriveBrowserView(
                projectId: projectId,
                token: token,
                projectName: projectName,
                folderId: folder.id,
                folderName: folder.name,
                fixedScope: scope
            )
            .environmentObject(sessionManager)
        ) {
            SiteDriveFolderRow(folder: folder, isPinnedOffline: pinState.folderIds.contains(folder.id))
        }
        .contextMenu {
            if pinState.folderIds.contains(folder.id) {
                Button {
                    unpinFolder(folder)
                } label: {
                    Label("Remove Offline Copy", systemImage: "xmark.icloud")
                }
            } else {
                Button {
                    prepareFolderPin(folder)
                } label: {
                    Label("Make Available Offline", systemImage: "arrow.down.circle")
                }
            }
            if capabilities?.canManageFolders == true || capabilities?.canWrite == true {
                Button {
                    renameText = folder.name
                    folderBeingRenamed = folder
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    moveTarget = .folder(folder)
                } label: {
                    Label("Move", systemImage: "folder")
                }
            }
            if capabilities?.canDelete == true {
                Button(role: .destructive) {
                    folderPendingDelete = folder
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func fileRow(_ item: SiteDriveItem) -> some View {
        NavigationLink(
            destination: SiteDriveFilePreviewView(
                projectId: projectId,
                scope: scope,
                item: item,
                token: token
            )
            .environmentObject(sessionManager)
        ) {
            SiteDriveFileRow(item: item, isAvailableOffline: isFileAvailableOffline(item))
        }
        .contextMenu {
            if pinState.itemIds.contains(item.id) {
                Button {
                    unpinFile(item)
                } label: {
                    Label("Remove Offline Copy", systemImage: "xmark.icloud")
                }
            } else {
                Button {
                    pinFile(item)
                } label: {
                    Label("Make Available Offline", systemImage: "arrow.down.circle")
                }
            }
            if capabilities?.canWrite == true {
                Button {
                    renameText = item.name
                    itemBeingRenamed = item
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    moveTarget = .item(item)
                } label: {
                    Label("Move", systemImage: "folder")
                }
            }
            if capabilities?.canDelete == true {
                Button(role: .destructive) {
                    itemPendingDelete = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Picker("Sort by", selection: $sortOption) {
                    ForEach(SiteDriveSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
        }

        if capabilities?.canWrite == true || capabilities?.canManageFolders == true {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if capabilities?.canWrite == true {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Upload Files", systemImage: "doc.badge.plus")
                        }
                    }
                    if capabilities?.canManageFolders == true {
                        Button {
                            newFolderName = ""
                            showNewFolderAlert = true
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            if capabilities?.canWrite == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $photoPickerItems, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                    }
                }
            }
        }
    }

    // MARK: - Upload overlay

    @ViewBuilder
    private var uploadOverlay: some View {
        if isUploading {
            VStack(spacing: 12) {
                ProgressView()
                Text(uploadProgressText)
                    .font(.subheadline)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
    }

    // MARK: - Data loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        if let fixedScope { scope = fixedScope }
        pinState = SiteDriveOfflineStore.loadPinState(scope: scope, projectId: projectId)
        do {
            async let capsTask = APIClient.fetchSiteDriveCapabilities(scope: scope, projectId: projectId, token: effectiveToken)
            async let foldersTask = APIClient.fetchSiteDriveFolders(scope: scope, projectId: projectId, token: effectiveToken)
            async let itemsTask = APIClient.fetchSiteDriveItems(scope: scope, projectId: projectId, folderId: folderId, token: effectiveToken)

            let (caps, folders, page) = try await (capsTask, foldersTask, itemsTask)
            capabilities = caps
            folderTree = folders
            items = page.items
            totalItems = page.total
            isShowingCachedData = false

            SiteDriveOfflineStore.saveCapabilities(caps, scope: scope, projectId: projectId)
            SiteDriveOfflineStore.saveFolders(folders, scope: scope, projectId: projectId)
            SiteDriveOfflineStore.saveItems(page, scope: scope, projectId: projectId, folderId: folderId)

            // At root, check once whether the company drive is visible.
            if isRoot && fixedScope == nil && scope == .project && !showCompanyTab {
                if let companyCaps = try? await APIClient.fetchSiteDriveCapabilities(scope: .company, projectId: projectId, token: effectiveToken),
                   companyCaps.canView {
                    showCompanyTab = true
                }
            }

            // Keep pinned content fresh in the background (root visits only).
            if isRoot {
                let currentScope = scope
                Task.detached(priority: .utility) {
                    await SiteDriveOfflineStore.reconcile(scope: currentScope, projectId: projectId, token: effectiveToken)
                    await MainActor.run {
                        pinState = SiteDriveOfflineStore.loadPinState(scope: currentScope, projectId: projectId)
                    }
                }
            }
        } catch {
            // Offline fallback: browse from the cached metadata.
            if let cachedFolders = SiteDriveOfflineStore.loadFolders(scope: scope, projectId: projectId),
               let cachedPage = SiteDriveOfflineStore.loadItems(scope: scope, projectId: projectId, folderId: folderId) {
                capabilities = SiteDriveOfflineStore.loadCapabilities(scope: scope, projectId: projectId)
                folderTree = cachedFolders
                items = cachedPage.items
                totalItems = cachedPage.total
                isShowingCachedData = true
            } else {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func loadMoreIfNeeded() {
        guard !isLoadingMore, items.count < totalItems, searchText.isEmpty else { return }
        isLoadingMore = true
        Task {
            defer { isLoadingMore = false }
            do {
                let page = try await APIClient.fetchSiteDriveItems(
                    scope: scope,
                    projectId: projectId,
                    folderId: folderId,
                    offset: items.count,
                    token: effectiveToken
                )
                let known = Set(items.map(\.id))
                items.append(contentsOf: page.items.filter { !known.contains($0.id) })
                totalItems = page.total
                SiteDriveOfflineStore.saveItems(
                    SiteDriveItemsPage(items: items, total: totalItems),
                    scope: scope,
                    projectId: projectId,
                    folderId: folderId
                )
            } catch {
                // Silent — pull-to-refresh recovers.
                print("SiteDrive: load more failed: \(error)")
            }
        }
    }

    // MARK: - Uploads

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var pending: [(data: Data, name: String)] = []
            for url in urls {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    pending.append((data, url.lastPathComponent))
                }
            }
            uploadFiles(pending)
        case .failure(let error):
            uploadResultMessage = "Could not read the selected files: \(error.localizedDescription)"
        }
    }

    private func handlePhotoPickerSelection(_ pickerItems: [PhotosPickerItem]) {
        Task {
            var pending: [(data: Data, name: String)] = []
            let stamp = Self.photoNameFormatter.string(from: Date())
            for (index, pickerItem) in pickerItems.enumerated() {
                guard let data = try? await pickerItem.loadTransferable(type: Data.self) else { continue }
                let ext = pickerItem.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let suffix = pickerItems.count > 1 ? "_\(index + 1)" : ""
                pending.append((data, "Photo_\(stamp)\(suffix).\(ext)"))
            }
            photoPickerItems = []
            uploadFiles(pending)
        }
    }

    private func uploadFiles(_ files: [(data: Data, name: String)]) {
        guard !files.isEmpty else { return }
        isUploading = true
        Task {
            var uploaded = 0
            var newVersions = 0
            var failures: [String] = []
            for (index, file) in files.enumerated() {
                uploadProgressText = "Uploading \(index + 1) of \(files.count)…"
                do {
                    let response = try await APIClient.uploadSiteDriveFile(
                        scope: scope,
                        projectId: projectId,
                        folderId: folderId,
                        fileData: file.data,
                        fileName: file.name,
                        token: effectiveToken
                    )
                    uploaded += 1
                    if response.isNewItem == false { newVersions += 1 }
                } catch {
                    let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
                    failures.append("\(file.name): \(message)")
                }
            }
            isUploading = false

            var summary: [String] = []
            if uploaded > 0 {
                summary.append(uploaded == 1 ? "1 file uploaded." : "\(uploaded) files uploaded.")
            }
            if newVersions > 0 {
                summary.append(newVersions == 1 ? "1 existing file got a new version." : "\(newVersions) existing files got new versions.")
            }
            if !failures.isEmpty {
                summary.append("Failed:\n" + failures.joined(separator: "\n"))
            }
            uploadResultMessage = summary.joined(separator: "\n")
            await loadData()
        }
    }

    private static let photoNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()

    // MARK: - Folder / item mutations

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        Task {
            do {
                _ = try await APIClient.createSiteDriveFolder(
                    scope: scope,
                    projectId: projectId,
                    name: name,
                    parentId: folderId,
                    token: effectiveToken
                )
                await loadData()
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { folderBeingRenamed != nil || itemBeingRenamed != nil },
            set: { if !$0 { clearRenameState() } }
        )
    }

    private func clearRenameState() {
        folderBeingRenamed = nil
        itemBeingRenamed = nil
        renameText = ""
    }

    private func performRename() {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = folderBeingRenamed
        let item = itemBeingRenamed
        clearRenameState()
        guard !name.isEmpty else { return }
        Task {
            do {
                if let folder {
                    _ = try await APIClient.updateSiteDriveFolder(folderId: folder.id, name: name, token: effectiveToken)
                } else if let item {
                    _ = try await APIClient.updateSiteDriveItem(itemId: item.id, name: name, token: effectiveToken)
                }
                await loadData()
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private var deleteConfirmationTitle: String {
        if let folder = folderPendingDelete { return "Delete \"\(folder.name)\"?" }
        if let item = itemPendingDelete { return "Delete \"\(item.name)\"?" }
        return "Delete?"
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil || itemPendingDelete != nil },
            set: { if !$0 { folderPendingDelete = nil; itemPendingDelete = nil } }
        )
    }

    private func performDelete() {
        let folder = folderPendingDelete
        let item = itemPendingDelete
        folderPendingDelete = nil
        itemPendingDelete = nil
        Task {
            do {
                if let folder {
                    try await APIClient.deleteSiteDriveFolder(folderId: folder.id, token: effectiveToken)
                } else if let item {
                    try await APIClient.deleteSiteDriveItem(itemId: item.id, token: effectiveToken)
                }
                await loadData()
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func performMove(target: SiteDriveMoveTarget, destinationId: Int?) {
        moveTarget = nil
        Task {
            do {
                switch target {
                case .folder(let folder):
                    _ = try await APIClient.updateSiteDriveFolder(folderId: folder.id, parentId: .some(destinationId), token: effectiveToken)
                case .item(let item):
                    _ = try await APIClient.updateSiteDriveItem(itemId: item.id, folderId: .some(destinationId), token: effectiveToken)
                }
                await loadData()
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private var uploadResultBinding: Binding<Bool> {
        Binding(
            get: { uploadResultMessage != nil && !isUploading },
            set: { if !$0 { uploadResultMessage = nil } }
        )
    }

    // MARK: - Offline pinning

    @ViewBuilder
    private var offlineStatusBanner: some View {
        if let status = offlineActivity.statusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(status)
                    .font(.footnote)
                    .foregroundColor(BrandChrome.mutedLabel)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        } else if isPreparingFolderPin {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Calculating download size…")
                    .font(.footnote)
                    .foregroundColor(BrandChrome.mutedLabel)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func isFileAvailableOffline(_ item: SiteDriveItem) -> Bool {
        guard let revisionId = item.latestRevision?.id else { return false }
        return SiteDriveFileCache.cachedURL(scope: scope, projectId: projectId, itemName: item.name, revisionId: revisionId) != nil
    }

    private func pinFile(_ item: SiteDriveItem) {
        Task {
            await MainActor.run { offlineActivity.statusText = "Downloading \(item.name)…" }
            do {
                try await SiteDriveOfflineStore.pinItem(item, scope: scope, projectId: projectId, token: effectiveToken)
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
            await MainActor.run {
                offlineActivity.statusText = nil
                pinState = SiteDriveOfflineStore.loadPinState(scope: scope, projectId: projectId)
            }
        }
    }

    private func unpinFile(_ item: SiteDriveItem) {
        SiteDriveOfflineStore.unpinItem(itemId: item.id, scope: scope, projectId: projectId)
        pinState = SiteDriveOfflineStore.loadPinState(scope: scope, projectId: projectId)
        kickBackgroundReconcile()
    }

    private func prepareFolderPin(_ folder: SiteDriveFolder) {
        isPreparingFolderPin = true
        Task {
            defer { isPreparingFolderPin = false }
            do {
                let collected = try await SiteDriveOfflineStore.collectFolderItems(
                    folder,
                    scope: scope,
                    projectId: projectId,
                    token: effectiveToken
                )
                pendingFolderPin = SiteDrivePendingFolderPin(folder: folder, items: collected)
            } catch {
                uploadResultMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func confirmFolderPin() {
        guard let pending = pendingFolderPin else { return }
        pendingFolderPin = nil
        Task {
            let result = await SiteDriveOfflineStore.pinFolder(
                pending.folder,
                items: pending.items,
                scope: scope,
                projectId: projectId,
                token: effectiveToken
            )
            await MainActor.run {
                pinState = SiteDriveOfflineStore.loadPinState(scope: scope, projectId: projectId)
                if result.failed > 0 {
                    uploadResultMessage = "\(result.downloaded) files downloaded, \(result.failed) failed. Pull to refresh to retry."
                }
            }
        }
    }

    private func unpinFolder(_ folder: SiteDriveFolder) {
        SiteDriveOfflineStore.unpinFolder(folderId: folder.id, scope: scope, projectId: projectId)
        pinState = SiteDriveOfflineStore.loadPinState(scope: scope, projectId: projectId)
        kickBackgroundReconcile()
    }

    /// Cleans up no-longer-pinned files in the background after an unpin.
    private func kickBackgroundReconcile() {
        let currentScope = scope
        Task.detached(priority: .utility) {
            await SiteDriveOfflineStore.reconcile(scope: currentScope, projectId: projectId, token: effectiveToken)
            await MainActor.run {
                pinState = SiteDriveOfflineStore.loadPinState(scope: currentScope, projectId: projectId)
            }
        }
    }

    private var folderPinConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingFolderPin != nil },
            set: { if !$0 { pendingFolderPin = nil } }
        )
    }
}

// MARK: - Pending folder pin

struct SiteDrivePendingFolderPin {
    let folder: SiteDriveFolder
    let items: [SiteDriveItem]

    var summary: String {
        let totalBytes = items.compactMap { $0.latestRevision?.sizeBytes }.reduce(0, +)
        let size = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        let count = items.count == 1 ? "1 file" : "\(items.count) files"
        return "\(count) (\(size)) will be stored on this device and kept up to date."
    }
}

// MARK: - Sorting

enum SiteDriveSortOption: String, CaseIterable, Identifiable {
    case nameAsc, nameDesc, modifiedDesc, modifiedAsc, sizeDesc, sizeAsc, typeAsc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAsc: return "Name (A–Z)"
        case .nameDesc: return "Name (Z–A)"
        case .modifiedDesc: return "Newest first"
        case .modifiedAsc: return "Oldest first"
        case .sizeDesc: return "Largest first"
        case .sizeAsc: return "Smallest first"
        case .typeAsc: return "Type"
        }
    }

    func sort(_ items: [SiteDriveItem]) -> [SiteDriveItem] {
        switch self {
        case .nameAsc:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .modifiedDesc:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .modifiedAsc:
            return items.sorted { $0.updatedAt < $1.updatedAt }
        case .sizeDesc:
            return items.sorted { ($0.latestRevision?.sizeBytes ?? 0) > ($1.latestRevision?.sizeBytes ?? 0) }
        case .sizeAsc:
            return items.sorted { ($0.latestRevision?.sizeBytes ?? 0) < ($1.latestRevision?.sizeBytes ?? 0) }
        case .typeAsc:
            return items.sorted {
                if $0.fileExtension != $1.fileExtension { return $0.fileExtension < $1.fileExtension }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}

// MARK: - Move target

enum SiteDriveMoveTarget: Identifiable {
    case folder(SiteDriveFolder)
    case item(SiteDriveItem)

    var id: String {
        switch self {
        case .folder(let folder): return "folder-\(folder.id)"
        case .item(let item): return "item-\(item.id)"
        }
    }

    var displayName: String {
        switch self {
        case .folder(let folder): return folder.name
        case .item(let item): return item.name
        }
    }
}
