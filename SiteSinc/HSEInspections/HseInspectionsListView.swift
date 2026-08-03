import SwiftUI

// MARK: - HSE Inspections (project entry point)
// Two tabs: Reports (inspections) and Observations (close-out register),
// mirroring apps/frontend/src/app/projects/[id]/hse-inspections/page.tsx.

struct HseInspectionsListView: View {
    let projectId: Int
    let token: String
    let projectName: String

    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var offlineManager = OfflineHseInspectionManager.shared

    @State private var selectedTab: Tab = .reports
    @State private var inspections: [HseInspection] = []
    @State private var observations: [HseObservation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isUsingCachedData = false
    @State private var cacheAge: Date?

    @State private var observationStatusFilter: HseObservationStatus?
    @State private var assignedToMeOnly = false

    @State private var showConduct = false
    @State private var continueLocalDraftId: String?
    @State private var continueServerDraft: HseInspection?

    // Bumped after conduct/detail flows change data so lists refetch.
    @State private var reloadKey = 0

    enum Tab: String, CaseIterable, Identifiable {
        case reports = "Reports"
        case observations = "Observations"
        var id: String { rawValue }
    }

    private var effectiveToken: String { sessionManager.token ?? token }

    private var canCreate: Bool { sessionManager.hasPermission("create_hse_inspections") }

    var body: some View {
        ZStack {
            BrandChrome.groupedBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                if offlineManager.isOffline || isUsingCachedData {
                    offlineBanner
                }
                if pendingDraftsForProject.count > 0 && !offlineManager.isOffline {
                    pendingSyncBanner
                }

                Picker("View", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if isLoading && inspections.isEmpty && observations.isEmpty {
                    Spacer()
                    ProgressView("Loading \(AppBrand.current.terminology.hseInspections.lowercased())...")
                    Spacer()
                } else {
                    content
                }
            }
        }
        .navigationTitle(AppBrand.current.terminology.hseInspections)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: selectedTab == .reports ? "Search reports..." : "Search observations...")
        .toolbar { toolbarContent }
        .refreshable { await loadData(forceNetwork: true) }
        .task(id: reloadKey) { await loadData() }
        .onAppear {
            AnalyticsManager.shared.trackScreenView("HSE Inspections", projectId: projectId)
        }
        .trackPageView("/projects/\(projectId)/hse-inspections", projectId: projectId)
        .fullScreenCover(isPresented: $showConduct, onDismiss: { reloadKey += 1 }) {
            ConductHseInspectionView(
                projectId: projectId,
                token: effectiveToken,
                mode: .new
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: $continueServerDraft, onDismiss: { reloadKey += 1 }) { draft in
            ConductHseInspectionView(
                projectId: projectId,
                token: effectiveToken,
                mode: .serverDraft(inspectionId: draft.id)
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: localDraftBinding, onDismiss: { reloadKey += 1 }) { wrapper in
            ConductHseInspectionView(
                projectId: projectId,
                token: effectiveToken,
                mode: .localDraft(draftId: wrapper.id)
            )
            .environmentObject(sessionManager)
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // Wrapper so a String draft id can drive fullScreenCover(item:).
    private struct DraftIdWrapper: Identifiable {
        let id: String
    }

    private var localDraftBinding: Binding<DraftIdWrapper?> {
        Binding(
            get: { continueLocalDraftId.map { DraftIdWrapper(id: $0) } },
            set: { continueLocalDraftId = $0?.id }
        )
    }

    private var pendingDraftsForProject: [LocalHseDraft] {
        offlineManager.pendingDrafts.filter { $0.projectId == projectId }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if selectedTab == .observations {
                Menu {
                    Picker("Status", selection: $observationStatusFilter) {
                        Text("All Statuses").tag(HseObservationStatus?.none)
                        ForEach(HseObservationStatus.allCases) { status in
                            Text(status.label).tag(HseObservationStatus?.some(status))
                        }
                    }
                    Toggle("Assigned to Me", isOn: $assignedToMeOnly)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(BrandChrome.accent)
                }
            }
            if canCreate {
                Button {
                    showConduct = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(BrandChrome.accent)
                }
            }
        }
    }

    // MARK: Banners

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: offlineManager.isOffline ? "wifi.slash" : "clock")
                .font(.caption)
            if offlineManager.isOffline {
                Text("Offline Mode").font(.caption).fontWeight(.medium)
            }
            if isUsingCachedData, let age = cacheAge {
                Text("Showing cached data from \(age.formatted(.relative(presentation: .named)))")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(offlineManager.isOffline ? Color.orange : Color.blue)
    }

    private var pendingSyncBanner: some View {
        HStack(spacing: 8) {
            if offlineManager.syncInProgress {
                ProgressView().scaleEffect(0.7)
                Text("Syncing offline inspections...").font(.caption)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                Text("\(pendingDraftsForProject.count) inspection(s) waiting to sync").font(.caption)
                Spacer()
                Button("Sync Now") { offlineManager.manualSync() }
                    .font(.caption)
                    .fontWeight(.medium)
            }
            if !offlineManager.syncInProgress { EmptyView() } else { Spacer() }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.purple)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .reports: reportsList
        case .observations: observationsList
        }
    }

    private var filteredInspections: [HseInspection] {
        guard !searchText.isEmpty else { return inspections }
        return inspections.filter { inspection in
            inspection.displayNumber.localizedCaseInsensitiveContains(searchText) ||
            (inspection.template?.title.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (inspection.inspectedBy?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var reportsList: some View {
        List {
            if !pendingDraftsForProject.isEmpty {
                Section("Waiting to Sync") {
                    ForEach(pendingDraftsForProject) { draft in
                        Button {
                            continueLocalDraftId = draft.id
                        } label: {
                            localDraftRow(draft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if filteredInspections.isEmpty && pendingDraftsForProject.isEmpty {
                emptyState(
                    icon: "shield.checkered",
                    title: "No \(AppBrand.current.terminology.hseInspections.lowercased()) yet",
                    message: canCreate ? "Tap + to conduct your first inspection." : "Inspections conducted on this project will appear here."
                )
            } else {
                Section {
                    ForEach(filteredInspections) { inspection in
                        if inspection.status == .draft, canCreate, inspection.inspectedById == sessionManager.user?.id || inspection.inspectedBy?.id == sessionManager.user?.id {
                            Button {
                                continueServerDraft = inspection
                            } label: {
                                inspectionRow(inspection)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                HseInspectionDetailView(projectId: projectId, inspectionId: inspection.id, token: effectiveToken)
                                    .environmentObject(sessionManager)
                            } label: {
                                inspectionRow(inspection)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func localDraftRow(_ draft: LocalHseDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(draft.templateTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Label(draft.submitRequested ? "Queued (submit)" : "Queued (draft)", systemImage: "clock.arrow.circlepath")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            HStack(spacing: 12) {
                Label(draft.conductedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label("\(draft.observations.count) item(s)", systemImage: "exclamationmark.bubble")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func inspectionRow(_ inspection: HseInspection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(inspection.displayNumber)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                HseInspectionStatusBadge(status: inspection.status)
            }
            Text(inspection.template?.title ?? AppBrand.current.terminology.hseInspection)
                .font(.caption)
                .foregroundColor(.primary)
            HStack(spacing: 12) {
                if let inspector = inspection.inspectedBy {
                    Label(inspector.displayName, systemImage: "person")
                }
                if let date = inspection.conductedAt ?? inspection.submittedAt {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
                if let counts = inspection.observationCounts, counts.total > 0 {
                    Label("\(counts.closed)/\(counts.total) closed", systemImage: "checkmark.circle")
                        .foregroundColor(counts.openTotal > 0 ? .orange : .green)
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var filteredObservations: [HseObservation] {
        var result = observations
        if let filter = observationStatusFilter {
            result = result.filter { $0.status == filter }
        }
        if assignedToMeOnly, let myId = sessionManager.user?.id {
            result = result.filter { $0.assignedTo?.id == myId }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                ($0.inspection?.inspectionNumber?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.assignedTo?.displayName.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return result
    }

    private var observationsList: some View {
        List {
            if filteredObservations.isEmpty {
                emptyState(
                    icon: "exclamationmark.bubble",
                    title: "No observations",
                    message: "Observations raised during \(AppBrand.current.terminology.hseInspections.lowercased()) appear here for close-out."
                )
            } else {
                ForEach(filteredObservations) { observation in
                    NavigationLink {
                        HseObservationDetailView(projectId: projectId, observationId: observation.id, token: effectiveToken)
                            .environmentObject(sessionManager)
                    } label: {
                        observationRow(observation)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func observationRow(_ observation: HseObservation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(observation.description)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                HseObservationStatusBadge(status: observation.status)
            }
            HStack(spacing: 12) {
                if let number = observation.inspection?.inspectionNumber {
                    Label(number, systemImage: "doc.text")
                }
                if let assignee = observation.assignedTo {
                    Label(assignee.displayName, systemImage: "person")
                }
                if let due = observation.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .foregroundColor(observation.isOverdue ? .red : .secondary)
                }
                if observation.photoCount > 0 {
                    Label("\(observation.photoCount)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowBackground(Color.clear)
    }

    // MARK: Data loading

    private func loadData(forceNetwork: Bool = false) async {
        if inspections.isEmpty && observations.isEmpty { isLoading = true }
        defer { isLoading = false }

        if offlineManager.isOffline && !forceNetwork {
            loadFromCache()
            return
        }

        do {
            async let inspectionsTask = APIClient.fetchHseInspections(projectId: projectId, token: effectiveToken)
            async let observationsTask = APIClient.fetchHseObservations(projectId: projectId, token: effectiveToken)
            let (fetchedInspections, fetchedObservations) = try await (inspectionsTask, observationsTask)
            inspections = fetchedInspections
            observations = fetchedObservations
            isUsingCachedData = false
            cacheAge = nil
            offlineManager.cacheInspections(fetchedInspections, forProject: projectId)
            offlineManager.cacheObservations(fetchedObservations, forProject: projectId)
            await refreshMetadataCache()
        } catch APIError.tokenExpired {
            errorMessage = APIError.tokenExpired.displayMessage
        } catch {
            // Network failure — fall back to cache so site users can keep working.
            loadFromCache()
            if inspections.isEmpty && observations.isEmpty {
                errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
            }
        }
    }

    private func loadFromCache() {
        if let cached = offlineManager.getCachedInspections(forProject: projectId) {
            inspections = cached.inspections
            cacheAge = cached.cachedAt
            isUsingCachedData = true
        }
        if let cached = offlineManager.getCachedObservations(forProject: projectId) {
            observations = cached.observations
            cacheAge = cached.cachedAt
            isUsingCachedData = true
        }
    }

    /// Keeps the offline conduct metadata (templates, header fields,
    /// categories, users, locations) fresh whenever the list is viewed online.
    private func refreshMetadataCache() async {
        guard sessionManager.hasPermission("create_hse_inspections") else { return }
        do {
            async let templates = APIClient.fetchHseAvailableTemplates(projectId: projectId, token: effectiveToken)
            async let headerFields = APIClient.fetchHseHeaderFields(token: effectiveToken)
            async let categories = APIClient.fetchHseCategories(token: effectiveToken)
            async let users = APIClient.fetchHseProjectUsers(projectId: projectId, token: effectiveToken)
            async let locations = APIClient.fetchProjectLocations(projectId: projectId, token: effectiveToken)
            let metadata = HseProjectMetadata(
                templates: try await templates,
                headerFields: try await headerFields,
                categories: try await categories,
                users: try await users,
                locations: try await locations,
                cachedAt: Date()
            )
            offlineManager.cacheMetadata(metadata, forProject: projectId)
        } catch {
            print("HseInspectionsListView: metadata cache refresh failed: \(error)")
        }
    }
}
