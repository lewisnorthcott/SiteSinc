import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Model") // Matches your Model.xcdatamodeld
        
        // Configure store description to disable CloudKit sync
        // This prevents CloudKit integration errors since we're only using Core Data for local caching
        if let storeDescription = container.persistentStoreDescriptions.first {
            storeDescription.setOption(false as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(false as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            // Explicitly disable CloudKit
            storeDescription.cloudKitContainerOptions = nil
        }
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Log error but don't crash - allow app to continue with degraded functionality
                print("⚠️ Core Data store failed to load: \(error), \(error.userInfo)")
                print("⚠️ This may cause issues with offline project caching")
                // Don't use fatalError - it causes app crashes and slow startup
                // Instead, log the error and continue
            } else {
                print("✅ Core Data store loaded successfully")
            }
        })
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // Preview provider for SwiftUI Previews
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        // Add any sample data for previews here if needed
        // For example:
        // if try! viewContext.fetch(CDProject.fetchRequest()).isEmpty { // Example check
        //     for i in 0..<5 { // Create 5 sample projects
        //         let newItem = CDProject(context: viewContext)
        //         newItem.id = Int64(i)
        //         newItem.name = "Preview Project \(i)"
        //         newItem.isAvailableOffline = (i % 2 == 0)
        //         newItem.projectStatus = "Active"
        //         newItem.reference = "REF00\(i)"
        //     }
        //     do {
        //         try viewContext.save()
        //     } catch {
        //         let nsError = error as NSError
        //         fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        //     }
        // }
        return result
    }()

    // Function to save changes
    func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                // Consider more robust error handling for production
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
} 