import Foundation
import BackgroundTasks
import UserNotifications
import SwiftData

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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // Fetch no earlier than 1 hour
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    func handleAppRefresh(task: BGAppRefreshTask, modelContext: ModelContext) {
        scheduleAppRefresh() // Schedule next refresh
        
        task.expirationHandler = {
            // Task expired, cancel operations
        }
        
        Task {
            // Fetch all monitored products
            // In a real app, we need to fetch from ModelContext safely
            // Since SwiftData actors are tricky in background tasks, we assume we can fetch here
            
            // NOTE: This part requires careful handling in a real app with ModelActor
            // For simplicity, we outline the logic
            
            /*
            let descriptor = FetchDescriptor<Product>(predicate: #Predicate { $0.isMonitoring })
            let products = try? modelContext.fetch(descriptor)
            
            for product in products ?? [] {
                if let scraped = try? await ZaraScraper.shared.fetchProduct(url: product.url) {
                     if scraped.price < product.currentPrice {
                         // Price Drop!
                         sendNotification(itemName: product.name, oldPrice: product.currentPrice, newPrice: scraped.price)
                         product.currentPrice = scraped.price
                         product.addPricePoint(price: scraped.price)
                     }
                }
            }
            */
            
            // Simulating completion
            task.setTaskCompleted(success: true)
        }
    }
    
    func sendNotification(itemName: String, oldPrice: Double, newPrice: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Price Drop Alert!"
        content.body = "\(itemName) dropped from \(oldPrice) to \(newPrice)!"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
