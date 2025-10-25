import Foundation

class RecentDrawingsManager: ObservableObject {
    static let shared = RecentDrawingsManager()
    private let userDefaults = UserDefaults.standard
    private let maxRecentCount = 5 // Maximum number of recent drawings to keep per project
    
    @Published private(set) var recentDrawingsByProject: [Int: [RecentDrawing]] = [:]
    
    private init() {
        loadRecentDrawings()
    }
    
    struct RecentDrawing: Codable, Identifiable, Equatable {
        let id: Int
        let title: String
        let number: String
        let projectId: Int
        let lastAccessedAt: Date
        let thumbnailUrl: String?
        
        static func == (lhs: RecentDrawing, rhs: RecentDrawing) -> Bool {
            return lhs.id == rhs.id
        }
    }
    
    func trackDrawingAccess(drawing: Drawing) {
        let recentDrawing = RecentDrawing(
            id: drawing.id,
            title: drawing.title,
            number: drawing.number,
            projectId: drawing.projectId,
            lastAccessedAt: Date(),
            thumbnailUrl: nil // We can add thumbnail support later if needed
        )
        
        // Get current recent drawings for this project
        var projectRecents = recentDrawingsByProject[drawing.projectId] ?? []
        
        // Remove existing entry if it exists
        projectRecents.removeAll { $0.id == drawing.id }
        
        // Add to the beginning
        projectRecents.insert(recentDrawing, at: 0)
        
        // Keep only the most recent items
        if projectRecents.count > maxRecentCount {
            projectRecents = Array(projectRecents.prefix(maxRecentCount))
        }
        
        // Update the dictionary
        recentDrawingsByProject[drawing.projectId] = projectRecents
        
        // Save to UserDefaults
        saveRecentDrawings()
        
        print("RecentDrawingsManager: Tracked access to drawing '\(drawing.title)' (ID: \(drawing.id)) for project \(drawing.projectId)")
    }
    
    func getRecentDrawings(for projectId: Int) -> [RecentDrawing] {
        return recentDrawingsByProject[projectId] ?? []
    }
    
    func clearRecentDrawings(for projectId: Int) {
        recentDrawingsByProject[projectId] = []
        saveRecentDrawings()
        print("RecentDrawingsManager: Cleared recent drawings for project \(projectId)")
    }
    
    func clearAllRecentDrawings() {
        recentDrawingsByProject.removeAll()
        saveRecentDrawings()
        print("RecentDrawingsManager: Cleared all recent drawings")
    }
    
    private func saveRecentDrawings() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(recentDrawingsByProject)
            userDefaults.set(data, forKey: "recentDrawingsByProject")
            print("RecentDrawingsManager: Saved recent drawings to UserDefaults")
        } catch {
            print("RecentDrawingsManager: Failed to save recent drawings: \(error.localizedDescription)")
        }
    }
    
    private func loadRecentDrawings() {
        guard let data = userDefaults.data(forKey: "recentDrawingsByProject") else {
            print("RecentDrawingsManager: No saved recent drawings found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            recentDrawingsByProject = try decoder.decode([Int: [RecentDrawing]].self, from: data)
            print("RecentDrawingsManager: Loaded recent drawings from UserDefaults")
        } catch {
            print("RecentDrawingsManager: Failed to load recent drawings: \(error.localizedDescription)")
            recentDrawingsByProject = [:]
        }
    }
}
