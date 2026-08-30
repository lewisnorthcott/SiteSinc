import SwiftUI
import UIKit

enum PermitPermissions {
    private static func names(from user: User?) -> Set<String> {
        Set(user?.permissions?.map(\.name) ?? [])
    }

    private static func isAdmin(_ user: User?) -> Bool {
        user?.roles?.contains {
            let name = $0.name.lowercased()
            return name == "admin" || name == "superadmin"
        } ?? false
    }

    private static func has(_ user: User?, _ permission: String) -> Bool {
        isAdmin(user) || names(from: user).contains(permission)
    }

    static func canCreate(user: User?) -> Bool {
        has(user, "create_permits")
    }

    static func canManage(user: User?) -> Bool {
        has(user, "manage_permits") || has(user, "manage_any_permits")
    }

    static func canOverrideReview(user: User?) -> Bool {
        has(user, "manage_any_permits")
    }

    /// Matches `POST /permits/:id/review` and `POST /permits/:id/closeout/review`.
    static func canReview(user: User?) -> Bool {
        has(user, "review_permits") || canOverrideReview(user: user)
    }

    /// Matches close-out / daily handback / resume: permission, manage, or the person who raised it.
    static func canCloseout(user: User?, permit: PermitDetail) -> Bool {
        if let uid = user?.id, let ownerId = permit.submittedById, uid == ownerId {
            return true
        }
        return has(user, "closeout_permits") || canManage(user: user)
    }

    static func isAssignedToCurrentStage(user: User?, permit: PermitDetail) -> Bool {
        guard let uid = user?.id else { return false }
        let stageId = permit.currentStageId ?? permit.currentStage?.id
        return (permit.approvals ?? []).contains { approval in
            let matchesUser = approval.reviewerId == uid || approval.reviewer?.id == uid
            guard matchesUser else { return false }
            guard let stageId else { return true }
            return approval.stageId == stageId
        }
    }

    /// Review is allowed only with `review_permits` (or override) and an assignment on the current stage.
    static func canReviewThisPermit(user: User?, permit: PermitDetail) -> Bool {
        guard canReview(user: user) else { return false }
        if canOverrideReview(user: user) { return true }
        return isAssignedToCurrentStage(user: user, permit: permit)
    }

