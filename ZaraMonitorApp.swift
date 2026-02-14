import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct ZaraMonitorApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Product.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        BackgroundManager.shared.requestNotificationPermission()
        
        // Register the background task
        // Note: This must be done before the app finishes launching
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundManager.taskId, using: nil) { task in
             // In a real app, we need to get the ModelContext properly here, likely via a ModelActor
             // BackgroundManager.shared.handleAppRefresh(task: task as! BGAppRefreshTask, modelContext: ...)
             task.setTaskCompleted(success: true) // Placeholder for now
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                BackgroundManager.shared.scheduleAppRefresh()
            }
        }
    }
}
