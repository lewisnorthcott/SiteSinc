//
//  TimesheetsListView.swift
//  SiteSinc
//
//  My timesheets list and detail: view entries/expenses, edit draft, submit for approval.
//

import SwiftUI

private let listDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

// MARK: - Timesheets List

struct TimesheetsListView: View {
    /// When true, shows a "Done" button (for sheet). When false, relies on system back button (for pushed full page).
    var isPresentedAsSheet: Bool = true

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    @State private var timesheets: [Timesheet] = []
    @State private var activeClocks: [TimesheetActiveClock] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreateSheet = false
    @State private var signingOutProjectId: Int?

    private var token: String { sessionManager.token ?? "" }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        ZStack {
            BrandChrome.groupedBackground
                .ignoresSafeArea()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if timesheets.isEmpty {
                emptyStateView
            } else {
                listContent
            }
        }
        .navigationTitle("My Timesheets")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if isPresentedAsSheet {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("Create", systemImage: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateTimesheetSheet(existingTimesheets: timesheets, token: token, onCreated: {
                showCreateSheet = false
                Task { await loadTimesheets() }
            }, onCancel: { showCreateSheet = false })
        }
        .task {
            await loadTimesheets()
        }
        .refreshable {
            await loadTimesheets()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading timesheets...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Unable to Load")
                .font(.headline)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await loadTimesheets() }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandChrome.accent)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No timesheets yet")
                .font(.headline)
            Text("Timesheets are created when you sign in on site. Sign in to a project to create a draft for that day.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var listContent: some View {
        List {
            if !activeClocks.isEmpty {
                Section("Current session") {
                    ForEach(activeClocks, id: \.id) { clock in
                        currentSessionRow(clock: clock)
                    }
                }
            }
            ForEach(timesheets) { ts in
                NavigationLink(value: ts.id) {
                    TimesheetRowView(timesheet: ts)
                }
            }
        }
        .listStyle(.insetGrouped)
        .brandListChrome()
        .navigationDestination(for: Int.self) { id in
            TimesheetDetailView(timesheetId: id, onSubmitted: {
                Task { await loadTimesheets() }
            })
            .environmentObject(sessionManager)
        }
    }

    private func breakHoursForToday(projectId: Int) -> Double? {
        let now = Date()
        guard let ts = timesheets.first(where: { ts in
            now >= ts.periodStart && now <= ts.periodEnd
        }), let entries = ts.entries else { return nil }
        return entries.first(where: { $0.projectId == projectId })?.breakHours
    }

