import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

// ModelActor for safe SwiftData access from background tasks
@ModelActor
actor BackgroundRefreshActor {
    func refreshAllProducts() async {
        let descriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.isMonitoring }
        )
        
        guard let products = try? modelContext.fetch(descriptor) else { return }
        
        for product in products {
            do {
                let scraped = try await ZaraScraper.shared.fetchProduct(url: product.url)
                
                if scraped.price != product.currentPrice {
                    let oldPrice = product.currentPrice
                    product.addPricePoint(price: scraped.price)
                    
                    // Update image if changed
                    if let newImage = scraped.imageURL {
                        product.imageURL = newImage
                    }
                    
                    // Notify on price drop
                    if scraped.price < oldPrice {
                        BackgroundManager.shared.sendNotification(
                            itemName: product.name,
                            oldPrice: oldPrice,
                            newPrice: scraped.price
                        )
                    }
                } else {
                    // Price unchanged, just update lastChecked
                    product.lastChecked = Date()
                }
            } catch {
                print("Failed to refresh \(product.name): \(error.localizedDescription)")
            }
        }
        
        try? modelContext.save()
    }
}

class BackgroundManager {
    static let shared = BackgroundManager()
    static let taskId = "com.zara.monitor.refresh"
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission denied: \(error.localizedDescription)")
            }
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour minimum
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    func handleAppRefresh(task: BGAppRefreshTask, modelContainer: ModelContainer) {
        // Schedule the next refresh immediately
        scheduleAppRefresh()
        
        let refreshTask = Task {
            let actor = BackgroundRefreshActor(modelContainer: modelContainer)
            await actor.refreshAllProducts()
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
    
    func sendNotification(itemName: String, oldPrice: Double, newPrice: Double) {
        let savings = oldPrice - newPrice
        let content = UNMutableNotificationContent()
        content.title = "💰 Preço Caiu!"
        content.body = "\(itemName): R$ \(String(format: "%.2f", oldPrice)) → R$ \(String(format: "%.2f", newPrice)) (economize R$ \(String(format: "%.2f", savings)))"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
