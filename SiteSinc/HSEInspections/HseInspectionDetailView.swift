import SwiftUI

// MARK: - HSE Inspection report (submitted / closed)
// Read-only view of a report: header, sections with observations, actions to
// close, create a report revision, and share the PDF.

struct HseInspectionDetailView: View {
    let projectId: Int
    let inspectionId: Int
    let token: String

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var inspection: HseInspection?
    @State private var headerFields: [HseInspectionHeaderField] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isActing = false

    @State private var showCloseConfirm = false
    @State private var showReviseConfirm = false
    @State private var reviseDraft: HseInspection?
    @State private var pdfShareItem: ShareSheetItem?
    @State private var isDownloadingPdf = false

    private var myId: Int? { sessionManager.user?.id }
    private var canManage: Bool { sessionManager.hasPermission("close_hse_observations") }
    private var canCreate: Bool { sessionManager.hasPermission("create_hse_inspections") }
    private var isInspector: Bool {
        inspection?.inspectedBy?.id == myId || inspection?.inspectedById == myId
    }

    private var allObservationsClosed: Bool {
        (inspection?.observations ?? []).allSatisfy { $0.status == .closed }
    }

    var body: some View {
        ZStack {
            BrandChrome.groupedBackground.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading report...")
            } else if let inspection {
                content(inspection)
            } else {
                Text("Inspection not found").foregroundColor(.secondary)
            }
        }
        .navigationTitle(inspection?.displayNumber ?? "\(AppBrand.current.terminology.hseInspection) Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { await load() }
        .refreshable { await load() }
        .trackPageView("/projects/\(projectId)/hse-inspections/\(inspectionId)", projectId: projectId)
        .confirmationDialog("Close this inspection?", isPresented: $showCloseConfirm, titleVisibility: .visible) {
            Button("Close Inspection") { Task { await closeInspection() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All observations are closed. This marks the report as complete.")
        }
        .confirmationDialog("Create a new report revision?", isPresented: $showReviseConfirm, titleVisibility: .visible) {
            Button("Create Revision") { Task { await createRevision() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new draft version of this report will be created for re-inspection.")
        }
        .fullScreenCover(item: $reviseDraft, onDismiss: { Task { await load() } }) { draft in
            ConductHseInspectionView(
                projectId: projectId,
                token: token,
                mode: .serverDraft(inspectionId: draft.id)
            )
            .environmentObject(sessionManager)
        }
        .sheet(item: $pdfShareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let errorMessage { Text(errorMessage) }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if let inspection {
                Menu {
                    Button {
                        Task { await downloadPdf() }
                    } label: {
                        Label(isDownloadingPdf ? "Preparing PDF..." : "Share PDF Report", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isDownloadingPdf)

                    if inspection.status == .submitted, canCreate, isInspector || canManage {
                        Button {
                            showReviseConfirm = true
                        } label: {
                            Label("New Report Revision", systemImage: "doc.badge.plus")
                        }
                    }

                    if inspection.status == .submitted, allObservationsClosed, isInspector || canManage {
                        Button {
                            showCloseConfirm = true
                        } label: {
                            Label("Close Inspection", systemImage: "checkmark.seal")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(BrandChrome.accent)
                }
            }
        }
    }

    // MARK: Content

    private func content(_ inspection: HseInspection) -> some View {
        List {
            // Status / summary
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HseInspectionStatusBadge(status: inspection.status)
                        if let version = inspection.reportVersion, version > 1 {
                            Text("Revision \(version)")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        if let counts = inspection.observationCounts ?? computedCounts(inspection) {
                            Text("\(counts.closed)/\(counts.total) closed")
                                .font(.caption)
                                .foregroundColor(counts.openTotal > 0 ? .orange : .green)
                        }
                    }
                    Text(inspection.template?.title ?? AppBrand.current.terminology.hseInspection)
                        .font(.headline)
                    if let reference = inspection.template?.reference, !reference.isEmpty {
                        Text(reference).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Header details
            Section("Inspection Details") {
                if let inspector = inspection.inspectedBy {
                    detailRow("Inspected by", inspector.displayName)
                }
                if let conducted = inspection.conductedAt {
                    detailRow("Conducted", conducted.formatted(date: .abbreviated, time: .shortened))
                }
                if let submitted = inspection.submittedAt {
                    detailRow("Submitted", submitted.formatted(date: .abbreviated, time: .shortened))
                }
                if let closed = inspection.closedAt {
                    detailRow("Closed", closed.formatted(date: .abbreviated, time: .shortened))
                }
                if let accompanied = inspection.accompaniedBy {
                    detailRow("Accompanied by", accompanied.displayName)
                }
                if let personnel = inspection.keyPersonnel, !personnel.isEmpty {
                    detailRow("Key personnel", personnel.compactMap { $0.user?.displayName }.joined(separator: ", "))
                }
                if let location = inspection.location {
                    detailRow("Location", location.name)
                }
                ForEach(headerAnswers(inspection), id: \.0) { label, value in
                    detailRow(label, value)
                }
            }

            // Sections with observations
            let sections = inspection.revision?.sectionList ?? []
            let observations = inspection.observations ?? []
            ForEach(sections) { section in
                let items = observations.filter { $0.sectionId == section.id }
                Section {
                    if let description = section.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundColor(.secondary)
                    }
                    if items.isEmpty {
                        Label("No observations", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        ForEach(items) { observation in
                            NavigationLink {
                                HseObservationDetailView(projectId: projectId, observationId: observation.id, token: token)
                                    .environmentObject(sessionManager)
                            } label: {
                                observationRow(observation)
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                }
            }

            // Observations raised against removed/unknown sections
            let knownSectionIds = Set(sections.map { $0.id })
            let orphaned = observations.filter { !knownSectionIds.contains($0.sectionId) }
            if !orphaned.isEmpty {
                Section("Other Observations") {
                    ForEach(orphaned) { observation in
                        NavigationLink {
                            HseObservationDetailView(projectId: projectId, observationId: observation.id, token: token)
                                .environmentObject(sessionManager)
                        } label: {
                            observationRow(observation)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func observationRow(_ observation: HseObservation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(observation.description)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                HseObservationStatusBadge(status: observation.status)
            }
            HStack(spacing: 10) {
                if let category = observation.category {
                    Label(category.name, systemImage: "tag")
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
        .padding(.vertical, 2)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func computedCounts(_ inspection: HseInspection) -> HseObservationCounts? {
        guard let observations = inspection.observations else { return nil }
        return HseObservationCounts(
            OPEN: observations.filter { $0.status == .open }.count,
            IN_PROGRESS: observations.filter { $0.status == .inProgress }.count,
            PENDING_APPROVAL: observations.filter { $0.status == .pendingApproval }.count,
            CLOSED: observations.filter { $0.status == .closed }.count
        )
    }

    private func headerAnswers(_ inspection: HseInspection) -> [(String, String)] {
        let answers = inspection.headerStrings
        guard !answers.isEmpty else { return [] }
        // Map configured field ids to labels; fall back to raw keys for
        // fields that have since been deleted.
        var result: [(String, String)] = []
        for field in headerFields {
            if let value = answers[String(field.id)], !value.isEmpty {
                result.append((field.label, value))
            }
        }
        let knownIds = Set(headerFields.map { String($0.id) })
        for (key, value) in answers where !knownIds.contains(key) {
            result.append(("Field \(key)", value))
        }
        return result
    }

    // MARK: Networking

    private func load() async {
        do {
            async let inspectionTask = APIClient.fetchHseInspection(projectId: projectId, inspectionId: inspectionId, token: token)
            inspection = try await inspectionTask
            if headerFields.isEmpty {
                headerFields = (try? await APIClient.fetchHseHeaderFields(token: token)) ?? []
            }
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isLoading = false
    }

    private func closeInspection() async {
        isActing = true
        defer { isActing = false }
        do {
            _ = try await APIClient.closeHseInspection(projectId: projectId, inspectionId: inspectionId, token: token)
            await load()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func createRevision() async {
        isActing = true
        defer { isActing = false }
        do {
            let draft = try await APIClient.createHseReportRevision(projectId: projectId, inspectionId: inspectionId, token: token)
            reviseDraft = draft
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func downloadPdf() async {
        isDownloadingPdf = true
        defer { isDownloadingPdf = false }
        do {
            let data = try await APIClient.downloadHseInspectionPdf(projectId: projectId, inspectionId: inspectionId, token: token)
            let brandPrefix = AppBrand.current.terminology.hseInspection.components(separatedBy: " ").first ?? "HSE"
            let fileName = "\(brandPrefix)_\(inspection?.displayNumber.replacingOccurrences(of: " ", with: "_") ?? "Report")_\(inspectionId).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            pdfShareItem = ShareSheetItem(url: url)
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }
}
