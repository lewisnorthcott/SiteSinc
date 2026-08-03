import Foundation
import Network

// MARK: - Offline models

enum OfflineMeetingMutationKind: String, Codable {
    case create
    case updateDetails
    case replaceAgenda
    case replaceMinutes
    case uploadAgendaFile
    case completeMinuteLine
    case reopenMinuteLine
    case minuteLineUpdate
}

struct OfflineMeetingMutation: Codable, Identifiable {
    let id: String
    let kind: OfflineMeetingMutationKind
    let projectId: Int
    let meetingId: Int?
    let createdAt: Date
    // NOTE: never persist auth tokens in queue files. Sync reads a fresh
    // token from the Keychain at send time. (Older queue files contained a
    // "token" key; it is ignored on decode.)

    var createBody: CreateMeetingRequest?
    var updateBody: UpdateMeetingRequest?
    var agendaItems: [AgendaItemInput]?
    var minuteLines: [MinuteLineInput]?

    var agendaFileName: String?
    var agendaMimeType: String?
    var agendaFileData: Data?

    var lineId: Int?
    var comment: String?
    var updateFileName: String?
    var updateMimeType: String?
    var updateFileData: Data?

    init(
        id: String,
        kind: OfflineMeetingMutationKind,
        projectId: Int,
        meetingId: Int?,
        createdAt: Date,
        createBody: CreateMeetingRequest? = nil,
        updateBody: UpdateMeetingRequest? = nil,
        agendaItems: [AgendaItemInput]? = nil,
        minuteLines: [MinuteLineInput]? = nil,
        agendaFileName: String? = nil,
        agendaMimeType: String? = nil,
        agendaFileData: Data? = nil,
        lineId: Int? = nil,
        comment: String? = nil,
        updateFileName: String? = nil,
        updateMimeType: String? = nil,
        updateFileData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.projectId = projectId
        self.meetingId = meetingId
        self.createdAt = createdAt
        self.createBody = createBody
        self.updateBody = updateBody
        self.agendaItems = agendaItems
        self.minuteLines = minuteLines
        self.agendaFileName = agendaFileName
        self.agendaMimeType = agendaMimeType
        self.agendaFileData = agendaFileData
        self.lineId = lineId
        self.comment = comment
        self.updateFileName = updateFileName
        self.updateMimeType = updateMimeType
        self.updateFileData = updateFileData
    }
}

struct CachedMeetingsData: Codable {
    let meetings: [MeetingListItem]
    let cachedAt: Date
    let projectId: Int
}

struct CachedMeetingDetailData: Codable {
    let meeting: MeetingDetail
    let cachedAt: Date
}

// MARK: - OfflineMeetingManager

@MainActor
final class OfflineMeetingManager: ObservableObject {
    static let shared = OfflineMeetingManager()

    @Published var pendingMutations: [OfflineMeetingMutation] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    @Published var isOffline = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sitesinc.offlineMeetingManager")

    private init() {
        loadPendingItems()
        setupNetworkMonitoring()
    }

    var pendingCount: Int { pendingMutations.count }

    func pendingCount(forProject projectId: Int) -> Int {
        pendingMutations.filter { $0.projectId == projectId }.count
    }

    // MARK: - Directories

    private var mutationsDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_meeting_mutations")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private var cacheDirectory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("meeting_cache")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    // MARK: - Network

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                if wasOffline && path.status == .satisfied {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.syncPendingItems()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - List / detail cache

    func cacheMeetings(_ meetings: [MeetingListItem], forProject projectId: Int) {
        let cached = CachedMeetingsData(meetings: meetings, cachedAt: Date(), projectId: projectId)
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_meetings.json")
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("OfflineMeetingManager: Failed to cache meetings: \(error)")
        }
    }

