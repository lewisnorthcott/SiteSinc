import Foundation
import Combine
import Network

// MARK: - Local (offline) HSE draft models

struct LocalHsePhoto: Codable, Identifiable, Equatable {
    let id: String
    let fileName: String
    let capturedAt: Date
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    var uploaded: Bool
}

struct LocalHseObservation: Codable, Identifiable, Equatable {
    let id: String
    var sectionId: String
    var descriptionText: String
    var categoryId: Int?
    var categoryData: [String: String]
    var assignedToId: Int?
    var dueDate: Date?
    var locationId: Int?
    var photos: [LocalHsePhoto]
    /// Set once the observation has been created on the server during sync.
    var serverId: Int?
}

/// A full HSE inspection captured offline, synced as a pipeline:
/// 1) create draft inspection, 2) create observations, 3) upload photos,
/// 4) submit if requested. Progress is persisted after each step so a failed
/// sync resumes without duplicating server records.
struct LocalHseDraft: Codable, Identifiable, Equatable {
    let id: String
    let projectId: Int
    let templateId: Int
    let templateTitle: String
    let templateReference: String?
    /// Snapshot of the live revision at capture time (sections, observation fields).
    let revision: HseTemplateRevision
    var conductedAt: Date
    var accompaniedById: Int?
    var keyPersonnelIds: [Int]
    var headerData: [String: String]
    var observations: [LocalHseObservation]
    var submitRequested: Bool
    var serverInspectionId: Int?
    let createdAt: Date
}

// MARK: - Cached metadata for offline conduct/viewing

struct HseProjectMetadata: Codable {
    let templates: [HseAvailableTemplate]
    let headerFields: [HseInspectionHeaderField]
    let categories: [HseObservationCategory]
    let users: [HseUser]
    let locations: [ProjectLocation]
    let cachedAt: Date
}

private struct CachedHseInspections: Codable {
    let inspections: [HseInspection]
    let cachedAt: Date
}

private struct CachedHseObservations: Codable {
    let observations: [HseObservation]
    let cachedAt: Date
}

// MARK: - OfflineHseInspectionManager

@MainActor
final class OfflineHseInspectionManager: ObservableObject {
    static let shared = OfflineHseInspectionManager()

    @Published var pendingDrafts: [LocalHseDraft] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    @Published var isOffline = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sitesinc.offlineHseManager")
    private let cacheTTL: TimeInterval = 86400 // 24 hours, matching OfflineInspectionManager

    private init() {
        loadPendingDrafts()
        setupNetworkMonitoring()
    }

    func pendingCount(forProject projectId: Int) -> Int {
        pendingDrafts.filter { $0.projectId == projectId }.count
    }

    // MARK: Directories

    private var draftsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_hse_inspections")
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private var photosDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_hse_photos")
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("hse_cache")
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private static func makeCoder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    // MARK: Network monitoring

    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                if wasOffline && path.status == .satisfied {
                    print("OfflineHseInspectionManager: Network restored")
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self?.syncPendingDrafts()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: Metadata cache (templates, header fields, categories, users, locations)

    func cacheMetadata(_ metadata: HseProjectMetadata, forProject projectId: Int) {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_metadata.json")
        let (encoder, _) = Self.makeCoder()
        do {
            try (try encoder.encode(metadata)).write(to: fileURL, options: .atomic)
        } catch {
            print("OfflineHseInspectionManager: Failed to cache metadata: \(error)")
        }
    }

    func getCachedMetadata(forProject projectId: Int, ignoreTTL: Bool = false) -> HseProjectMetadata? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_metadata.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let (_, decoder) = Self.makeCoder()
        guard let metadata = try? decoder.decode(HseProjectMetadata.self, from: data) else { return nil }
        if !ignoreTTL && Date().timeIntervalSince(metadata.cachedAt) > cacheTTL { return nil }
        return metadata
    }

    // MARK: Inspections / observations list caches (offline viewing)

    func cacheInspections(_ inspections: [HseInspection], forProject projectId: Int) {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_inspections.json")
        let (encoder, _) = Self.makeCoder()
        try? (try? encoder.encode(CachedHseInspections(inspections: inspections, cachedAt: Date())))?.write(to: fileURL, options: .atomic)
    }

