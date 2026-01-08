import Foundation
import Combine
import Network

// MARK: - Offline Inspection Models

struct OfflineInspection: Codable, Identifiable {
    let id: String
    let projectId: Int
    let projectInspectionTemplateId: Int
    let inspectionNumber: Int
    let locationId: Int
    let locationName: String?
    let assignedToId: Int?
    let managerId: Int?
    let notes: String?
    let createdAt: Date
    let token: String
}

struct CachedInspectionData: Codable {
    let inspections: [Inspection]
    let cachedAt: Date
    let projectId: Int
}

// MARK: - OfflineInspectionManager

@MainActor
class OfflineInspectionManager: ObservableObject {
    static let shared = OfflineInspectionManager()
    
    @Published var pendingInspections: [OfflineInspection] = []
    @Published var syncInProgress = false
    @Published var lastSyncError: String?
    @Published var isOffline = false
    
    private var cancellables = Set<AnyCancellable>()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sitesinc.offlineInspectionManager")
    
    private init() {
        loadPendingItems()
        setupNetworkMonitoring()
    }
    
    // MARK: - Computed Properties
    
    var pendingInspectionsCount: Int {
        return pendingInspections.count
    }
    
    var totalPendingCount: Int {
        return pendingInspectionsCount
    }
    
    // MARK: - Directory Management
    