    func getCachedMeetings(forProject projectId: Int) -> [MeetingListItem]? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_meetings.json")
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedMeetingsData.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(cached.cachedAt) > 86400 { return nil }
        return cached.meetings
    }

    func cacheMeetingDetail(_ meeting: MeetingDetail) {
        let cached = CachedMeetingDetailData(meeting: meeting, cachedAt: Date())
        let fileURL = cacheDirectory.appendingPathComponent("meeting_\(meeting.id).json")
        do {
            let data = try JSONEncoder().encode(cached)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("OfflineMeetingManager: Failed to cache meeting detail: \(error)")
        }
    }

    func getCachedMeetingDetail(id: Int) -> MeetingDetail? {
        let fileURL = cacheDirectory.appendingPathComponent("meeting_\(id).json")
        guard let data = try? Data(contentsOf: fileURL),
              let cached = try? JSONDecoder().decode(CachedMeetingDetailData.self, from: data) else {
            return nil
        }
        return cached.meeting
    }

    // MARK: - Queue mutations

    func queue(_ mutation: OfflineMeetingMutation) {
        // Coalesce replace-style mutations for the same meeting
        if let meetingId = mutation.meetingId,
           mutation.kind == .updateDetails || mutation.kind == .replaceAgenda || mutation.kind == .replaceMinutes {
            let superseded = pendingMutations.filter {
                $0.meetingId == meetingId && $0.kind == mutation.kind
            }
            for old in superseded {
                removeMutation(id: old.id)
            }
        }

        pendingMutations.append(mutation)
        persist(mutation)
    }

    func queueCreate(projectId: Int, body: CreateMeetingRequest, token: String) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .create,
            projectId: projectId,
            meetingId: nil,
            createdAt: Date(),
            createBody: body
        ))
    }

    func queueUpdateDetails(projectId: Int, meetingId: Int, body: UpdateMeetingRequest, token: String) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .updateDetails,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            updateBody: body
        ))
    }

    func queueReplaceAgenda(projectId: Int, meetingId: Int, items: [AgendaItemInput], token: String) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .replaceAgenda,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            agendaItems: items
        ))
    }

    func queueReplaceMinutes(projectId: Int, meetingId: Int, lines: [MinuteLineInput], token: String) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .replaceMinutes,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            minuteLines: lines
        ))
    }

    func queueAgendaFileUpload(
        projectId: Int,
        meetingId: Int,
        fileData: Data,
        fileName: String,
        mimeType: String,
        token: String
    ) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .uploadAgendaFile,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            agendaFileName: fileName,
            agendaMimeType: mimeType,
            agendaFileData: fileData
        ))
    }

    func queueCompleteMinuteLine(
        projectId: Int,
        meetingId: Int,
        lineId: Int,
        comment: String?,
        token: String
    ) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .completeMinuteLine,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            lineId: lineId,
            comment: comment
        ))
    }

    func queueReopenMinuteLine(projectId: Int, meetingId: Int, lineId: Int, token: String) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .reopenMinuteLine,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            lineId: lineId
        ))
    }

    func queueMinuteLineUpdate(
        projectId: Int,
        meetingId: Int,
        lineId: Int,
        content: String?,
        fileData: Data?,
        fileName: String?,
        mimeType: String?,
        token: String
    ) {
        queue(OfflineMeetingMutation(
            id: UUID().uuidString,
            kind: .minuteLineUpdate,
            projectId: projectId,
            meetingId: meetingId,
            createdAt: Date(),
            lineId: lineId,
            comment: content,
            updateFileName: fileName,
            updateMimeType: mimeType,
            updateFileData: fileData
        ))
    }

    private func persist(_ mutation: OfflineMeetingMutation) {
        let fileURL = mutationsDirectory.appendingPathComponent("\(mutation.id).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(mutation).write(to: fileURL, options: .atomic)
        } catch {
            print("OfflineMeetingManager: Failed to persist mutation: \(error)")
        }
    }

    private func removeMutation(id: String) {
        // Delete the durable copy BEFORE dropping the in-memory item so a
        // failed delete can never lead to a silent duplicate at next launch.
        let fileURL = mutationsDirectory.appendingPathComponent("\(id).json")
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("OfflineMeetingManager: CRITICAL - could not delete mutation file \(id): \(error)")
            lastSyncError = "A synced meeting change could not be cleared from the offline queue and may be re-sent on next launch."
        }
        pendingMutations.removeAll { $0.id == id }
    }

    private func loadPendingItems() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: mutationsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        pendingMutations = urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(OfflineMeetingMutation.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Sync

    func manualSync() {
        syncPendingItems()
    }

    func syncPendingItems() {
        guard !syncInProgress else { return }
        guard !pendingMutations.isEmpty else { return }
        guard !isOffline else { return }

        syncInProgress = true
        lastSyncError = nil

        Task {
            defer { syncInProgress = false }
            // Snapshot so coalescing during sync doesn't skip items unexpectedly
            let items = pendingMutations.sorted { $0.createdAt < $1.createdAt }
            for mutation in items {
                // Skip if already coalesced away
                guard pendingMutations.contains(where: { $0.id == mutation.id }) else { continue }
                do {
                    try await syncMutation(mutation)
                    removeMutation(id: mutation.id)
                } catch {
                    lastSyncError = (error as? APIError)?.displayMessage ?? error.localizedDescription
                    print("OfflineMeetingManager: Sync failed for \(mutation.id): \(error)")
                    // Stop on first failure to preserve order for dependent creates
                    if mutation.kind == .create { break }
                }
            }
        }
    }

    private func syncMutation(_ mutation: OfflineMeetingMutation) async throws {
        // Always use a fresh token from the Keychain: a token frozen at queue
        // time may have expired while the device was offline.
        guard let token = KeychainHelper.getToken() else {
            throw APIError.tokenExpired
        }
        switch mutation.kind {
        case .create:
            guard let body = mutation.createBody else {
                throw APIError.badRequest(message: "Missing create payload")
            }
            let meeting = try await APIClient.createMeeting(
                projectId: mutation.projectId,
                body: body,
                token: token
            )
            cacheMeetingDetail(meeting)
            if var list = getCachedMeetings(forProject: mutation.projectId) {
                let item = MeetingListItem(
                    id: meeting.id,
                    reference: meeting.reference,
                    title: meeting.title,
                    meetingDate: meeting.meetingDate,
                    nextMeetingDate: meeting.nextMeetingDate,
                    location: meeting.location,
                    status: meeting.status,
                    isPrivate: meeting.isPrivate,
                    categoryId: meeting.categoryId,
                    category: meeting.category,
                    reviewSourceMeetingId: meeting.reviewSourceMeetingId,
                    reviewSourceMeeting: meeting.reviewSourceMeeting,
                    createdAt: meeting.createdAt,
                    createdById: meeting.createdById,
                    createdBy: meeting.createdBy,
                    attendees: meeting.attendees,
                    _count: meeting._count
                )
                list.insert(item, at: 0)
                cacheMeetings(list, forProject: mutation.projectId)
            }

        case .updateDetails:
            guard let meetingId = mutation.meetingId, let body = mutation.updateBody else {
                throw APIError.badRequest(message: "Missing update payload")
            }
            let meeting = try await APIClient.updateMeeting(id: meetingId, body: body, token: token)
            cacheMeetingDetail(meeting)

        case .replaceAgenda:
            guard let meetingId = mutation.meetingId, let items = mutation.agendaItems else {
                throw APIError.badRequest(message: "Missing agenda payload")
            }
            let meeting = try await APIClient.replaceMeetingAgendaItems(
                meetingId: meetingId,
                items: items,
                token: token
            )
            cacheMeetingDetail(meeting)

        case .replaceMinutes:
            guard let meetingId = mutation.meetingId, let lines = mutation.minuteLines else {
                throw APIError.badRequest(message: "Missing minutes payload")
            }
            let meeting = try await APIClient.replaceMeetingMinuteLines(
                meetingId: meetingId,
                lines: lines,
                token: token
            )
            cacheMeetingDetail(meeting)

        case .uploadAgendaFile:
            guard let meetingId = mutation.meetingId,
                  let data = mutation.agendaFileData,
                  let fileName = mutation.agendaFileName else {
                throw APIError.badRequest(message: "Missing agenda file")
            }
            _ = try await APIClient.uploadMeetingAgendaFile(
                meetingId: meetingId,
                fileData: data,
                fileName: fileName,
                mimeType: mutation.agendaMimeType ?? "application/octet-stream",
                token: token
            )
            if let detail = try? await APIClient.fetchMeeting(id: meetingId, token: token) {
                cacheMeetingDetail(detail)
            }

        case .completeMinuteLine:
            guard let meetingId = mutation.meetingId, let lineId = mutation.lineId else {
                throw APIError.badRequest(message: "Missing complete payload")
            }
            _ = try await APIClient.completeMeetingMinuteLine(
                meetingId: meetingId,
                lineId: lineId,
                comment: mutation.comment,
                token: token
            )
            if let detail = try? await APIClient.fetchMeeting(id: meetingId, token: token) {
                cacheMeetingDetail(detail)
            }

        case .reopenMinuteLine:
            guard let meetingId = mutation.meetingId, let lineId = mutation.lineId else {
                throw APIError.badRequest(message: "Missing reopen payload")
            }
            _ = try await APIClient.reopenMeetingMinuteLine(
                meetingId: meetingId,
                lineId: lineId,
                token: token
            )
            if let detail = try? await APIClient.fetchMeeting(id: meetingId, token: token) {
                cacheMeetingDetail(detail)
            }

        case .minuteLineUpdate:
            guard let meetingId = mutation.meetingId, let lineId = mutation.lineId else {
                throw APIError.badRequest(message: "Missing update payload")
            }
            _ = try await APIClient.addMeetingMinuteLineUpdate(
                meetingId: meetingId,
                lineId: lineId,
                content: mutation.comment,
                fileData: mutation.updateFileData,
                fileName: mutation.updateFileName,
                mimeType: mutation.updateMimeType,
                token: token
            )
            if let detail = try? await APIClient.fetchMeeting(id: meetingId, token: token) {
                cacheMeetingDetail(detail)
            }
        }
    }

    static func isConnectivityError(_ error: Error) -> Bool {
        if let apiError = error as? APIError, case .networkError = apiError {
            return true
        }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain
    }
}