    func getCachedInspections(forProject projectId: Int) -> (inspections: [HseInspection], cachedAt: Date)? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_inspections.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let (_, decoder) = Self.makeCoder()
        guard let cached = try? decoder.decode(CachedHseInspections.self, from: data),
              Date().timeIntervalSince(cached.cachedAt) <= cacheTTL else { return nil }
        return (cached.inspections, cached.cachedAt)
    }

    func cacheObservations(_ observations: [HseObservation], forProject projectId: Int) {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_observations.json")
        let (encoder, _) = Self.makeCoder()
        try? (try? encoder.encode(CachedHseObservations(observations: observations, cachedAt: Date())))?.write(to: fileURL, options: .atomic)
    }

    func getCachedObservations(forProject projectId: Int) -> (observations: [HseObservation], cachedAt: Date)? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_hse_observations.json")
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let (_, decoder) = Self.makeCoder()
        guard let cached = try? decoder.decode(CachedHseObservations.self, from: data),
              Date().timeIntervalSince(cached.cachedAt) <= cacheTTL else { return nil }
        return (cached.observations, cached.cachedAt)
    }

    // MARK: Draft management

    func draft(withId id: String) -> LocalHseDraft? {
        pendingDrafts.first { $0.id == id }
    }

    /// Creates or updates a local draft (durable copy + in-memory list).
    func saveDraft(_ draft: LocalHseDraft) {
        if let index = pendingDrafts.firstIndex(where: { $0.id == draft.id }) {
            pendingDrafts[index] = draft
        } else {
            pendingDrafts.append(draft)
        }
        persistDraft(draft)
    }

    private func persistDraft(_ draft: LocalHseDraft) {
        let fileURL = draftsDirectory.appendingPathComponent("\(draft.id).json")
        let (encoder, _) = Self.makeCoder()
        do {
            try (try encoder.encode(draft)).write(to: fileURL, options: .atomic)
        } catch {
            print("OfflineHseInspectionManager: Failed to persist draft \(draft.id): \(error)")
        }
    }

    func deleteDraft(_ draftId: String) {
        pendingDrafts.removeAll { $0.id == draftId }
        try? FileManager.default.removeItem(at: draftsDirectory.appendingPathComponent("\(draftId).json"))
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(draftId, isDirectory: true))
    }

    private func loadPendingDrafts() {
        let (_, decoder) = Self.makeCoder()
        let fileURLs = (try? FileManager.default.contentsOfDirectory(at: draftsDirectory, includingPropertiesForKeys: nil)) ?? []
        pendingDrafts = fileURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(LocalHseDraft.self, from: data)
        }.sorted { $0.createdAt < $1.createdAt }
        print("OfflineHseInspectionManager: Loaded \(pendingDrafts.count) pending HSE drafts")
    }

    // MARK: Local photo storage

    func savePhotoData(_ data: Data, draftId: String, photoId: String) -> String? {
        let dir = photosDirectory.appendingPathComponent(draftId, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fileName = "\(photoId).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(fileName), options: .atomic)
            return fileName
        } catch {
            print("OfflineHseInspectionManager: Failed to save photo: \(error)")
            return nil
        }
    }

    func photoData(draftId: String, fileName: String) -> Data? {
        try? Data(contentsOf: photosDirectory.appendingPathComponent(draftId, isDirectory: true).appendingPathComponent(fileName))
    }

    func deletePhotoFile(draftId: String, fileName: String) {
        try? FileManager.default.removeItem(at: photosDirectory.appendingPathComponent(draftId, isDirectory: true).appendingPathComponent(fileName))
    }

    // MARK: Sync

    func manualSync() {
        syncPendingDrafts()
    }

    private func syncPendingDrafts() {
        guard !syncInProgress else { return }
        guard !pendingDrafts.isEmpty else { return }

        syncInProgress = true
        lastSyncError = nil

        Task {
            var errorMessages: [String] = []
            for draft in pendingDrafts {
                do {
                    try await syncDraft(draft)
                } catch {
                    let message = (error as? APIError)?.displayMessage ?? error.localizedDescription
                    print("OfflineHseInspectionManager: Failed to sync draft \(draft.id): \(error)")
                    errorMessages.append(message)
                }
            }
            syncInProgress = false
            if !errorMessages.isEmpty {
                lastSyncError = "Failed to sync \(errorMessages.count) inspection(s): \(errorMessages[0])"
            }
        }
    }

    /// Runs the pipeline for one draft, persisting progress after each step so
    /// retries never duplicate server records.
    private func syncDraft(_ initialDraft: LocalHseDraft) async throws {
        // Always use a fresh token — one frozen at capture time may have expired.
        guard let token = KeychainHelper.getToken() else {
            throw NSError(domain: "OfflineHseInspectionManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication token missing"])
        }
        var draft = initialDraft

        // Step 1: create the draft inspection on the server
        if draft.serverInspectionId == nil {
            let created = try await APIClient.createHseInspection(
                projectId: draft.projectId,
                templateId: draft.templateId,
                status: "draft",
                conductedAt: draft.conductedAt,
                accompaniedById: draft.accompaniedById,
                keyPersonnelIds: draft.keyPersonnelIds,
                headerData: draft.headerData,
                token: token
            )
            draft.serverInspectionId = created.id
            saveDraft(draft)
        }
        guard let inspectionId = draft.serverInspectionId else { return }

        // Step 2: create observations
        for index in draft.observations.indices where draft.observations[index].serverId == nil {
            let obs = draft.observations[index]
            let created = try await APIClient.createHseObservation(
                projectId: draft.projectId,
                inspectionId: inspectionId,
                sectionId: obs.sectionId,
                description: obs.descriptionText,
                categoryId: obs.categoryId,
                categoryData: obs.categoryData.isEmpty ? nil : obs.categoryData,
                assignedToId: obs.assignedToId,
                dueDate: obs.dueDate,
                locationId: obs.locationId,
                token: token
            )
            draft.observations[index].serverId = created.id
            saveDraft(draft)
        }

        // Step 3: upload photos
        for obsIndex in draft.observations.indices {
            guard let serverObservationId = draft.observations[obsIndex].serverId else { continue }
            for photoIndex in draft.observations[obsIndex].photos.indices where !draft.observations[obsIndex].photos[photoIndex].uploaded {
                let photo = draft.observations[obsIndex].photos[photoIndex]
                guard let data = photoData(draftId: draft.id, fileName: photo.fileName) else {
                    // File missing (e.g. cleared storage) — skip rather than block the queue.
                    draft.observations[obsIndex].photos[photoIndex].uploaded = true
                    saveDraft(draft)
                    continue
                }
                _ = try await APIClient.uploadHseObservationPhotos(
                    projectId: draft.projectId,
                    observationId: serverObservationId,
                    images: [(data: data, fileName: photo.fileName)],
                    photoType: .observation,
                    latitude: photo.latitude,
                    longitude: photo.longitude,
                    accuracy: photo.accuracy,
                    capturedAt: photo.capturedAt,
                    token: token
                )
                draft.observations[obsIndex].photos[photoIndex].uploaded = true
                saveDraft(draft)
            }
        }

        // Step 4: submit if the user tapped Submit while offline
        if draft.submitRequested {
            do {
                _ = try await APIClient.updateHseInspection(
                    projectId: draft.projectId,
                    inspectionId: inspectionId,
                    status: "submitted",
                    conductedAt: .some(draft.conductedAt),
                    accompaniedById: draft.accompaniedById.map { .some($0) } ?? .some(nil),
                    keyPersonnelIds: draft.keyPersonnelIds,
                    headerData: draft.headerData,
                    token: token
                )
            } catch let error as APIError {
                // Validation failures (e.g. header field made required after
                // capture) leave the report as a server-side draft; don't
                // block the queue — the user can finish it online.
                if case .badRequest(let message) = error {
                    print("OfflineHseInspectionManager: Submit rejected, left as server draft: \(message)")
                    lastSyncError = "Inspection uploaded as draft — submit failed: \(message)"
                } else {
                    throw error
                }
            }
        }

        deleteDraft(draft.id)
        print("OfflineHseInspectionManager: Synced HSE draft \(draft.id) → inspection #\(inspectionId)")
    }
}