    static func canEditDraft(user: User?, permit: PermitDetail) -> Bool {
        if canManage(user: user) { return true }
        guard let uid = user?.id, let ownerId = permit.submittedById, uid == ownerId else { return false }
        return has(user, "create_permits")
    }
}

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
        if fieldType == "links" {
            return arr.compactMap { linkDisplayString(from: $0) }.joined(separator: "\n")
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

private func linkDisplayString(from value: JSONPrimitive) -> String? {
    switch value {
    case .string(let s):
        return s.isEmpty ? nil : s
    case .object(let dict):
        if case .string(let displayText) = dict["displayText"], !displayText.isEmpty {
            return displayText
        }
        let reference: String = {
            if case .string(let s) = dict["reference"] { return s }
            return ""
        }()
        let title: String = {
            if case .string(let s) = dict["title"] { return s }
            return ""
        }()
        if !reference.isEmpty && !title.isEmpty { return "\(reference): \(title)" }
        if !title.isEmpty { return title }
        if !reference.isEmpty { return reference }
        return nil
    default:
        return nil
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
    @State private var showPhotoCloseoutSheet = false
    @State private var photoCloseoutIsDaily = false
    @State private var showResumePhotoSheet = false
    @State private var showExtendSheet = false
    @State private var showAmendSheet = false
    @State private var showAddIsolation = false
    @State private var showAddParty = false
    @State private var addPartyRole = "OPERATIVE"
    @State private var selectedPartyUserId: Int?
    @State private var projectUsers: [User] = []
    @State private var sharePdfItem: ShareSheetItem?
    @State private var linkKind = "rams"
    @State private var linkIdText = ""

    @State private var rejectedFormFlow: RejectedPermitFormFlow?

    struct CloseoutFormPack: Identifiable {
        let id = UUID()
        let form: FormModel
        let permitId: Int
        var isDaily: Bool = false
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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await sharePdf() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task {
            await load()
            await loadProjectUsers()
        }
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
                    onSubmit: { decision, comments, validUntil, activateAfter in
                        showReviewSheet = false
                        Task { await runReview(detail: d, decision: decision, comments: comments, validUntil: validUntil, activateAfter: activateAfter) }
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
                permitCloseoutIsDaily: pack.isDaily,
                navigationTitleOverride: pack.isDaily ? "Close out day" : "Close-out",
                onSave: {
                    closeoutFormPack = nil
                    Task { await load() }
                }
            )
            .environmentObject(sessionManager)
        }
        .sheet(item: $sharePdfItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $showExtendSheet) {
            if let d = detail {
                PermitActivateSheet(
                    permitNumber: d.permitNumber,
                    defaultActiveDays: d.permitType?.defaultActiveDurationDays,
                    confirmTitle: "Extend",
                    onActivate: { validUntil in
                        showExtendSheet = false
                        Task { await runExtend(validUntil: validUntil) }
                    },
                    onCancel: { showExtendSheet = false }
                )
            }
        }
        .sheet(isPresented: $showAmendSheet) {
            PermitAmendSheet(
                notesDraft: $notesDraft,
                onSave: {
                    showAmendSheet = false
                    Task { await runAmend() }
                },
                onCancel: { showAmendSheet = false }
            )
        }
        .sheet(isPresented: $showAddIsolation) {
            PermitAddIsolationSheet { kind, description, location in
                showAddIsolation = false
                Task { await runAddIsolation(kind: kind, description: description, location: location) }
            } onCancel: {
                showAddIsolation = false
            }
        }
        .sheet(isPresented: $showAddParty) {
            UserPickerView(users: projectUsers, selectedUserId: $selectedPartyUserId, title: "Add \(addPartyRole.replacingOccurrences(of: "_", with: " ").capitalized)")
                .onDisappear {
                    if let uid = selectedPartyUserId {
                        Task { await runAddParty(userId: uid, role: addPartyRole) }
                        selectedPartyUserId = nil
                    }
                }
        }
        .sheet(isPresented: $showResumePhotoSheet) {
            PermitPhotoCloseoutSheet(
                permitNumber: detail?.permitNumber ?? "Permit",
                isDaily: false,
                titleOverride: "Resume inspection",
                onSubmit: { photoData in
                    showResumePhotoSheet = false
                    Task { await submitResumePhoto(photoData) }
                },
                onCancel: { showResumePhotoSheet = false }
            )
        }
        .sheet(isPresented: $showPhotoCloseoutSheet) {
            PermitPhotoCloseoutSheet(
                permitNumber: detail?.permitNumber ?? summaryPermit?.permitNumber ?? "Permit",
                isDaily: photoCloseoutIsDaily,
                onSubmit: { photoData in
                    let isDaily = photoCloseoutIsDaily
                    showPhotoCloseoutSheet = false
                    Task { await submitPhotoOnlyCloseout(photoData, isDaily: isDaily) }
                },
                onCancel: { showPhotoCloseoutSheet = false }
            )
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
                peopleSection(d)
                isolationsSection(d)
                linksSection(d)
                dailyLogsSection(d)
                amendmentsSection(d)
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
            if d.permitType?.requiresDailyCloseout == true, let daily = d.dailyState {
                LabeledContent("Day status", value: dailyStateLabel(daily))
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

    private func peopleSection(_ d: PermitDetail) -> some View {
        let parties = d.parties ?? []
        let issuer = parties.first { $0.role.uppercased() == "ISSUER" }
        let acceptor = parties.first { $0.role.uppercased() == "ACCEPTOR" }
        let others = parties.filter {
            let role = $0.role.uppercased()
            return role != "ISSUER" && role != "ACCEPTOR"
        }
        return Section("People") {
            partyNamedRow(label: "Issued by", party: issuer, permit: d)
            partyNamedRow(label: "Person in charge", party: acceptor, permit: d)
            ForEach(others) { party in
                partyNamedRow(label: party.roleLabel, party: party, permit: d)
            }
            if canManage || isOwner(d) {
                Menu("Add person") {
                    Button("Issued by") { addPartyRole = "ISSUER"; showAddParty = true }
                    Button("Person in charge") { addPartyRole = "ACCEPTOR"; showAddParty = true }
                    Button("Competent person") { addPartyRole = "COMPETENT_PERSON"; showAddParty = true }
                    Button("Operative") { addPartyRole = "OPERATIVE"; showAddParty = true }
                }
            }
        }
    }

    @ViewBuilder
    private func partyNamedRow(label: String, party: PermitParty?, permit: PermitDetail) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                Text(party.map(partyDisplayName) ?? "Not named")
                    .font(.subheadline)
                    .foregroundColor(party == nil ? .secondary : .primary)
            }
            Spacer()
            if let party {
                if party.briefedAt != nil {
                    Text("Briefed")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if canManage || isOwner(permit) {
                    Button("Brief") {
                        Task { await runBrief(partyId: party.id) }
                    }
                } else {
                    Text("Not briefed")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func partyDisplayName(_ party: PermitParty) -> String {
        if let user = projectUsers.first(where: { $0.id == party.userId }) {
            return userDisplayName(user)
        }
        if let me = sessionManager.user, me.id == party.userId {
            return userDisplayName(me)
        }
        return party.user?.email ?? "User \(party.userId)"
    }

    private func isolationsSection(_ d: PermitDetail) -> some View {
        let isolations = d.isolations ?? []
        return Section("Isolations") {
            if isolations.isEmpty {
                Text("No isolation points recorded.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(isolations) { iso in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(iso.kind.capitalized) · \(iso.description)")
                    if let loc = iso.locationNote, !loc.isEmpty {
                        Text(loc).font(.caption).foregroundColor(.secondary)
                    }
                    HStack {
                        Text(iso.restoredAt == nil ? "Unrestored" : "Restored")
                            .font(.caption)
                            .foregroundColor(iso.restoredAt == nil ? .orange : .green)
                        Spacer()
                        if iso.restoredAt == nil, canManage || isOwner(d) {
                            Button("Restore") {
                                Task { await runRestoreIsolation(iso.id) }
                            }
                        }
                    }
                }
            }
            if canManage || isOwner(d) {
                Button("Add isolation") { showAddIsolation = true }
            }
        }
    }

    private func linksSection(_ d: PermitDetail) -> some View {
        Section("Linked records") {
            ForEach(d.ramsLinks ?? []) { link in
                LabeledContent("RA/MS", value: link.projectRams?.title ?? link.projectRams?.reference ?? "#\(link.projectRamsId)")
            }
            ForEach(d.drawingLinks ?? []) { link in
                LabeledContent("Drawing", value: [link.drawing?.number, link.drawing?.title].compactMap { $0 }.joined(separator: " · "))
            }
            ForEach(d.toolboxTalkLinks ?? []) { link in
                LabeledContent("Toolbox talk", value: link.projectToolboxTalk?.title ?? link.projectToolboxTalk?.reference ?? "#\(link.projectToolboxTalkId)")
            }
            if canManage || isOwner(d) {
                Picker("Link type", selection: $linkKind) {
                    Text("RA/MS").tag("rams")
                    Text("Drawing").tag("drawing")
                    Text("Toolbox talk").tag("tbt")
                }
                TextField("Record ID", text: $linkIdText)
                    .keyboardType(.numberPad)
                Button("Link") {
                    Task { await runLink() }
                }
                .disabled(Int(linkIdText) == nil)
            }
        }
    }

    private func dailyLogsSection(_ d: PermitDetail) -> some View {
        let logs = d.dailyLogs ?? []
        guard !logs.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(Section("Daily close-out") {
            ForEach(logs) { log in
                VStack(alignment: .leading, spacing: 6) {
                    Text(log.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.medium))
                    if let at = log.submittedAt {
                        Text("\(log.submittedBy?.email ?? "—") · \(formatDateTime(at))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let photo = log.data?["closeoutPhoto"] ?? log.data?["resumePhoto"] {
                        PermitFormAttachmentBlock(fieldType: "image", value: photo, token: sessionManager.token ?? token)
                    }
                    if let data = log.formSubmission?.data, !data.isEmpty {
                        ForEach(Array(data.keys.sorted()), id: \.self) { key in
                            if key != "closeoutPhoto" && key != "resumePhoto", let value = data[key] {
                                LabeledContent(key, value: displayString(from: value, fieldType: "text"))
                            }
                        }
                    }
                }
            }
        })
    }

    private func amendmentsSection(_ d: PermitDetail) -> some View {
        let rows = d.amendments ?? []
        guard !rows.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(Section("Amendments") {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.kind.capitalized)
                        .font(.subheadline.weight(.medium))
                    if let notes = row.notes, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundColor(.secondary)
                    }
                    if let prev = row.previousValidUntil, let next = row.newValidUntil {
                        Text("\(formatDateTime(prev)) → \(formatDateTime(next))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        })
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
            if field.type != "heading" && field.type != "subheading" {
                Text(field.label ?? field.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if ["image", "camera", "attachment", "signature"].contains(field.type) {
                PermitFormAttachmentBlock(fieldType: field.type, value: value, token: sessionManager.token ?? token)
            } else if field.type == "heading" {
                Text(field.label ?? "")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
            } else if field.type == "subheading" {
                Text(field.label ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
            } else if field.type == "links" {
                let links = displayString(from: value, fieldType: field.type)
                if links.isEmpty {
                    Text("—")
                        .font(.body)
                        .foregroundColor(.secondary)
                } else {
                    Text(links)
                        .font(.body)
                }
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
        let canEditDraft = PermitPermissions.canEditDraft(user: sessionManager.user, permit: d)
        let canReviewThis = PermitPermissions.canReviewThisPermit(user: sessionManager.user, permit: d)
        let canCloseout = PermitPermissions.canCloseout(user: sessionManager.user, permit: d)
        let showNoStageHint = (status == "DRAFT" || status == "REJECTED") && approvalStages.isEmpty && canEditDraft
        let daily = (d.dailyState ?? "WORKING").uppercased()
        let hasActions: Bool = {
            switch status {
            case "DRAFT": return canEditDraft
            case "REJECTED": return canEditDraft
            case "UNDER_REVIEW": return canReviewThis
            case "APPROVED": return canManage
            case "ACTIVE":
                return (canCloseout && (d.permitType?.requiresDailyCloseout == true || d.permitType?.requiresCloseout == true))
                    || canManage
            case "EXPIRED": return canManage
            case "SUSPENDED": return canManage
            case "CLOSEOUT_REVIEW": return canReviewThis
            default: return false
            }
        }()

        if !hasActions && !showNoStageHint && actionError == nil {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if let err = actionError {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if showNoStageHint {
                    Text("No approval stages. Activate to put this permit live immediately.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if status == "DRAFT", canEditDraft {
                    let canActivateNow = approvalStages.isEmpty && hasIssuerAndAcceptor(d)
                    actionBarPrimaryButton(
                        title: approvalStages.isEmpty ? "Activate" : "Submit",
                        systemImage: approvalStages.isEmpty ? "bolt.fill" : "paperplane.fill"
                    ) {
                        Task { await runSubmit(d) }
                    }
                    .disabled(approvalStages.isEmpty && !canActivateNow)
                    if approvalStages.isEmpty && !canActivateNow {
                        Text("Name who this is issued by and the person in charge before activating.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 10) {
                        if let tid = d.permitType?.formTemplate?.id {
                            actionBarSecondaryButton(title: "Edit", systemImage: "pencil") {
                                rejectedFormFlow = RejectedPermitFormFlow(permit: Permit(from: d), formTemplateId: tid)
                            }
                        }
                        actionBarSecondaryButton(title: "Delete", systemImage: "trash", destructive: true) {
                            showDeleteConfirm = true
                        }
                    }
                }

                if status == "REJECTED", canEditDraft {
                    actionBarPrimaryButton(
                        title: approvalStages.isEmpty ? "Activate" : "Resubmit",
                        systemImage: approvalStages.isEmpty ? "bolt.fill" : "paperplane.fill"
                    ) {
                        Task { await runSubmit(d) }
                    }
                    if let tid = d.permitType?.formTemplate?.id {
                        actionBarSecondaryButton(title: "Edit", systemImage: "pencil") {
                            rejectedFormFlow = RejectedPermitFormFlow(permit: Permit(from: d), formTemplateId: tid)
                        }
                    }
                }

                if status == "UNDER_REVIEW", canReviewThis {
                    actionBarPrimaryButton(title: "Review", systemImage: "clipboard.fill") {
                        reviewIsCloseout = false
                        showReviewSheet = true
                    }
                }

                if status == "APPROVED", canManage {
                    actionBarPrimaryButton(title: "Activate", systemImage: "play.fill") {
                        showActivateSheet = true
                    }
                    .disabled(!hasIssuerAndAcceptor(d))
                    if !hasIssuerAndAcceptor(d) {
                        Text("Name who this is issued by and the person in charge before activating.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if status == "ACTIVE" {
                    if canCloseout, d.permitType?.requiresDailyCloseout == true {
                        if daily == "WORKING" || daily == "OVERDUE_HANDBACK" {
                            actionBarPrimaryButton(
                                title: daily == "OVERDUE_HANDBACK" ? "Close out overdue day" : "Close out day",
                                systemImage: "moon.zzz"
                            ) {
                                Task { await openCloseoutForm(d, isDaily: true) }
                            }
                        }
                        if daily == "HANDED_BACK" {
                            actionBarPrimaryButton(title: "Resume work", systemImage: "play.fill") {
                                if d.permitType?.requireResumeInspection == true {
                                    showResumePhotoSheet = true
                                } else {
                                    Task { await runDailyResume() }
                                }
                            }
                        }
                    }
                    if canCloseout, d.permitType?.requiresCloseout == true {
                        let unrestored = (d.isolations ?? []).contains { $0.restoredAt == nil }
                        if unrestored {
                            Text("Restore isolations before final close-out.")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                        if d.permitType?.requiresDailyCloseout == true {
                            actionBarSecondaryButton(title: "Final close-out", systemImage: "checklist") {
                                Task { await openCloseoutForm(d, isDaily: false) }
                            }
                            .disabled(unrestored)
                        } else {
                            actionBarPrimaryButton(title: "Close out", systemImage: "checklist") {
                                Task { await openCloseoutForm(d, isDaily: false) }
                            }
                            .disabled(unrestored)
                        }
                    }
                    if canManage {
                        actionBarSecondaryButton(title: "Extend", systemImage: "calendar.badge.plus") {
                            showExtendSheet = true
                        }
                        actionBarSecondaryButton(title: "Amend", systemImage: "pencil") {
                            notesDraft = ""
                            showAmendSheet = true
                        }
                        actionBarSecondaryButton(title: "Suspend", systemImage: "pause.fill") {
                            notesDraft = ""
                            moderationSheet = .suspend
                        }
                    }
                }

                if status == "EXPIRED", canManage {
                    actionBarPrimaryButton(title: "Extend to reactivate", systemImage: "calendar.badge.plus") {
                        showExtendSheet = true
                    }
                }

                if status == "SUSPENDED", canManage {
                    actionBarPrimaryButton(title: "Reinstate", systemImage: "arrow.counterclockwise") {
                        notesDraft = ""
                        moderationSheet = .reinstate
                    }
                }

                if status == "CLOSEOUT_REVIEW", canReviewThis {
                    actionBarPrimaryButton(title: "Review closeout", systemImage: "clipboard.fill") {
                        reviewIsCloseout = true
                        showReviewSheet = true
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Rectangle()
                    .fill(.bar)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func actionBarPrimaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func actionBarSecondaryButton(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
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
            case "EXPIRED": return (Color.gray.opacity(0.25), .secondary)
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

    private var canManage: Bool {
        PermitPermissions.canManage(user: sessionManager.user)
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

    private func runReview(detail d: PermitDetail, decision: String, comments: String, validUntil: Date?, activateAfter: Bool) async {
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
                if activateAfter, decision != "rejected" {
                    try await APIClient.activatePermit(id: d.id, token: tok, validUntil: validUntil)
                }
            }
            await load()
        } catch APIError.badRequest(let msg) {
            await MainActor.run { actionError = msg }
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runActivate(validUntil: Date?) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.activatePermit(id: permitId, token: tok, validUntil: validUntil)
            await load()
        } catch APIError.badRequest(let msg) {
            await MainActor.run { actionError = msg }
        } catch APIError.forbidden {
            await MainActor.run { actionError = "You do not have permission to activate this permit." }
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
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

    private func openCloseoutForm(_ d: PermitDetail, isDaily: Bool) async {
        let formId = isDaily
            ? (d.permitType?.dailyCloseoutFormTemplate?.id ?? d.permitType?.closeoutFormTemplate?.id)
            : d.permitType?.closeoutFormTemplate?.id
        if let formId {
            let tok = sessionManager.token ?? token
            do {
                let form = try await APIClient.fetchFormDetails(formId: formId, token: tok)
                await MainActor.run {
                    closeoutFormPack = CloseoutFormPack(form: form, permitId: d.id, isDaily: isDaily)
                }
            } catch {
                await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
            }
            return
        }

        await MainActor.run {
            photoCloseoutIsDaily = isDaily
            showPhotoCloseoutSheet = true
        }
    }

    private func submitPhotoOnlyCloseout(_ photoData: Data, isDaily: Bool) async {
        let tok = sessionManager.token ?? token
        do {
            let fileKey = try await APIClient.uploadToolboxTalkFile(
                data: photoData,
                fileName: "closeout-\(permitId).jpg",
                mimeType: "image/jpeg",
                token: tok
            )
            if isDaily {
                try await APIClient.submitPermitDailyHandback(id: permitId, token: tok, formData: ["closeoutPhoto": fileKey])
            } else {
                try await APIClient.submitPermitCloseout(id: permitId, token: tok, formData: ["closeoutPhoto": fileKey])
            }
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runDailyResume(formData: [String: Any]? = nil) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.resumePermitDaily(id: permitId, token: tok, formData: formData)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func submitResumePhoto(_ photoData: Data) async {
        let tok = sessionManager.token ?? token
        do {
            let fileKey = try await APIClient.uploadToolboxTalkFile(
                data: photoData,
                fileName: "resume-\(permitId).jpg",
                mimeType: "image/jpeg",
                token: tok
            )
            await runDailyResume(formData: ["resumePhoto": fileKey])
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func hasIssuerAndAcceptor(_ d: PermitDetail) -> Bool {
        let roles = Set((d.parties ?? []).map { $0.role.uppercased() })
        return roles.contains("ISSUER") && roles.contains("ACCEPTOR")
    }

    private func loadProjectUsers() async {
        let tok = sessionManager.token ?? token
        projectUsers = (try? await APIClient.fetchProjectUsers(projectId: projectId, token: tok)) ?? []
    }

    private func runBrief(partyId: Int) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.briefPermitParty(id: permitId, partyId: partyId, token: tok)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runAddParty(userId: Int, role: String) async {
        let tok = sessionManager.token ?? token
        var parties = (detail?.parties ?? []).map { ["userId": $0.userId, "role": $0.role] as [String: Any] }
        if !parties.contains(where: { ($0["userId"] as? Int) == userId && ($0["role"] as? String) == role }) {
            parties.append(["userId": userId, "role": role])
        }
        do {
            try await APIClient.setPermitParties(id: permitId, token: tok, parties: parties)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runAddIsolation(kind: String, description: String, location: String?) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.addPermitIsolation(id: permitId, token: tok, kind: kind, description: description, locationNote: location)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runRestoreIsolation(_ isolationId: Int) async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.restorePermitIsolation(id: permitId, isolationId: isolationId, token: tok)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runExtend(validUntil: Date?) async {
        guard let validUntil else { return }
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.extendPermit(id: permitId, token: tok, validUntil: validUntil)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runAmend() async {
        let tok = sessionManager.token ?? token
        do {
            try await APIClient.amendPermit(id: permitId, token: tok, notes: notesDraft.isEmpty ? nil : notesDraft)
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func runLink() async {
        guard let recordId = Int(linkIdText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let tok = sessionManager.token ?? token
        do {
            switch linkKind {
            case "drawing":
                try await APIClient.linkPermitDrawing(id: permitId, token: tok, drawingId: recordId)
            case "tbt":
                try await APIClient.linkPermitToolboxTalk(id: permitId, token: tok, projectToolboxTalkId: recordId)
            default:
                try await APIClient.linkPermitRams(id: permitId, token: tok, projectRamsId: recordId)
            }
            await MainActor.run { linkIdText = "" }
            await load()
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func sharePdf() async {
        let tok = sessionManager.token ?? token
        do {
            let url = try await APIClient.fetchPermitPDF(
                id: permitId,
                permitNumber: detail?.permitNumber ?? "permit",
                token: tok
            )
            await MainActor.run { sharePdfItem = ShareSheetItem(url: url) }
        } catch {
            await MainActor.run { actionError = (error as? APIError)?.displayMessage ?? error.localizedDescription }
        }
    }

    private func dailyStateLabel(_ state: String) -> String {
        switch state.uppercased() {
        case "WORKING": return "Working"
        case "HANDED_BACK": return "Handed back for the day"
        case "OVERDUE_HANDBACK": return "Day close-out overdue"
        default: return state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Photo-only close-out

private struct PermitPhotoCloseoutSheet: View {
    let permitNumber: String
    var isDaily: Bool = false
    var titleOverride: String? = nil
    let onSubmit: (Data) -> Void
    let onCancel: () -> Void

    @State private var photoData: Data?
    @State private var pickerSource: PhotoSource?

    private var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isDaily
                     ? "Capture or upload a photo of the area to close out this day."
                     : "Capture or upload a photo of the area to complete close-out.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipped()
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("No photo selected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }

                HStack(spacing: 12) {
                    if canUseCamera {
                        Button {
                            pickerSource = .camera
                        } label: {
                            Label("Take Photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Button {
                        pickerSource = .library
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    if let photoData {
                        onSubmit(photoData)
                    }
                } label: {
                    Label(titleOverride ?? (isDaily ? "Close out day" : "Submit Closeout"), systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(photoData == nil)
            }
            .padding()
            .navigationTitle(titleOverride ?? (isDaily ? "Close out day — \(permitNumber)" : "Close Out — \(permitNumber)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .sheet(item: $pickerSource) { source in
                AssetPhotoPicker(
                    sourceType: source.pickerType,
                    onImageCaptured: { data in
                        photoData = data
                        pickerSource = nil
                    },
                    onDismiss: { pickerSource = nil }
                )
                .ignoresSafeArea()
            }
        }
    }

    private enum PhotoSource: String, Identifiable {
        case camera
        case library
        var id: String { rawValue }
        var pickerType: UIImagePickerController.SourceType {
            self == .camera ? .camera : .photoLibrary
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
    let onSubmit: (String, String, Date?, Bool) -> Void
    let onCancel: () -> Void

    @State private var decision = "approved"
    @State private var comments = ""
    @State private var includeValidUntil = false
    @State private var validUntil = Date()
    @State private var activateAfterApprove = false

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
                        if !isCloseout {
                            Toggle("Approve and activate", isOn: $activateAfterApprove)
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
                    Button(decision != "rejected" && activateAfterApprove && !isCloseout ? "Approve and activate" : "Submit") {
                        let vu: Date? = (decision != "rejected" && includeValidUntil) ? validUntil : nil
                        onSubmit(decision, comments, vu, activateAfterApprove && !isCloseout)
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
    var confirmTitle: String = "Activate"
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
            .navigationTitle("\(confirmTitle) \(permitNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) {
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

private struct PermitAmendSheet: View {
    @Binding var notesDraft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Notes") {
                    TextField("What changed?", text: $notesDraft, axis: .vertical)
                }
                Section {
                    Button("Save amendment", action: onSave)
                }
            }
            .navigationTitle("Amend permit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct PermitAddIsolationSheet: View {
    var onSave: (String, String, String?) -> Void
    var onCancel: () -> Void
    @State private var kind = "ELECTRICAL"
    @State private var description = ""
    @State private var location = ""

    var body: some View {
        NavigationView {
            Form {
                Picker("Kind", selection: $kind) {
                    Text("Electrical").tag("ELECTRICAL")
                    Text("Mechanical").tag("MECHANICAL")
                    Text("Process").tag("PROCESS")
                    Text("Other").tag("OTHER")
                }
                TextField("Description", text: $description)
                TextField("Location note (optional)", text: $location)
                Section {
                    Button("Add isolation") {
                        onSave(kind, description, location.isEmpty ? nil : location)
                    }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add isolation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}