    private var inspectionsDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let inspectionsURL = paths[0].appendingPathComponent("offline_inspections")
        if !FileManager.default.fileExists(atPath: inspectionsURL.path) {
            try? FileManager.default.createDirectory(at: inspectionsURL, withIntermediateDirectories: true, attributes: nil)
        }
        return inspectionsURL
    }
    
    private var cacheDirectory: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let cacheURL = paths[0].appendingPathComponent("inspection_cache")
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        return cacheURL
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied
                
                if wasOffline && path.status == .satisfied {
                    print("OfflineInspectionManager: Network connection restored")
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    self?.syncPendingItems()
                } else if path.status != .satisfied {
                    print("OfflineInspectionManager: Network connection lost")
                }
            }
        }
        monitor.start(queue: queue)
    }
    
    // MARK: - Inspection Caching (for offline viewing)
    
    func cacheInspections(_ inspections: [Inspection], forProject projectId: Int) {
        Task.detached {
            let cachedData = CachedInspectionData(inspections: inspections, cachedAt: Date(), projectId: projectId)
            let fileURL = await self.cacheDirectory.appendingPathComponent("project_\(projectId)_inspections.json")
            
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(cachedData)
                try data.write(to: fileURL)
                print("OfflineInspectionManager: Cached \(inspections.count) inspections for project \(projectId)")
            } catch {
                print("OfflineInspectionManager: Failed to cache inspections: \(error)")
            }
        }
    }
    
    func getCachedInspections(forProject projectId: Int) -> [Inspection]? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_inspections.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cachedData = try decoder.decode(CachedInspectionData.self, from: data)
            
            // Check if cache is still valid (24 hours)
            let cacheAge = Date().timeIntervalSince(cachedData.cachedAt)
            if cacheAge > 86400 { // 24 hours
                print("OfflineInspectionManager: Cache expired for project \(projectId)")
                return nil
            }
            
            print("OfflineInspectionManager: Loaded \(cachedData.inspections.count) cached inspections for project \(projectId)")
            return cachedData.inspections
        } catch {
            print("OfflineInspectionManager: Failed to decode cached inspections: \(error)")
            return nil
        }
    }
    
    func getCacheAge(forProject projectId: Int) -> Date? {
        let fileURL = cacheDirectory.appendingPathComponent("project_\(projectId)_inspections.json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let cachedData = try? JSONDecoder().decode(CachedInspectionData.self, from: data) else {
            return nil
        }
        
        return cachedData.cachedAt
    }
    
    // MARK: - Pending Inspection Management
    
    func saveInspection(_ inspection: OfflineInspection) {
        pendingInspections.append(inspection)
        
        Task.detached {
            let fileURL = await self.inspectionsDirectory.appendingPathComponent("\(inspection.id).json")
            do {
                let data = try JSONEncoder().encode(inspection)
                try data.write(to: fileURL)
                print("OfflineInspectionManager: Saved inspection offline: \(inspection.id)")
            } catch {
                print("OfflineInspectionManager: Failed to save inspection offline: \(error)")
            }
        }
    }
    
    private func loadPendingItems() {
        Task {
            // Load pending inspections
            let inspections = await Task.detached {
                let fileURLs = (try? FileManager.default.contentsOfDirectory(
                    at: await self.inspectionsDirectory,
                    includingPropertiesForKeys: nil
                )) ?? []
                
                return fileURLs.compactMap { url -> OfflineInspection? in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? JSONDecoder().decode(OfflineInspection.self, from: data)
                }
            }.value
            
            await MainActor.run {
                self.pendingInspections = inspections
                print("OfflineInspectionManager: Loaded \(inspections.count) pending inspections")
            }
        }
    }
    
    // MARK: - Sync
    
    func manualSync() {
        print("OfflineInspectionManager: Manual sync triggered")
        syncPendingItems()
    }
    
    private func syncPendingItems() {
        guard !syncInProgress else {
            print("OfflineInspectionManager: Sync already in progress")
            return
        }
        
        guard !pendingInspections.isEmpty else {
            print("OfflineInspectionManager: No pending items to sync")
            return
        }
        
        syncInProgress = true
        lastSyncError = nil
        
        Task {
            var successCount = 0
            var errorCount = 0
            
            // Sync pending inspections
            for inspection in pendingInspections {
                do {
                    try await syncInspection(inspection)
                    await removePendingInspection(inspection)
                    successCount += 1
                } catch {
                    print("OfflineInspectionManager: Failed to sync inspection \(inspection.id): \(error)")
                    errorCount += 1
                }
            }
            
            await MainActor.run {
                self.syncInProgress = false
                
                if errorCount > 0 {
                    self.lastSyncError = "Failed to sync \(errorCount) item(s)"
                }
                
                print("OfflineInspectionManager: Sync complete. Inspections: \(successCount) success, \(errorCount) errors")
            }
        }
    }
    
    private func syncInspection(_ offlineInspection: OfflineInspection) async throws {
        // Create the inspection request
        let inspectionData = CreateInspectionRequest(
            projectInspectionTemplateId: offlineInspection.projectInspectionTemplateId,
            locationId: offlineInspection.locationId,
            assignedToId: offlineInspection.assignedToId,
            managerId: offlineInspection.managerId,
            notes: offlineInspection.notes
        )
        
        // Submit to API
        _ = try await APIClient.createInspection(
            projectId: offlineInspection.projectId,
            inspectionData: inspectionData,
            token: offlineInspection.token
        )
        print("OfflineInspectionManager: Successfully synced inspection: #\(offlineInspection.inspectionNumber)")
    }
    
    private func removePendingInspection(_ inspection: OfflineInspection) async {
        await MainActor.run {
            pendingInspections.removeAll { $0.id == inspection.id }
        }
        
        let fileURL = inspectionsDirectory.appendingPathComponent("\(inspection.id).json")
        try? FileManager.default.removeItem(at: fileURL)
        print("OfflineInspectionManager: Removed synced inspection: \(inspection.id)")
    }
    
    // MARK: - Delete Pending Items
    
    func deletePendingInspection(_ inspection: OfflineInspection) {
        pendingInspections.removeAll { $0.id == inspection.id }
        
        let fileURL = inspectionsDirectory.appendingPathComponent("\(inspection.id).json")
        try? FileManager.default.removeItem(at: fileURL)
        print("OfflineInspectionManager: Deleted pending inspection: \(inspection.id)")
    }
}



