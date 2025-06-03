import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Model") // Matches your Model.xcdatamodeld
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate.
                // You should not use this function in a shipping application, although it may be useful during development.
                fatalError("Unresolved error \(error), \(error.userInfo)")
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