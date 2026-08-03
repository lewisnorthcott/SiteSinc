import SwiftUI

// MARK: - Conduct HSE Inspection
// Mirrors the web ConductInspectionDialog: pick a template (creates a draft
// immediately), fill the header, raise observations per section, then submit.
// Works against the server when online, or against a local queued draft offline.

struct ConductHseInspectionView: View {
    enum Mode {
        case new
        case serverDraft(inspectionId: Int)
        case localDraft(draftId: String)
    }

    let projectId: Int
    let token: String
    let mode: Mode

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var offlineManager = OfflineHseInspectionManager.shared

    // Metadata
    @State private var templates: [HseAvailableTemplate] = []
    @State private var headerFields: [HseInspectionHeaderField] = []
    @State private var categories: [HseObservationCategory] = []
    @State private var users: [HseUser] = []
    @State private var locations: [ProjectLocation] = []
    @State private var isLoadingMetadata = true

    // Editing target
    @State private var revision: HseTemplateRevision?
    @State private var templateTitle: String = ""
    @State private var serverInspectionId: Int?
    @State private var serverObservations: [HseObservation] = []
    @State private var localDraftId: String?
    @State private var isCreatingDraft = false

    // Header state
    @State private var conductedAt = Date()
    @State private var accompaniedById: Int?
    @State private var keyPersonnelIds: [Int] = []
    @State private var headerAnswers: [String: String] = [:]

    // Autosave (server drafts)
    @State private var autosaveTask: Task<Void, Never>?
    @State private var autosaveState: AutosaveState = .idle
    @State private var suppressAutosave = true

    // Sheets / dialogs
    @State private var addObservationSection: HseSection?
    @State private var editServerObservation: HseObservation?
    @State private var editLocalObservation: LocalHseObservation?
    @State private var showAccompaniedPicker = false
    @State private var showKeyPersonnelPicker = false
    @State private var showDeleteConfirm = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    enum AutosaveState {
        case idle, saving, saved, error
    }

