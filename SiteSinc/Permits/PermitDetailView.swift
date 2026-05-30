import SwiftUI

// MARK: - Form value → display / attachments

private func permitFileKeys(from value: JSONPrimitive) -> [String] {
    switch value {
    case .string(let s):
        return s.isEmpty ? [] : [s]
    case .array(let arr):
        return arr.flatMap { permitFileKeys(from: $0) }
    case .object(let dict):
        var keys: [String] = []
        if let img = dict["image"], case .string(let s) = img, !s.isEmpty { keys.append(s) }
        if let fk = dict["fileKey"], case .string(let s) = fk, !s.isEmpty { keys.append(s) }
        for (_, v) in dict {
            if case .object = v { keys.append(contentsOf: permitFileKeys(from: v)) }
            if case .array = v { keys.append(contentsOf: permitFileKeys(from: v)) }
        }
        return Array(Set(keys))
    default:
        return []
    }
}

private func isImageLikeKey(_ key: String, fieldType: String) -> Bool {
    if ["camera", "image", "signature"].contains(fieldType) {
        if key.range(of: #"\.(pdf|doc|xls|txt|csv)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }
    return key.range(of: #"\.(jpg|jpeg|png|gif|webp|bmp)(\?|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
        || key.contains("image%2F")
}

private func displayString(from value: JSONPrimitive, fieldType: String) -> String {
    switch value {
    case .null:
        return ""
    case .string(let s):
        if fieldType == "yesNoNA" {
            let labels: [String: String] = ["yes": "Yes", "no": "No", "na": "N/A"]
            return labels[s.lowercased()] ?? s
        }
        return s
    case .bool(let b):
        return b ? "Yes" : "No"
    case .number(let n):
        if n.rounded() == n { return String(Int(n)) }
        return String(n)
    case .array(let arr):
        if fieldType == "checkbox" {
            return arr.compactMap {
                if case .string(let s) = $0 { return s }
                if case .number(let n) = $0 { return String(Int(n)) }
                return nil
            }.joined(separator: ", ")
        }
        return arr.map { displayString(from: $0, fieldType: fieldType) }.joined(separator: ", ")
    case .object(let dict):
        if ["image", "camera", "attachment", "signature"].contains(fieldType) {
            return ""
        }
        if fieldType == "yesNoNA" {
            if case .string(let v) = dict["value"] ?? .null {
                let labels: [String: String] = ["yes": "Yes", "no": "No", "na": "N/A"]
                return labels[v.lowercased()] ?? v
            }
        }
        return dict.map { "\($0.key): \(displayString(from: $0.value, fieldType: fieldType))" }.joined(separator: ", ")
    }
}

// MARK: - Detail

struct PermitDetailView: View {
    let permitId: Int
    let projectId: Int
    let token: String
    /// Shallow row from list — used for title fallback while loading.
    let summaryPermit: Permit?

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var detail: PermitDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?

    @State private var showReviewSheet = false
    @State private var reviewIsCloseout = false

    @State private var showActivateSheet = false
    @State private var showDeleteConfirm = false
    @State private var moderationSheet: ModerationKind?

    @State private var notesDraft = ""

    private enum ModerationKind: Identifiable, Equatable {
        case suspend, reinstate
        var id: String { self == .suspend ? "suspend" : "reinstate" }
    }
    @State private var closeoutFormPack: CloseoutFormPack?

    @State private var rejectedFormFlow: RejectedPermitFormFlow?

    struct CloseoutFormPack: Identifiable {
        let id = UUID()
        let form: FormModel
        let permitId: Int
    }

    struct RejectedPermitFormFlow: Identifiable {
        let id = UUID()
        let permit: Permit
        let formTemplateId: Int
    }

    var body: some View {
        Group {
            if isLoading && detail == nil {
                ProgressView("Loading permit…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, detail == nil {
                VStack(spacing: 16) {
                    Text(err)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let d = detail {
                detailContent(d)
            }
        }
        .navigationTitle(summaryPermit?.permitNumber ?? detail?.permitNumber ?? "Permit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { await load() }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .sheet(isPresented: $showReviewSheet) {
            if let d = detail {
                PermitReviewSheet(
                    permitNumber: d.permitNumber,
                    isCloseout: reviewIsCloseout,
                    onSubmit: { decision, comments, validUntil in
                        showReviewSheet = false
                        Task { await runReview(detail: d, decision: decision, comments: comments, validUntil: validUntil) }
                    },
                    onCancel: { showReviewSheet = false }
                )
            }
        }
        .sheet(isPresented: $showActivateSheet) {
            if let d = detail {
                PermitActivateSheet(
                    permitNumber: d.permitNumber,
                    defaultActiveDays: d.permitType?.defaultActiveDurationDays,
                    onActivate: { validUntil in
                        showActivateSheet = false
                        Task { await runActivate(validUntil: validUntil) }
                    },
                    onCancel: { showActivateSheet = false }
                )
            }
        }
        .confirmationDialog("Delete this draft permit?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await runDelete() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $moderationSheet) { kind in
            NavigationView {
                Form {
                    Section {
                        TextField("Notes (optional)", text: $notesDraft)
                    }
                    Section {
                        if kind == .suspend {
                            Button("Suspend permit", role: .destructive) {
                                moderationSheet = nil
                                Task { await runSuspend() }
                            }
                        } else {
                            Button("Reinstate permit") {
                                moderationSheet = nil
                                Task { await runReinstate() }
                            }
                        }
                    }
                }
                .navigationTitle(kind == .suspend ? "Suspend" : "Reinstate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { moderationSheet = nil }
                    }
                }
            }
        }
        .fullScreenCover(item: $closeoutFormPack) { pack in
                FormSubmissionCreateView(
                form: pack.form,
                projectId: projectId,
                token: sessionManager.token ?? token,
                permitId: nil,
                permitCloseoutSubmitId: pack.permitId,
                navigationTitleOverride: "Close-out",
                onSave: {
                    closeoutFormPack = nil
                    Task { await load() }
                }
            )
            .environmentObject(sessionManager)
        }
        .fullScreenCover(item: $rejectedFormFlow) { flow in
            PermitFormView(
                permit: flow.permit,
                formTemplateId: flow.formTemplateId,
                projectId: projectId,
                token: sessionManager.token ?? token,
                onDone: {
                    rejectedFormFlow = nil
                    Task { await load() }
                }
            )
            .environmentObject(sessionManager)
        }
    }

    @ViewBuilder
    private func detailContent(_ d: PermitDetail) -> some View {
        VStack(spacing: 0) {
            List {
                summarySection(d)
                if let fields = mainFormFields(d), !fields.isEmpty, let data = d.formSubmission?.data {
                    Section("Permit form") {
                        ForEach(fields) { field in
                            formFieldRow(field: field, data: data)
                        }
                    }
                }
                approvalSection(d)
                closeoutProgressSection(d)
                closeoutSubmissionSection(d)
                historySection(d)
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }

            actionBar(d)
        }
    }

    private func summarySection(_ d: PermitDetail) -> some View {
        Section {
            LabeledContent("Status", value: statusLabel(d.status))
            LabeledContent("Type", value: d.permitType?.name ?? "—")
            if let email = d.submittedBy?.email {
                LabeledContent("Submitted by", value: email)
            }
            if let loc = d.location {
                let locLine = [loc.name, loc.code].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !locLine.isEmpty {
                    LabeledContent("Location", value: locLine)
                }
            }
            if let w = d.worksDate {
                LabeledContent("Works date", value: formatShortDate(w))
            }
            if let du = d.dueDate {
                LabeledContent("Due", value: formatShortDate(du))
            }
            if let c = d.createdAt {
                LabeledContent("Created", value: formatDateTime(c))
            }
            if let s = d.submittedAt {
                LabeledContent("Submitted", value: formatDateTime(s))
            }
            if let a = d.approvedAt {
                LabeledContent("Approved", value: formatDateTime(a))
            }
            if let v = d.validUntil {
                LabeledContent("Valid until", value: formatDateTime(v))
            }
            if let cl = d.closedAt {
                LabeledContent("Closed", value: formatDateTime(cl))
            }
        } header: {
            HStack {
                Text(d.permitNumber)
                    .font(.headline)
                Spacer()
                permitStatusBadge(d.status)
            }
        }
    }

    private func mainFormFields(_ d: PermitDetail) -> [PermitDetailFormField]? {
        let rev = d.permitType?.formTemplate?.revisions?.first
        guard let raw = rev?.formFields, !raw.isEmpty else { return nil }
        return raw
            .filter { ($0.parentFieldId ?? "").isEmpty }
            .sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    @ViewBuilder
    private func formFieldRow(field: PermitDetailFormField, data: [String: JSONPrimitive]) -> some View {
        let value = data[field.id] ?? .null
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label ?? field.id)
                .font(.caption)
                .foregroundColor(.secondary)
            if ["image", "camera", "attachment", "signature"].contains(field.type) {
                PermitFormAttachmentBlock(fieldType: field.type, value: value, token: sessionManager.token ?? token)
            } else if field.type == "subheading" {
                Text(field.label ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
            } else {
                let text = displayString(from: value, fieldType: field.type)
                Text(text.isEmpty ? "—" : text)
                    .font(.body)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private func approvalSection(_ d: PermitDetail) -> some View {
        let stages = (d.permitType?.approvalStages ?? []).filter { !($0.isCloseoutStage ?? false) }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard !stages.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(Section("Approvals") {
            ForEach(stages) { stage in
                stageBlock(d: d, stage: stage, approvals: d.approvals ?? [])
            }
        })
    }

    private func stageBlock(d: PermitDetail, stage: PermitDetailApprovalStage, approvals: [PermitDetailApproval]) -> some View {
        let stageApprovals = approvals.filter { $0.stageId == stage.id }
        let isCurrent = d.currentStageId == stage.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: stageApprovals.contains { $0.decision == "approved" || $0.decision == "approved_with_comments" } ? "checkmark.circle.fill" : "clock")
                    .foregroundColor(isCurrent ? .blue : .secondary)
                Text(stage.name)
                    .font(.subheadline.weight(.semibold))
                if isCurrent {
                    Text("Current")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            ForEach(stageApprovals) { ap in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(ap.reviewer?.email ?? "Reviewer")
                            .font(.caption)
                        Spacer()
                        Text(ap.decision?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Pending")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let c = ap.comments, !c.isEmpty {
                        Text("“\(c)”")
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func closeoutProgressSection(_ d: PermitDetail) -> some View {
        guard d.permitType?.requiresCloseout == true else { return AnyView(EmptyView()) }
        let stages = (d.permitType?.approvalStages ?? []).filter { $0.isCloseoutStage == true }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        guard !stages.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(Section("Close-out progress") {
            ForEach(stages) { stage in
                stageBlock(d: d, stage: stage, approvals: d.approvals ?? [])
            }
        })
    }

    private func closeoutSubmissionSection(_ d: PermitDetail) -> some View {
        let hasSubmission = d.closeoutFormSubmission != nil
        let hasLegacy = d.closeoutData.map { !$0.isEmpty } ?? false
        guard hasSubmission || hasLegacy else { return AnyView(EmptyView()) }

        let fields = closeoutDisplayFields(d)
        let data = mergedCloseoutData(d)

        return AnyView(Section("Closeout submission") {
            if let sub = d.closeoutFormSubmission {
                if let email = sub.submittedBy?.email {
                    LabeledContent("Submitted by", value: email)
                }
                if let dt = sub.createdAt {
                    LabeledContent("Submitted at", value: formatDateTime(dt))
                }
            }
            ForEach(fields) { field in
                let val = data[field.id] ?? .null
                formFieldRow(field: field, data: data)
            }
            if let cd = d.closeoutData, let photo = cd["closeoutPhoto"], d.closeoutFormSubmission?.data == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Closeout photo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    PermitFormAttachmentBlock(fieldType: "image", value: photo, token: sessionManager.token ?? token)
                }
            }
        })
    }

    private func mergedCloseoutData(_ d: PermitDetail) -> [String: JSONPrimitive] {
        var m = d.closeoutFormSubmission?.data ?? [:]
        if let extra = d.closeoutData {
            for (k, v) in extra where m[k] == nil { m[k] = v }
        }
        return m
    }

    private func closeoutDisplayFields(_ d: PermitDetail) -> [PermitDetailFormField] {
        let rev = d.permitType?.closeoutFormTemplate?.revisions?.first
        if let ff = rev?.formFields, !ff.isEmpty {
            return ff.filter { ($0.parentFieldId ?? "").isEmpty }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        }
        if let cf = d.permitType?.closeoutFields, !cf.isEmpty {
            return cf.filter { ($0.parentFieldId ?? "").isEmpty }.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        }
        return []
    }

    private func historySection(_ d: PermitDetail) -> some View {
        let h = d.history ?? []
        guard !h.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(Section("History") {
            ForEach(h) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.action.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.medium))
                    if let n = entry.notes, !n.isEmpty {
                        Text(n).font(.caption).foregroundColor(.secondary)
                    }
                    Text("\(entry.transitionedBy?.email ?? "—") · \(formatDateTime(entry.transitionedAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        })
    }

    @ViewBuilder
    private func actionBar(_ d: PermitDetail) -> some View {
        let status = d.status.uppercased()
        let approvalStages = (d.permitType?.approvalStages ?? []).filter { !($0.isCloseoutStage ?? false) }
        let owner = isOwner(d)

        VStack(spacing: 8) {
            if let err = actionError {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if (status == "DRAFT" || status == "REJECTED"), approvalStages.isEmpty && owner {
                        Text("No approval stages — submitting will approve immediately.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if status == "DRAFT", owner {
                        Button {
                            Task { await runSubmit(d) }
                        } label: {
                            Label(approvalStages.isEmpty ? "Approve" : "Submit", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }
                    if status == "REJECTED", owner {
                        if let tid = d.permitType?.formTemplate?.id {
                            Button {
                                rejectedFormFlow = RejectedPermitFormFlow(permit: Permit(from: d), formTemplateId: tid)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                        }
                        Button {
                            Task { await runSubmit(d) }
                        } label: {
                            Label(approvalStages.isEmpty ? "Approve" : "Resubmit", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if status == "UNDER_REVIEW", canReview {
                        Button {
                            reviewIsCloseout = false
                            showReviewSheet = true
                        } label: {
                            Label("Review", systemImage: "clipboard.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if status == "APPROVED", canManage {
                        Button {
                            showActivateSheet = true
                        } label: {
                            Label("Activate", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if status == "ACTIVE", d.permitType?.requiresCloseout == true {
                        Button {
                            Task { await openCloseoutForm(d) }
                        } label: {
                            Label("Close out", systemImage: "checklist")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if status == "ACTIVE", canManage {
                        Button {
                            notesDraft = ""
                            moderationSheet = .suspend
                        } label: {
                            Label("Suspend", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                    if status == "SUSPENDED", canManage {
                        Button {
                            notesDraft = ""
                            moderationSheet = .reinstate
                        } label: {
                            Label("Reinstate", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if status == "CLOSEOUT_REVIEW", canReview {
                        Button {
                            reviewIsCloseout = true
                            showReviewSheet = true
                        } label: {
                            Label("Review closeout", systemImage: "clipboard.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)
        }
    }

    private func permitStatusBadge(_ status: String) -> some View {
        let s = status.uppercased()
        let (bg, fg): (Color, Color) = {
            switch s {
            case "DRAFT": return (Color.gray.opacity(0.2), .primary)
            case "UNDER_REVIEW", "CLOSEOUT_REVIEW": return (Color.orange.opacity(0.2), .orange)
            case "APPROVED", "ACTIVE": return (Color.green.opacity(0.2), .green)
            case "REJECTED": return (Color.red.opacity(0.2), .red)
            case "SUSPENDED": return (Color.yellow.opacity(0.25), .primary)
            case "CLOSED": return (Color.blue.opacity(0.15), .blue)
            default: return (Color.gray.opacity(0.15), .secondary)
            }
        }()
        return Text(statusLabel(status))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(bg)
            .foregroundColor(fg)
            .cornerRadius(6)
    }

    private func statusLabel(_ raw: String) -> String {
        let s = raw.uppercased()
        let map: [String: String] = [
            "DRAFT": "Draft",
            "UNDER_REVIEW": "Under Review",
            "APPROVED": "Approved",
            "ACTIVE": "Active",
            "REJECTED": "Rejected",
            "SUSPENDED": "Suspended",
            "CLOSEOUT_REVIEW": "Closeout Review",
            "CLOSED": "Closed",
            "CLOSEOUT_PENDING": "Closeout pending",
            "EXPIRED": "Expired"
        ]
        return map[s] ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var canReview: Bool {
        // API `POST /permits/:id/review` allows `review_permits` or `manage_any_permits`.
        // Also show Review when user has `manage_permits` (web sidebar parity; avoids hidden actions for project managers).
        sessionManager.hasPermission("review_permits")
            || sessionManager.hasPermission("manage_any_permits")
            || sessionManager.hasPermission("manage_permits")
    }

    private var canManage: Bool {
        sessionManager.hasPermission("manage_permits")
    }

    private func isOwner(_ d: PermitDetail) -> Bool {
        guard let uid = sessionManager.user?.id, let sid = d.submittedById else { return false }
        return uid == sid
    }

    private func formatShortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    private func formatDateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func load() async {
        let tok = sessionManager.token ?? token
        isLoading = true
        errorMessage = nil
        do {
            let d = try await APIClient.fetchPermit(id: permitId, token: tok)
            await MainActor.run {
                detail = d
                isLoading = false
            }
        } catch APIError.tokenExpired {
            await MainActor.run {
                sessionManager.handleTokenExpiration()
                isLoading = false
            }
        } catch APIError.forbidden {
            await MainActor.run {
                sessionManager.handleTokenExpiration()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func runSubmit(_ d: PermitDetail) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.submitPermit(id: d.id, token: tok)
            await load()
        } catch APIError.badRequest(let msg) {
            await MainActor.run { actionError = msg }
        } catch APIError.tokenExpired {
            await MainActor.run { sessionManager.handleTokenExpiration() }
        } catch APIError.forbidden {
            await MainActor.run { sessionManager.handleTokenExpiration() }
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func runDelete() async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.deletePermit(id: permitId, token: tok)
            await MainActor.run { dismiss() }
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func runReview(detail d: PermitDetail, decision: String, comments: String, validUntil: Date?) async {
        let tok = sessionManager.token ?? token
        do {
            if reviewIsCloseout {
                try await APIClient.reviewPermitCloseout(
                    id: d.id,
                    token: tok,
                    decision: decision,
                    comments: comments.isEmpty ? nil : comments,
                    validUntil: validUntil
                )
            } else {
                try await APIClient.reviewPermit(
                    id: d.id,
                    token: tok,
                    decision: decision,
                    comments: comments.isEmpty ? nil : comments,
                    validUntil: validUntil
                )
            }
            await load()
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func runActivate(validUntil: Date?) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.activatePermit(id: permitId, token: tok, validUntil: validUntil)
            await load()
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func runSuspend() async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.suspendPermit(id: permitId, token: tok, notes: notesDraft.isEmpty ? nil : notesDraft)
            await load()
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func runReinstate() async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.reinstatePermit(id: permitId, token: tok, notes: notesDraft.isEmpty ? nil : notesDraft)
            await load()
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }

    private func openCloseoutForm(_ d: PermitDetail) async {
        guard let formId = d.permitType?.closeoutFormTemplate?.id else {
            await MainActor.run {
                actionError = "This permit has no closeout form template. Use the web app or contact support."
            }
            return
        }
        let tok = sessionManager.token ?? token
        do {
            let form = try await APIClient.fetchFormDetails(formId: formId, token: tok)
            await MainActor.run {
                closeoutFormPack = CloseoutFormPack(form: form, permitId: d.id)
            }
        } catch {
            await MainActor.run { actionError = error.localizedDescription }
        }
    }
}

// MARK: - Attachment block

private struct PermitFormAttachmentBlock: View {
    let fieldType: String
    let value: JSONPrimitive
    let token: String

    @State private var urls: [String] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if urls.isEmpty {
                Text("—")
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(urls.indices, id: \.self) { i in
                            let u = urls[i]
                            if let url = URL(string: u), isImageLikeKey(u, fieldType: fieldType) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFill()
                                    default:
                                        Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: 64, height: 64)
                                .clipped()
                                .cornerRadius(6)
                            } else if let fileUrl = URL(string: u) {
                                Link(destination: fileUrl) {
                                    Label("File \(i + 1)", systemImage: "doc")
                                        .font(.caption)
                                }
                            } else {
                                Text("File \(i + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: value) {
            await resolve()
        }
    }

    private func resolve() async {
        let keys = permitFileKeys(from: value)
        guard !keys.isEmpty else {
            await MainActor.run { loading = false; urls = [] }
            return
        }
        var resolved: [String] = []
        for key in keys {
            if key.lowercased().hasPrefix("http://") || key.lowercased().hasPrefix("https://") || key.lowercased().hasPrefix("data:") {
                resolved.append(key)
                continue
            }
            if let u = try? await APIClient.getPresignedUrl(forKey: key, token: token) {
                resolved.append(u)
            } else {
                resolved.append(key)
            }
        }
        await MainActor.run {
            urls = resolved
            loading = false
        }
    }
}

// MARK: - Review sheet

private struct PermitReviewSheet: View {
    let permitNumber: String
    let isCloseout: Bool
    let onSubmit: (String, String, Date?) -> Void
    let onCancel: () -> Void

    @State private var decision = "approved"
    @State private var comments = ""
    @State private var includeValidUntil = false
    @State private var validUntil = Date()

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Decision", selection: $decision) {
                        Text("Approved").tag("approved")
                        Text("Approved with comments").tag("approved_with_comments")
                        Text("Rejected").tag("rejected")
                    }
                }
                Section("Comments") {
                    TextField("Optional", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
                }
                if decision != "rejected" {
                    Section {
                        Toggle("Set permit valid until", isOn: $includeValidUntil)
                        if includeValidUntil {
                            DatePicker("Valid until", selection: $validUntil, displayedComponents: [.date, .hourAndMinute])
                        }
                    }
                }
            }
            .navigationTitle(isCloseout ? "Review closeout" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        let vu: Date? = (decision != "rejected" && includeValidUntil) ? validUntil : nil
                        onSubmit(decision, comments, vu)
                    }
                }
            }
        }
    }
}

// MARK: - Activate sheet

private struct PermitActivateSheet: View {
    let permitNumber: String
    let defaultActiveDays: Int?
    let onActivate: (Date?) -> Void
    let onCancel: () -> Void

    enum DurationChoice: String, CaseIterable, Identifiable {
        case none, d1, d7, d14, d30, d90, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .none: return "No end date"
            case .d1: return "1 day"
            case .d7: return "7 days"
            case .d14: return "14 days"
            case .d30: return "30 days"
            case .d90: return "90 days"
            case .custom: return "Custom date"
            }
        }
    }

    @State private var choice: DurationChoice = .none
    @State private var customDate = Date()

    var body: some View {
        NavigationView {
            Form {
                Section("Active period") {
                    Picker("Duration", selection: $choice) {
                        ForEach(DurationChoice.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                    .onAppear {
                        if let d = defaultActiveDays, [1, 7, 14, 30, 90].contains(d) {
                            switch d {
                            case 1: choice = .d1
                            case 7: choice = .d7
                            case 14: choice = .d14
                            case 30: choice = .d30
                            case 90: choice = .d90
                            default: break
                            }
                        }
                    }
                    if choice == .custom {
                        DatePicker("Valid until", selection: $customDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Activate \(permitNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate") {
                        onActivate(resolvedValidUntil())
                    }
                }
            }
        }
    }

    private func resolvedValidUntil() -> Date? {
        switch choice {
        case .none:
            return nil
        case .d1:
            return endOfDay(afterAddingDays: 1)
        case .d7:
            return endOfDay(afterAddingDays: 7)
        case .d14:
            return endOfDay(afterAddingDays: 14)
        case .d30:
            return endOfDay(afterAddingDays: 30)
        case .d90:
            return endOfDay(afterAddingDays: 90)
        case .custom:
            return customDate
        }
    }

    private func endOfDay(afterAddingDays days: Int) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: days, to: Date()) ?? Date()
        var comps = cal.dateComponents([.year, .month, .day], from: base)
        comps.hour = 23
        comps.minute = 59
        comps.second = 0
        return cal.date(from: comps) ?? base
    }
}
