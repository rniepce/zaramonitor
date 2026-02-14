import Foundation

enum ScraperError: Error {
    case invalidURL
    case noData
    case parsingError
}

class ZaraScraper {
    static let shared = ZaraScraper()
    
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        // Zara might block generic user agents, so let's spoof a real iPhone
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        self.session = URLSession(configuration: config)
    }
    
    func fetchProduct(url: String) async throws -> ScrapedProduct {
        guard let validURL = URL(string: url) else {
            throw ScraperError.invalidURL
        }
        
        let (data, response) = try await session.data(from: validURL)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ScraperError.noData
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw ScraperError.parsingError
        }
        
        return try parseHTML(html)
    }
    
    private func parseHTML(_ html: String) throws -> ScrapedProduct {
        // Zara usually embeds product data in a schema.org JSON-LD script or a window.__ZARA_APP_INITIAL_STATE__
        // Strategy 1: Look for schema.org Product JSON
        // Regex to find <script type="application/ld+json">...</script>
        
        // Simplified parsing logic for demonstration. In a real app, swift-soup is better, but we want zero dependencies.
        
        // Attempt to find Name
        // <h1 class="product-detail-info__header-name">...</h1> or similar
        // Fallback to title tag
        var name = "Unknown Product"
        if let titleRange = html.range(of: "<title>"), let endTitleRange = html.range(of: "</title>", range: titleRange.upperBound..<html.endIndex) {
            let title = html[titleRange.upperBound..<endTitleRange.lowerBound]
            name = String(title).replacingOccurrences(of: " | ZARA Brazil", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Attempt to find Price
        // Often found in meta property="product:price:amount" content="123.45"
        var price = 0.0
        if let priceRange = html.range(of: "product:price:amount\" content=\"") {
            let searchRegion = priceRange.upperBound..<html.endIndex
            if let endQuote = html.range(of: "\"", range: searchRegion) {
                let priceString = html[priceRange.upperBound..<endQuote.lowerBound]
                price = Double(priceString) ?? 0.0
            }
        } else {
            // Plan B: specific Zara JSON search
             if let jsonStart = html.range(of: "\"price\":"), let jsonEnd = html.range(of: ",", range: jsonStart.upperBound..<html.endIndex) {
                 let priceVal = html[jsonStart.upperBound..<jsonEnd.lowerBound]
                 // Clean up string like "123" or "123.0"
                 price = Double(priceVal.trimmingCharacters(in: CharacterSet(charactersIn: " \":"))) ?? 0.0
             }
        }
        
        // Attempt to find Image
        var imageUrl: String? = nil
        if let imageRange = html.range(of: "og:image\" content=\"") {
            let searchRegion = imageRange.upperBound..<html.endIndex
            if let endQuote = html.range(of: "\"", range: searchRegion) {
                imageUrl = String(html[imageRange.upperBound..<endQuote.lowerBound])
            }
        }

        return ScrapedProduct(name: name, price: price, currency: "BRL", imageURL: imageUrl)
    }
}

struct ScrapedProduct {
    let name: String
    let price: Double
    let currency: String
    let imageURL: String?
}
