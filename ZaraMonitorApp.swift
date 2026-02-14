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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .backgroundTask(.appRefresh(BackgroundManager.taskId)) {
            let actor = BackgroundRefreshActor(modelContainer: sharedModelContainer)
            await actor.refreshAllProducts()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                BackgroundManager.shared.scheduleAppRefresh()
            }
        }
    }
}