    private func currentSessionRow(clock: TimesheetActiveClock) -> some View {
        let elapsed = Date().timeIntervalSince(clock.signedInAt)
        let hours = max(0, elapsed) / 3600
        let breakHrs = breakHoursForToday(projectId: clock.projectId)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clock.project.name)
                    .font(.headline)
                Spacer()
            }
            HStack {
                Text("Sign in")
                    .foregroundColor(.secondary)
                Spacer()
                Text(Self.timeFormatter.string(from: clock.signedInAt))
            }
            .font(.subheadline)
            HStack {
                Text("Current hours")
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f h", hours))
            }
            .font(.subheadline)
            if let bh = breakHrs, bh > 0 {
                HStack {
                    Text("Break hours")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f h", bh))
                }
                .font(.subheadline)
            }
            if signingOutProjectId == clock.projectId {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 4)
            } else {
                Button {
                    Task { await signOut(projectId: clock.projectId) }
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign out")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 4)
    }

    private func signOut(projectId: Int) async {
        guard !token.isEmpty else { return }
        signingOutProjectId = projectId
        defer { signingOutProjectId = nil }
        do {
            _ = try await APIClient.timesheetClockSignOut(projectId: projectId, latitude: nil, longitude: nil, token: token)
            await loadTimesheets()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func loadTimesheets() async {
        guard !token.isEmpty else {
            errorMessage = "Not signed in"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            async let timesheetsTask = APIClient.fetchMyTimesheets(token: token)
            async let clockTask = APIClient.fetchTimesheetClockStatus(token: token)
            timesheets = try await timesheetsTask
            let status = try await clockTask
            activeClocks = status.activeClocks
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Row

struct TimesheetRowView: View {
    let timesheet: Timesheet

    private var periodText: String {
        listDateFormatter.string(from: timesheet.periodStart)
    }

    private var totalHours: Double {
        (timesheet.entries ?? []).reduce(0) { $0 + $1.hours }
    }

    private var statusColor: Color {
        switch timesheet.status {
        case "DRAFT": return Color.orange
        case "SUBMITTED": return Color.blue
        case "APPROVED": return Color(hex: "#10B981")
        case "REJECTED": return Color.red
        default: return Color.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(periodText)
                    .font(.headline)
                Spacer()
                Text(timesheet.status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(6)
            }
            Text(String(format: "%.1f hours", totalHours))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail

struct TimesheetDetailView: View {
    let timesheetId: Int
    var onSubmitted: (() -> Void)?

    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.dismiss) var dismiss

    @State private var timesheet: Timesheet?
    @State private var activeClocks: [TimesheetActiveClock] = []
    @State private var clockHistoryByProjectId: [Int: [ClockHistorySession]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showEditSheet = false
    @State private var submitError: String?
    @State private var showSubmitAlert = false
    @State private var signingOutProjectId: Int?

    private var token: String { sessionManager.token ?? "" }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await loadDetail() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if let ts = timesheet {
                detailContent(timesheet: ts)
            }
        }
        .navigationTitle("Timesheet")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetail()
        }
        .sheet(isPresented: $showEditSheet) {
            if let ts = timesheet {
                TimesheetEditSheet(
                    timesheet: ts,
                    token: token,
                    onSave: {
                        showEditSheet = false
                        Task { await loadDetail() }
                    },
                    onCancel: { showEditSheet = false }
                )
            }
        }
        .alert("Submit for approval?", isPresented: $showSubmitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Submit") {
                Task { await submit() }
            }
        } message: {
            Text("This timesheet will be sent for approval. You won’t be able to edit it after submitting.")
        }
    }

    private func isTimesheetForCurrentPeriod(_ ts: Timesheet) -> Bool {
        let now = Date()
        return now >= ts.periodStart && now <= ts.periodEnd
    }

    private func activeClockForThisTimesheet(_ ts: Timesheet) -> TimesheetActiveClock? {
        let entryProjectIds = Set((ts.entries ?? []).compactMap { $0.projectId })
        return activeClocks.first { entryProjectIds.contains($0.projectId) }
    }

    /// Sessions that overlap the timesheet period (for showing sign-in/out when entry has no fromTime/toTime).
    private func sessionsInPeriod(for projectId: Int?, timesheet ts: Timesheet) -> [ClockHistorySession] {
        guard let pid = projectId else { return [] }
        let list = clockHistoryByProjectId[pid] ?? []
        let start = ts.periodStart
        let end = ts.periodEnd
        return list
            .filter { $0.signedInAt <= end && $0.signedOutAt >= start }
            .sorted { $0.signedInAt < $1.signedInAt }
    }

    @ViewBuilder
    private func entryHoursBlock(entry: TimesheetEntry, timesheet ts: Timesheet) -> some View {
        HStack {
            Text(entry.project?.name ?? "General")
                .font(.body)
            Spacer()
            Text(String(format: "%.1f h", entry.hours))
                .foregroundColor(.secondary)
        }
        if let from = entry.fromTime, let to = entry.toTime, !from.isEmpty, !to.isEmpty {
            Button {
                showEditSheet = true
            } label: {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Sign in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(from)
                            .font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Text("Sign out")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(to)
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
        } else {
            let sessions = sessionsInPeriod(for: entry.projectId, timesheet: ts)
            if sessions.isEmpty {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("Sign in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("—")
                            .font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Text("Sign out")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("—")
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(sessions) { session in
                    Button {
                        showEditSheet = true
                    } label: {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Text("Sign in")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(Self.timeFormatter.string(from: session.signedInAt))
                                    .font(.subheadline)
                            }
                            HStack(spacing: 4) {
                                Text("Sign out")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(Self.timeFormatter.string(from: session.signedOutAt))
                                    .font(.subheadline)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        HStack {
            Text("Break")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(String(format: "%.1f h", entry.breakHours ?? 0))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func detailContent(timesheet ts: Timesheet) -> some View {
        List {
            if ts.status == "DRAFT", isTimesheetForCurrentPeriod(ts), let clock = activeClockForThisTimesheet(ts) {
                Section("Current session") {
                    HStack {
                        Text(clock.project.name)
                            .font(.headline)
                        Spacer()
                    }
                    HStack {
                        Text("Sign in")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(Self.timeFormatter.string(from: clock.signedInAt))
                    }
                    .font(.subheadline)
                    HStack {
                        Text("Sign out")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("—")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    HStack {
                        Text("Current hours")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f h", max(0, Date().timeIntervalSince(clock.signedInAt)) / 3600))
                    }
                    .font(.subheadline)
                    HStack {
                        Text("Break hours")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f h", (ts.entries ?? []).first(where: { $0.projectId == clock.projectId })?.breakHours ?? 0))
                    }
                    .font(.subheadline)
                    if signingOutProjectId == clock.projectId {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            Task { await signOut(projectId: clock.projectId) }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Sign out")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                HStack {
                    Text("Period")
                    Spacer()
                    Text(listDateFormatter.string(from: ts.periodStart))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Status")
                    Spacer()
                    Text(ts.status)
                        .foregroundColor(statusColor(ts.status))
                        .fontWeight(.medium)
                }
            }

            Section("Hours") {
                let entries = ts.entries ?? []
                let totalHours = entries.reduce(0) { $0 + $1.hours }
                let totalBreak = entries.reduce(0) { $0 + ($1.breakHours ?? 0) }
                ForEach(entries) { entry in
                    entryHoursBlock(entry: entry, timesheet: ts)
                }
                HStack {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer()
                    Text(String(format: "%.1f h", totalHours))
                        .fontWeight(.semibold)
                }
                HStack {
                    Text("Total break")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f h", totalBreak))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            let expenses = ts.expenses ?? []
            if !expenses.isEmpty {
                Section("Expenses") {
                    ForEach(expenses) { exp in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(String(format: "£%.2f", exp.amount))
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            if let d = exp.description, !d.isEmpty {
                                Text(d)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if ts.status == "DRAFT" {
                Section {
                    Button {
                        showEditSheet = true
                    } label: {
                        HStack {
                            Label("Edit timesheet", systemImage: "pencil")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color(UIColor.tertiaryLabel))
                        }
                    }
                    if isSubmitting {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        Button(action: { showSubmitAlert = true }) {
                            HStack {
                                Spacer()
                                Text("Submit for approval")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)
                    }
                    if let err = submitError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "DRAFT": return .orange
        case "SUBMITTED": return .blue
        case "APPROVED": return Color(hex: "#10B981")
        case "REJECTED": return .red
        default: return .secondary
        }
    }

    private func loadDetail() async {
        guard !token.isEmpty else {
            errorMessage = "Not signed in"
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        clockHistoryByProjectId = [:]
        do {
            async let detailTask = APIClient.fetchTimesheet(id: timesheetId, token: token)
            async let clockTask = APIClient.fetchTimesheetClockStatus(token: token)
            let ts = try await detailTask
            let status = try await clockTask
            timesheet = ts
            activeClocks = status.activeClocks
            let projectIds = Set((ts.entries ?? []).compactMap { $0.projectId })
            var history: [Int: [ClockHistorySession]] = [:]
            for pid in projectIds {
                do {
                    let sessions = try await APIClient.fetchClockHistory(projectId: pid, limit: 50, token: token)
                    history[pid] = sessions
                } catch {
                    history[pid] = []
                }
            }
            clockHistoryByProjectId = history
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isLoading = false
    }

    private func signOut(projectId: Int) async {
        guard !token.isEmpty else { return }
        signingOutProjectId = projectId
        defer { signingOutProjectId = nil }
        do {
            _ = try await APIClient.timesheetClockSignOut(projectId: projectId, latitude: nil, longitude: nil, token: token)
            await loadDetail()
        } catch {
            errorMessage = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
    }

    private func submit() async {
        guard !token.isEmpty else { return }
        isSubmitting = true
        submitError = nil
        do {
            _ = try await APIClient.submitTimesheet(id: timesheetId, token: token)
            onSubmitted?()
            dismiss()
        } catch {
            submitError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Edit sheet (draft only)

struct TimesheetEditSheet: View {
    let timesheet: Timesheet
    let token: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var entries: [TimesheetEditEntry] = []
    @State private var expenses: [TimesheetEditExpense] = []
    @State private var isSaving = false
    @State private var saveError: String?

    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone.current
        return f
    }()

    private func dateFromTimeString(_ timeString: String?, refDate: Date, defaultHour: Int = 9, defaultMinute: Int = 0) -> Date {
        guard let s = timeString, !s.isEmpty,
              let date = Self.timeOnlyFormatter.date(from: s) else {
            return Calendar.current.date(bySettingHour: defaultHour, minute: defaultMinute, second: 0, of: refDate) ?? refDate
        }
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return cal.date(bySettingHour: comps.hour ?? defaultHour, minute: comps.minute ?? defaultMinute, second: 0, of: refDate) ?? refDate
    }

    private func timeStringFromDate(_ date: Date) -> String {
        Self.timeOnlyFormatter.string(from: date)
    }

    private func fromTimeBinding(entryIndex i: Int) -> Binding<Date> {
        let ref = timesheet.periodStart
        return Binding(
            get: { dateFromTimeString(entries[i].fromTime, refDate: ref) },
            set: { newDate in
                var updated = entries[i]
                updated.fromTime = timeStringFromDate(newDate)
                entries[i] = updated
            }
        )
    }

    private func toTimeBinding(entryIndex i: Int) -> Binding<Date> {
        let ref = timesheet.periodStart
        return Binding(
            get: { dateFromTimeString(entries[i].toTime, refDate: ref, defaultHour: 17, defaultMinute: 0) },
            set: { newDate in
                var updated = entries[i]
                updated.toTime = timeStringFromDate(newDate)
                entries[i] = updated
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Entries") {
                    ForEach(entries.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(entries[i].projectName)
                                    .lineLimit(1)
                                Spacer()
                                TextField("Hours", value: $entries[i].hours, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                            }
                            DatePicker("Sign in time", selection: fromTimeBinding(entryIndex: i), displayedComponents: .hourAndMinute)
                                .font(.subheadline)
                            DatePicker("Sign out time", selection: toTimeBinding(entryIndex: i), displayedComponents: .hourAndMinute)
                                .font(.subheadline)
                            HStack {
                                Text("Break hours")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Spacer()
                                TextField("0", value: $entries[i].breakHours, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                            }
                            .font(.subheadline)
                            Toggle(isOn: $entries[i].unpaid) {
                                Text("Unpaid / break")
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Expenses") {
                    ForEach(expenses.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Amount (£)")
                                Spacer()
                                TextField("0", value: $expenses[i].amount, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                            }
                            TextField("Description", text: $expenses[i].description)
                        }
                    }
                    Button("Add expense") {
                        expenses.append(TimesheetEditExpense(amount: 0, description: ""))
                    }
                }
                if let err = saveError {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit timesheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                entries = (timesheet.entries ?? []).map {
                    TimesheetEditEntry(
                        id: $0.id,
                        projectId: $0.projectId,
                        projectName: $0.project?.name ?? "General",
                        hours: $0.hours,
                        breakHours: $0.breakHours ?? 0,
                        fromTime: $0.fromTime,
                        toTime: $0.toTime,
                        unpaid: $0.unpaid ?? false
                    )
                }
                expenses = (timesheet.expenses ?? []).map {
                    TimesheetEditExpense(amount: $0.amount, description: $0.description ?? "")
                }
                if expenses.isEmpty {
                    expenses = [TimesheetEditExpense(amount: 0, description: "")]
                }
            }
        }
    }

    private func save() async {
        let entryPayloads = entries.map { e -> [String: Any] in
            var d: [String: Any] = [
                "hours": e.hours,
                "breakHours": e.breakHours,
                "unpaid": e.unpaid
            ]
            if let pid = e.projectId { d["projectId"] = pid }
            if let from = e.fromTime, !from.isEmpty { d["fromTime"] = from }
            if let to = e.toTime, !to.isEmpty { d["toTime"] = to }
            return d
        }
        let expensePayloads = expenses
            .filter { $0.amount > 0 }
            .map { e -> [String: Any] in
                var d: [String: Any] = ["amount": e.amount]
                if !e.description.isEmpty { d["description"] = e.description }
                return d
            }
        isSaving = true
        saveError = nil
        do {
            _ = try await APIClient.updateTimesheet(
                id: timesheet.id,
                entries: entryPayloads,
                expenses: expensePayloads,
                token: token
            )
            onSave()
        } catch {
            saveError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Create timesheet sheet

struct CreateTimesheetSheet: View {
    let existingTimesheets: [Timesheet]
    let token: String
    let onCreated: () -> Void
    let onCancel: () -> Void

    @State private var selectedDate = Date()
    @State private var isCreating = false
    @State private var createError: String?

    private var calendar: Calendar { Calendar.current }
    private var dayStart: Date {
        calendar.startOfDay(for: selectedDate)
    }
    private var dayEnd: Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 59, of: selectedDate) ?? selectedDate
    }

    /// True if the selected date already has a timesheet (any status).
    private var selectedDateAlreadyHasTimesheet: Bool {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        return existingTimesheets.contains { ts in
            let tsDay = calendar.startOfDay(for: ts.periodStart)
            return tsDay == selectedDay
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                } header: {
                    Text("New draft timesheet")
                } footer: {
                    if selectedDateAlreadyHasTimesheet {
                        Text("You already have a timesheet for this day. Open it from the list to edit or submit.")
                            .foregroundColor(.orange)
                    } else {
                        Text("Creates an empty draft for the selected day. Add hours and expenses in the timesheet, then submit for approval.")
                    }
                }
                if let err = createError {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create timesheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(isCreating || selectedDateAlreadyHasTimesheet)
                }
            }
        }
    }

    private func create() async {
        isCreating = true
        createError = nil
        let entries: [[String: Any]] = [["hours": 0]]
        do {
            _ = try await APIClient.createTimesheet(
                periodStart: dayStart,
                periodEnd: dayEnd,
                entries: entries,
                expenses: [],
                token: token
            )
            onCreated()
        } catch {
            createError = (error as? APIError)?.displayMessage ?? error.localizedDescription
        }
        isCreating = false
    }
}

struct TimesheetEditEntry: Identifiable {
    let id: Int
    let projectId: Int?
    let projectName: String
    var hours: Double
    var breakHours: Double
    var fromTime: String?
    var toTime: String?
    var unpaid: Bool
}

struct TimesheetEditExpense: Identifiable {
    let id = UUID()
    var amount: Double
    var description: String
}
