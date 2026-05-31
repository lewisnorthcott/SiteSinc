import SwiftUI

struct LogInvestigationView: View {
    let log: Log
    let projectId: Int
    let token: String
    let onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sessionManager: SessionManager

    @State private var occurredAt: Date
    @State private var severityBand: SeverityBand?
    @State private var injuryInvolved: Bool
    @State private var riddorKeys: Set<String>
    @State private var bodyMapRegions: Set<String>
    @State private var rootCauseSummary: String
    @State private var fiveWhys: [String]
    @State private var investigationOwnerId: Int?
    @State private var markClosed: Bool
    @State private var users: [User] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showForceCloseAlert = false
    @State private var pendingCloseRequest: CreateLogRequest?
    @State private var witnesses: [WitnessStatement]
    @State private var involvedPeople: [InvolvedPerson]
    @State private var newWitnessName = ""
    @State private var newWitnessStatement = ""
    @State private var newPersonName = ""
    @State private var newPersonRole = ""
    @State private var newPersonInjured = false

    init(log: Log, projectId: Int, token: String, onSuccess: @escaping () -> Void) {
        self.log = log
        self.projectId = projectId
        self.token = token
        self.onSuccess = onSuccess

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsedOccurred = log.occurredAt.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) } ?? Date()

        _occurredAt = State(initialValue: parsedOccurred)
        _severityBand = State(initialValue: log.severityBand)
        _injuryInvolved = State(initialValue: log.injuryInvolved ?? false)
        _riddorKeys = State(initialValue: Set(log.incidentPayload?.riddor ?? []))
        _bodyMapRegions = State(initialValue: Set(log.incidentPayload?.bodyMap ?? []))
        _rootCauseSummary = State(initialValue: log.rootCauseSummary ?? "")
        _fiveWhys = State(initialValue: log.incidentPayload?.fiveWhys ?? [])
        _investigationOwnerId = State(initialValue: log.investigationOwnerId)
        _markClosed = State(initialValue: log.closedAt != nil)
        _witnesses = State(initialValue: log.witnessStatements ?? [])
        _involvedPeople = State(initialValue: log.involvedPeople ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Investigation") {
                    DatePicker("Occurred at", selection: $occurredAt, displayedComponents: [.date, .hourAndMinute])
                    SeverityPickerView(selectedBand: $severityBand)
                    Toggle("Injury involved", isOn: $injuryInvolved)
                    if injuryInvolved {
                        BodyMapSelectorView(selectedRegions: $bodyMapRegions)
                    }
                    RiddorCheckView(selectedKeys: $riddorKeys)
                }

                Section("Root cause") {
                    TextField("Root cause summary", text: $rootCauseSummary, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("5 Whys") {
                    ForEach(0..<5, id: \.self) { index in
                        TextField("Why \(index + 1)", text: bindingForWhy(index))
                    }
                }

                Section("Investigation owner") {
                    Picker("Owner", selection: $investigationOwnerId) {
                        Text("None").tag(nil as Int?)
                        ForEach(users, id: \.id) { user in
                            Text("\(user.firstName ?? "") \(user.lastName ?? "")").tag(user.id as Int?)
                        }
                    }
                }

                Section("Witness statements") {
                    ForEach(witnesses) { witness in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(witness.witnessName).font(.subheadline).fontWeight(.medium)
                            Text(witness.statement).font(.caption).foregroundColor(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await deleteWitness(witness) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    TextField("Witness name", text: $newWitnessName)
                    TextField("Statement", text: $newWitnessStatement, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Add witness") {
                        Task { await addWitness() }
                    }
                    .disabled(newWitnessName.trimmingCharacters(in: .whitespaces).isEmpty || newWitnessStatement.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Involved people") {
                    ForEach(involvedPeople) { person in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.name).font(.subheadline)
                                if let role = person.role {
                                    Text(role).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if person.injured == true {
                                Text("Injured").font(.caption2).foregroundColor(.red)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await deletePerson(person) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    TextField("Name", text: $newPersonName)
                    TextField("Role (optional)", text: $newPersonRole)
                    Toggle("Injured", isOn: $newPersonInjured)
                    Button("Add person") {
                        Task { await addPerson() }
                    }
                    .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Closure") {
                    Toggle("Mark closed", isOn: $markClosed)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Investigation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(forceClose: false) } }
                        .disabled(isSaving)
                }
            }
            .task { await loadUsers() }
            .alert("Close anyway?", isPresented: $showForceCloseAlert) {
                Button("Cancel", role: .cancel) { pendingCloseRequest = nil }
                Button("Close anyway", role: .destructive) {
                    Task { await save(forceClose: true) }
                }
            } message: {
                Text("No root cause recorded and/or corrective actions are still open. Close this incident anyway?")
            }
        }
    }

    private func bindingForWhy(_ index: Int) -> Binding<String> {
        Binding(
            get: {
                index < fiveWhys.count ? fiveWhys[index] : ""
            },
            set: { newValue in
                while fiveWhys.count <= index { fiveWhys.append("") }
                fiveWhys[index] = newValue
            }
        )
    }

    private func loadUsers() async {
        do {
            let fetched = try await APIClient.fetchProjectUsers(projectId: projectId, token: sessionManager.token ?? token)
            await MainActor.run { users = fetched }
        } catch {
            print("Failed to load users: \(error)")
        }
    }

    private func buildRequest(forceClose: Bool) -> CreateLogRequest {
        var payload = log.incidentPayload ?? IncidentPayload()
        payload.bodyMap = injuryInvolved && !bodyMapRegions.isEmpty ? Array(bodyMapRegions) : nil
        payload.riddor = riddorKeys.isEmpty ? nil : Array(riddorKeys)
        let whys = fiveWhys.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        payload.fiveWhys = whys.isEmpty ? nil : whys

        var request = CreateLogRequest(
            title: log.title ?? "",
            description: log.description,
            typeId: log.typeId,
            tradeId: log.tradeId,
            statusId: log.statusId,
            hazardId: log.hazardId,
            contributingConditionId: log.contributingConditionId,
            contributingBehaviourId: log.contributingBehaviourId,
            dueDate: log.dueDate,
            priorityId: log.priorityId,
            folderId: log.folderId,
            isPrivate: log.isPrivate,
            assigneeId: log.assigneeId,
            distributionUserIds: log.distributions?.map { $0.userId },
            location: log.location,
            specification: log.specification,
            locationId: log.locationId,
            attachments: nil
        )
        request.occurredAt = ISO8601DateFormatter().string(from: occurredAt)
        request.incidentSeverityBand = severityBand?.rawValue
        request.injuryInvolved = injuryInvolved
        request.regulatoryNotifiable = isRiddorReportable(Array(riddorKeys))
        request.investigationOwnerId = investigationOwnerId
        request.rootCauseSummary = rootCauseSummary.isEmpty ? nil : rootCauseSummary
        request.incidentPayload = payload
        request.closedAt = markClosed ? ISO8601DateFormatter().string(from: Date()) : nil
        request.forceClose = forceClose ? true : nil
        return request
    }

    private func addWitness() async {
        guard !newWitnessName.isEmpty, !newWitnessStatement.isEmpty else { return }
        do {
            let witness = try await APIClient.createWitnessStatement(
                projectId: projectId, logId: log.id,
                witnessName: newWitnessName.trimmingCharacters(in: .whitespaces),
                statement: newWitnessStatement.trimmingCharacters(in: .whitespaces),
                recordedAt: nil, token: sessionManager.token ?? token
            )
            await MainActor.run {
                witnesses.append(witness)
                newWitnessName = ""
                newWitnessStatement = ""
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func deleteWitness(_ witness: WitnessStatement) async {
        do {
            try await APIClient.deleteWitnessStatement(
                projectId: projectId, logId: log.id, statementId: witness.id,
                token: sessionManager.token ?? token
            )
            await MainActor.run { witnesses.removeAll { $0.id == witness.id } }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func addPerson() async {
        guard !newPersonName.isEmpty else { return }
        do {
            let person = try await APIClient.createInvolvedPerson(
                projectId: projectId, logId: log.id,
                name: newPersonName.trimmingCharacters(in: .whitespaces),
                role: newPersonRole.isEmpty ? nil : newPersonRole,
                company: nil, injured: newPersonInjured,
                token: sessionManager.token ?? token
            )
            await MainActor.run {
                involvedPeople.append(person)
                newPersonName = ""
                newPersonRole = ""
                newPersonInjured = false
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func deletePerson(_ person: InvolvedPerson) async {
        do {
            try await APIClient.deleteInvolvedPerson(
                projectId: projectId, logId: log.id, personId: person.id,
                token: sessionManager.token ?? token
            )
            await MainActor.run { involvedPeople.removeAll { $0.id == person.id } }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    private func save(forceClose: Bool) async {
        isSaving = true
        errorMessage = nil
        let request = buildRequest(forceClose: forceClose)
        do {
            _ = try await APIClient.updateLog(
                projectId: projectId, logId: log.id,
                logData: request, token: sessionManager.token ?? token
            )
            await MainActor.run {
                isSaving = false
                onSuccess()
                dismiss()
            }
        } catch APIError.closureGate(let gate) {
            await MainActor.run {
                isSaving = false
                pendingCloseRequest = request
                showForceCloseAlert = true
                errorMessage = gate.message
            }
        } catch {
            await MainActor.run {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