    private var isOffline: Bool { offlineManager.isOffline }
    private var hasStarted: Bool { revision != nil }
    private var localDraft: LocalHseDraft? {
        localDraftId.flatMap { offlineManager.draft(withId: $0) }
    }
    private var isLocalMode: Bool { localDraftId != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                BrandChrome.groupedBackground.ignoresSafeArea()

                if isLoadingMetadata {
                    ProgressView("Loading...")
                } else if !hasStarted {
                    templatePicker
                } else {
                    editorForm
                }
            }
            .navigationTitle(hasStarted ? templateTitle : "New \(AppBrand.current.terminology.hseInspection)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(hasStarted ? "Close" : "Cancel") { dismiss() }
                }
                if hasStarted {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete Draft", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if hasStarted { submitBar }
            }
        }
        .interactiveDismissDisabled(hasStarted)
        .task { await initialLoad() }
        .sheet(item: $addObservationSection) { section in
            observationForm(section: section, serverObservation: nil, localObservation: nil)
        }
        .sheet(item: $editServerObservation) { observation in
            if let section = sectionFor(id: observation.sectionId) {
                observationForm(section: section, serverObservation: observation, localObservation: nil)
            }
        }
        .sheet(item: $editLocalObservation) { observation in
            if let section = sectionFor(id: observation.sectionId) {
                observationForm(section: section, serverObservation: nil, localObservation: observation)
            }
        }
        .sheet(isPresented: $showAccompaniedPicker) {
            HseUserSelectSheet(users: users, allowClear: true) { user in
                accompaniedById = user?.id
                headerChanged()
            }
        }
        .sheet(isPresented: $showKeyPersonnelPicker) {
            HseUserSelectSheet(users: users, excludedIds: Set(keyPersonnelIds)) { user in
                if let user, !keyPersonnelIds.contains(user.id) {
                    keyPersonnelIds.append(user.id)
                    headerChanged()
                }
            }
        }
        .confirmationDialog("Delete this draft inspection?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Draft", role: .destructive) {
                Task { await deleteDraft() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All items raised on this draft will be removed.")
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: Template picker

    private var templatePicker: some View {
        List {
            if templates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No published templates")
                        .font(.headline)
                    Text(isOffline
                         ? "Templates were not cached before going offline. Connect once to enable offline \(AppBrand.current.terminology.hseInspections.lowercased())."
                         : "Ask an administrator to publish a \(AppBrand.current.terminology.hseInspection.lowercased()) template on the web app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(templates) { template in
                        Button {
                            Task { await startInspection(with: template) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(template.title)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if isCreatingDraft {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                if let reference = template.reference, !reference.isEmpty {
                                    Text(reference).font(.caption).foregroundColor(.secondary)
                                }
                                if let description = template.description, !description.isEmpty {
                                    Text(description).font(.caption).foregroundColor(.secondary).lineLimit(2)
                                }
                                Text("\(template.liveRevision?.sectionList.count ?? 0) sections • v\(template.liveRevision?.versionNumber ?? 1)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isCreatingDraft)
                    }
                } header: {
                    Text(isOffline ? "Select a template (offline — will sync later)" : "Select a template")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: Editor

    private var editorForm: some View {
        Form {
            headerSection

            ForEach(revision?.sectionList ?? []) { section in
                sectionCard(section)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var headerSection: some View {
        Section {
            DatePicker("Conducted at", selection: $conductedAt)
                .onChange(of: conductedAt) { _, _ in headerChanged() }

            HStack {
                Text("Accompanied by")
                Spacer()
                Button {
                    showAccompaniedPicker = true
                } label: {
                    Text(userName(for: accompaniedById) ?? "Select")
                        .foregroundColor(accompaniedById == nil ? .secondary : .primary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Key personnel")
                    Spacer()
                    Button {
                        showKeyPersonnelPicker = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption)
                    }
                }
                if !keyPersonnelIds.isEmpty {
                    FlowLayoutCompat(spacing: 6) {
                        ForEach(keyPersonnelIds, id: \.self) { userId in
                            HStack(spacing: 4) {
                                Text(userName(for: userId) ?? "User \(userId)")
                                    .font(.caption)
                                Button {
                                    keyPersonnelIds.removeAll { $0 == userId }
                                    headerChanged()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(.systemGray5)))
                        }
                    }
                }
            }

            ForEach(headerFields) { field in
                headerFieldRow(field)
            }
        } header: {
            HStack {
                Text("Inspection Details")
                Spacer()
                autosaveIndicator
            }
        } footer: {
            if headerFields.contains(where: { $0.required }) {
                Text("Fields marked * are required before submitting.")
            }
        }
    }

    @ViewBuilder
    private func headerFieldRow(_ field: HseInspectionHeaderField) -> some View {
        let label = field.required ? "\(field.label) *" : field.label
        if field.type == "dropdown", let options = field.options, !options.isEmpty {
            Picker(label, selection: Binding(
                get: { headerAnswers[String(field.id)] ?? "" },
                set: { headerAnswers[String(field.id)] = $0; headerChanged() }
            )) {
                Text("Select...").tag("")
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundColor(.secondary)
                TextField(field.label, text: Binding(
                    get: { headerAnswers[String(field.id)] ?? "" },
                    set: { headerAnswers[String(field.id)] = $0; headerChanged() }
                ))
            }
        }
    }

    private var autosaveIndicator: some View {
        Group {
            switch autosaveState {
            case .idle:
                EmptyView()
            case .saving:
                Label("Saving...", systemImage: "arrow.triangle.2.circlepath")
            case .saved:
                Label(isLocalMode ? "Saved on device" : "Saved", systemImage: "checkmark.circle")
                    .foregroundColor(.green)
            case .error:
                Label("Save failed", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
            }
        }
        .font(.caption2)
        .textCase(nil)
    }

    // MARK: Section cards

    private func sectionCard(_ section: HseSection) -> some View {
        Section {
            if let description = section.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let serverItems = serverObservations.filter { $0.sectionId == section.id }
            let localItems = localDraft?.observations.filter { $0.sectionId == section.id } ?? []

            ForEach(serverItems) { observation in
                Button {
                    editServerObservation = observation
                } label: {
                    serverObservationRow(observation)
                }
                .buttonStyle(.plain)
            }
            ForEach(localItems) { observation in
                Button {
                    editLocalObservation = observation
                } label: {
                    localObservationRow(observation)
                }
                .buttonStyle(.plain)
            }

            Button {
                addObservationSection = section
            } label: {
                Label("Add Observation", systemImage: "plus.circle")
                    .font(.subheadline)
            }
        } header: {
            Text(section.title)
        }
    }

    private func serverObservationRow(_ observation: HseObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(observation.description)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                if let category = observation.category {
                    Label(category.name, systemImage: "tag")
                }
                if let assignee = observation.assignedTo {
                    Label(assignee.displayName, systemImage: "person")
                }
                if observation.photoCount > 0 {
                    Label("\(observation.photoCount)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func localObservationRow(_ observation: LocalHseObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(observation.descriptionText)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                if let categoryId = observation.categoryId,
                   let category = categories.first(where: { $0.id == categoryId }) {
                    Label(category.name, systemImage: "tag")
                }
                if let assigneeId = observation.assignedToId {
                    Label(userName(for: assigneeId) ?? "User \(assigneeId)", systemImage: "person")
                }
                if !observation.photos.isEmpty {
                    Label("\(observation.photos.count)", systemImage: "photo")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Submit bar

    private var missingRequiredHeaderFields: [HseInspectionHeaderField] {
        headerFields.filter { field in
            field.required && (headerAnswers[String(field.id)] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var submitBar: some View {
        VStack(spacing: 8) {
            if isLocalMode {
                Label("Offline — this inspection will upload when you reconnect", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isSubmitting { ProgressView().tint(.white) }
                    Text(isLocalMode ? "Submit When Online" : "Submit Inspection")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(BrandChrome.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSubmitting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    // MARK: Helpers

    private func sectionFor(id: String) -> HseSection? {
        revision?.sectionList.first { $0.id == id }
    }

    private func userName(for userId: Int?) -> String? {
        guard let userId else { return nil }
        return users.first { $0.id == userId }?.displayName
    }

    // MARK: Observation form plumbing

    @ViewBuilder
    private func observationForm(section: HseSection, serverObservation: HseObservation?, localObservation: LocalHseObservation?) -> some View {
        let existingInput: HseObservationInput? = {
            if let obs = serverObservation {
                var input = HseObservationInput(sectionId: obs.sectionId)
                input.description = obs.description
                input.categoryId = obs.categoryId ?? obs.category?.id
                input.categoryData = (obs.categoryData ?? [:]).mapValues { $0.displayString }
                input.assignedToId = obs.assignedTo?.id
                input.dueDate = obs.dueDate
                input.locationId = obs.locationId ?? obs.location?.id
                return input
            }
            if let obs = localObservation {
                var input = HseObservationInput(sectionId: obs.sectionId)
                input.description = obs.descriptionText
                input.categoryId = obs.categoryId
                input.categoryData = obs.categoryData
                input.assignedToId = obs.assignedToId
                input.dueDate = obs.dueDate
                input.locationId = obs.locationId
                return input
            }
            return nil
        }()

        HseObservationFormView(
            sectionTitle: section.title,
            sectionId: section.id,
            observationFields: revision?.observationFieldList ?? [],
            locationsEnabled: revision?.locationsEnabled ?? false,
            categories: categories,
            users: users,
            locations: locations,
            existingInput: existingInput,
            existingServerObservation: serverObservation,
            projectId: projectId,
            token: token,
            onSave: { input, pendingPhotos in
                if isLocalMode {
                    try await saveLocalObservation(input: input, pendingPhotos: pendingPhotos, editing: localObservation)
                } else {
                    try await saveServerObservation(input: input, pendingPhotos: pendingPhotos, editing: serverObservation)
                }
            },
            onDelete: (serverObservation != nil || localObservation != nil) ? {
                if let obs = serverObservation {
                    try await deleteServerObservation(obs)
                } else if let obs = localObservation {
                    deleteLocalObservation(obs)
                }
            } : nil
        )
        .environmentObject(sessionManager)
    }

    // MARK: Initial load

    private func initialLoad() async {
        defer { isLoadingMetadata = false }
        await loadMetadata()

        switch mode {
        case .new:
            break
        case .serverDraft(let inspectionId):
            await loadServerDraft(inspectionId)
        case .localDraft(let draftId):
            loadLocalDraft(draftId)
        }
        // Enable autosave only after initial state is populated.
        try? await Task.sleep(nanoseconds: 300_000_000)
        suppressAutosave = false
    }

    private func loadMetadata() async {
        if !isOffline {
            do {
                async let templatesTask = APIClient.fetchHseAvailableTemplates(projectId: projectId, token: token)
                async let headerFieldsTask = APIClient.fetchHseHeaderFields(token: token)
                async let categoriesTask = APIClient.fetchHseCategories(token: token)
                async let usersTask = APIClient.fetchHseProjectUsers(projectId: projectId, token: token)
                async let locationsTask = APIClient.fetchProjectLocations(projectId: projectId, token: token)
                templates = try await templatesTask
                headerFields = (try await headerFieldsTask).filter { $0.active ?? true }
                categories = (try await categoriesTask).filter { $0.active ?? true }
                users = try await usersTask
                locations = try await locationsTask
                offlineManager.cacheMetadata(
                    HseProjectMetadata(templates: templates, headerFields: headerFields, categories: categories, users: users, locations: locations, cachedAt: Date()),
                    forProject: projectId
                )
                return
            } catch {
                print("ConductHseInspectionView: online metadata load failed, falling back to cache: \(error)")
            }
        }
        if let cached = offlineManager.getCachedMetadata(forProject: projectId, ignoreTTL: true) {
            templates = cached.templates
            headerFields = cached.headerFields.filter { $0.active ?? true }
            categories = cached.categories.filter { $0.active ?? true }
            users = cached.users
            locations = cached.locations
        }
    }

    private func loadServerDraft(_ inspectionId: Int) async {
        do {
            let inspection = try await APIClient.fetchHseInspection(projectId: projectId, inspectionId: inspectionId, token: token)
            applyServerInspection(inspection)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func applyServerInspection(_ inspection: HseInspection) {
        serverInspectionId = inspection.id
        revision = inspection.revision
        templateTitle = inspection.template?.title ?? AppBrand.current.terminology.hseInspection
        serverObservations = inspection.observations ?? []
        conductedAt = inspection.conductedAt ?? Date()
        accompaniedById = inspection.accompaniedBy?.id ?? inspection.accompaniedById
        keyPersonnelIds = (inspection.keyPersonnel ?? []).map { $0.userId }
        headerAnswers = inspection.headerStrings
    }

    private func loadLocalDraft(_ draftId: String) {
        guard let draft = offlineManager.draft(withId: draftId) else { return }
        localDraftId = draft.id
        revision = draft.revision
        templateTitle = draft.templateTitle
        conductedAt = draft.conductedAt
        accompaniedById = draft.accompaniedById
        keyPersonnelIds = draft.keyPersonnelIds
        headerAnswers = draft.headerData
    }

    // MARK: Start (template selection)

    private func startInspection(with template: HseAvailableTemplate) async {
        guard let liveRevision = template.liveRevision else {
            errorMessage = "Template has no published revision"
            return
        }
        isCreatingDraft = true
        defer { isCreatingDraft = false }

        if isOffline {
            let draft = LocalHseDraft(
                id: UUID().uuidString,
                projectId: projectId,
                templateId: template.id,
                templateTitle: template.title,
                templateReference: template.reference,
                revision: liveRevision,
                conductedAt: Date(),
                accompaniedById: nil,
                keyPersonnelIds: [],
                headerData: [:],
                observations: [],
                submitRequested: false,
                serverInspectionId: nil,
                createdAt: Date()
            )
            offlineManager.saveDraft(draft)
            localDraftId = draft.id
            revision = liveRevision
            templateTitle = template.title
            return
        }

        do {
            let created = try await APIClient.createHseInspection(
                projectId: projectId,
                templateId: template.id,
                status: "draft",
                conductedAt: conductedAt,
                token: token
            )
            serverInspectionId = created.id
            revision = liveRevision
            templateTitle = template.title
            serverObservations = []
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    // MARK: Autosave

    private func headerChanged() {
        guard !suppressAutosave, hasStarted else { return }

        if isLocalMode {
            persistLocalHeader()
            autosaveState = .saved
            return
        }

        autosaveTask?.cancel()
        autosaveState = .saving
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await saveServerHeader()
        }
    }

    private func persistLocalHeader() {
        guard var draft = localDraft else { return }
        draft.conductedAt = conductedAt
        draft.accompaniedById = accompaniedById
        draft.keyPersonnelIds = keyPersonnelIds
        draft.headerData = headerAnswers
        offlineManager.saveDraft(draft)
    }

    private func saveServerHeader() async {
        guard let inspectionId = serverInspectionId else { return }
        do {
            _ = try await APIClient.updateHseInspection(
                projectId: projectId,
                inspectionId: inspectionId,
                conductedAt: .some(conductedAt),
                accompaniedById: accompaniedById.map { .some($0) } ?? .some(nil),
                keyPersonnelIds: keyPersonnelIds,
                headerData: headerAnswers,
                token: token
            )
            autosaveState = .saved
        } catch {
            autosaveState = .error
            print("ConductHseInspectionView: autosave failed: \(error)")
        }
    }

    // MARK: Observations (server)

    private func saveServerObservation(input: HseObservationInput, pendingPhotos: [HsePendingPhoto], editing: HseObservation?) async throws {
        guard let inspectionId = serverInspectionId else { return }
        let observation: HseObservation
        if let editing {
            observation = try await APIClient.updateHseObservation(
                projectId: projectId,
                observationId: editing.id,
                description: input.description,
                categoryId: .some(input.categoryId),
                categoryData: input.categoryData,
                assignedToId: .some(input.assignedToId),
                dueDate: .some(input.dueDate),
                locationId: (revision?.locationsEnabled ?? false) ? .some(input.locationId) : nil,
                token: token
            )
        } else {
            observation = try await APIClient.createHseObservation(
                projectId: projectId,
                inspectionId: inspectionId,
                sectionId: input.sectionId,
                description: input.description,
                categoryId: input.categoryId,
                categoryData: input.categoryData.isEmpty ? nil : input.categoryData,
                assignedToId: input.assignedToId,
                dueDate: input.dueDate,
                locationId: input.locationId,
                token: token
            )
        }

        for photo in pendingPhotos {
            _ = try await APIClient.uploadHseObservationPhotos(
                projectId: projectId,
                observationId: observation.id,
                images: [(data: photo.data, fileName: "photo_\(photo.id).jpg")],
                photoType: .observation,
                latitude: photo.latitude,
                longitude: photo.longitude,
                accuracy: photo.accuracy,
                capturedAt: photo.capturedAt,
                token: token
            )
        }

        await refreshServerObservations()
    }

    private func deleteServerObservation(_ observation: HseObservation) async throws {
        try await APIClient.deleteHseObservation(projectId: projectId, observationId: observation.id, token: token)
        await refreshServerObservations()
    }

    private func refreshServerObservations() async {
        guard let inspectionId = serverInspectionId else { return }
        if let inspection = try? await APIClient.fetchHseInspection(projectId: projectId, inspectionId: inspectionId, token: token) {
            serverObservations = inspection.observations ?? []
        }
    }

    // MARK: Observations (local)

    private func saveLocalObservation(input: HseObservationInput, pendingPhotos: [HsePendingPhoto], editing: LocalHseObservation?) async throws {
        guard var draft = localDraft else { return }

        var savedPhotos: [LocalHsePhoto] = editing?.photos ?? []
        for photo in pendingPhotos {
            if let fileName = offlineManager.savePhotoData(photo.data, draftId: draft.id, photoId: photo.id) {
                savedPhotos.append(LocalHsePhoto(
                    id: photo.id,
                    fileName: fileName,
                    capturedAt: photo.capturedAt,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    accuracy: photo.accuracy,
                    uploaded: false
                ))
            }
        }

        if let editing, let index = draft.observations.firstIndex(where: { $0.id == editing.id }) {
            draft.observations[index].descriptionText = input.description
            draft.observations[index].categoryId = input.categoryId
            draft.observations[index].categoryData = input.categoryData
            draft.observations[index].assignedToId = input.assignedToId
            draft.observations[index].dueDate = input.dueDate
            draft.observations[index].locationId = input.locationId
            draft.observations[index].photos = savedPhotos
        } else {
            draft.observations.append(LocalHseObservation(
                id: UUID().uuidString,
                sectionId: input.sectionId,
                descriptionText: input.description,
                categoryId: input.categoryId,
                categoryData: input.categoryData,
                assignedToId: input.assignedToId,
                dueDate: input.dueDate,
                locationId: input.locationId,
                photos: savedPhotos,
                serverId: nil
            ))
        }
        offlineManager.saveDraft(draft)
    }

    private func deleteLocalObservation(_ observation: LocalHseObservation) {
        guard var draft = localDraft else { return }
        for photo in observation.photos {
            offlineManager.deletePhotoFile(draftId: draft.id, fileName: photo.fileName)
        }
        draft.observations.removeAll { $0.id == observation.id }
        offlineManager.saveDraft(draft)
    }

    // MARK: Submit / delete

    private func submit() async {
        let missing = missingRequiredHeaderFields
        guard missing.isEmpty else {
            errorMessage = "Please complete required fields: \(missing.map { $0.label }.joined(separator: ", "))"
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        if isLocalMode {
            guard var draft = localDraft else { return }
            draft.conductedAt = conductedAt
            draft.accompaniedById = accompaniedById
            draft.keyPersonnelIds = keyPersonnelIds
            draft.headerData = headerAnswers
            draft.submitRequested = true
            offlineManager.saveDraft(draft)
            offlineManager.manualSync()
            dismiss()
            return
        }

        guard let inspectionId = serverInspectionId else { return }
        do {
            autosaveTask?.cancel()
            _ = try await APIClient.updateHseInspection(
                projectId: projectId,
                inspectionId: inspectionId,
                status: "submitted",
                conductedAt: .some(conductedAt),
                accompaniedById: accompaniedById.map { .some($0) } ?? .some(nil),
                keyPersonnelIds: keyPersonnelIds,
                headerData: headerAnswers,
                token: token
            )
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func deleteDraft() async {
        if isLocalMode {
            if let draftId = localDraftId {
                offlineManager.deleteDraft(draftId)
            }
            dismiss()
            return
        }
        guard let inspectionId = serverInspectionId else {
            dismiss()
            return
        }
        do {
            try await APIClient.deleteHseInspectionDraft(projectId: projectId, inspectionId: inspectionId, token: token)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}

// MARK: - Simple flow layout for chips (iOS 16+)

struct FlowLayoutCompat: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
