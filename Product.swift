import Foundation
import SwiftData

@Model
final class Product {
    var id: UUID
    var url: String
    var name: String
    var currentPrice: Double
    var initialPrice: Double
    var targetPrice: Double?
    var imageURL: String?
    var currency: String
    var lastChecked: Date
    var isMonitoring: Bool
    var priceHistory: [PricePoint]

    init(url: String, name: String = "Unknown Item", currentPrice: Double = 0.0, currency: String = "BRL", targetPrice: Double? = nil, imageURL: String? = nil) {
        self.id = UUID()
        self.url = url
        self.name = name
        self.currentPrice = currentPrice
        self.initialPrice = currentPrice
        self.currency = currency
        self.targetPrice = targetPrice
        self.imageURL = imageURL
        self.lastChecked = Date()
        self.isMonitoring = true
        self.priceHistory = []
        
        // Add initial history point
        addPricePoint(price: currentPrice)
    }
    
    func addPricePoint(price: Double) {
        let point = PricePoint(price: price, date: Date())
        self.priceHistory.append(point)
        self.currentPrice = price
        self.lastChecked = Date()
    }
    
    /// Percentage change from initial price. Negative = price dropped.
    var priceChangePercent: Double {
        guard initialPrice > 0 else { return 0 }
        return ((currentPrice - initialPrice) / initialPrice) * 100.0
    }
    
    /// Absolute change from initial price. Negative = price dropped.
    var priceChangeAbsolute: Double {
        return currentPrice - initialPrice
    }
}

@Model
final class PricePoint {
    var price: Double
    var date: Date
    
    init(price: Double, date: Date) {
        self.price = price
        self.date = date
    }
}
