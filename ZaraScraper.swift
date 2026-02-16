import Foundation
import WebKit

enum ScraperError: Error, LocalizedError {
    case invalidURL
    case noData
    case parsingError
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL inválida"
        case .noData: return "Sem dados"
        case .parsingError: return "Erro ao extrair dados"
        case .timeout: return "Tempo esgotado"
        }
    }
}

struct ScrapedProduct {
    let name: String
    let price: Double
    let currency: String
    let imageURL: String?
}

// MARK: - WKWebView-based Scraper (runs on MainActor)

@MainActor
class ZaraScraper: NSObject {
    static let shared = ZaraScraper()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<ScrapedProduct, Error>?
    private var timeoutTask: Task<Void, Never>?

    /// Number of seconds to wait for page + JS to fully render
    private let pageLoadTimeout: TimeInterval = 20
    /// Extra delay after page load to wait for client-side rendering
    private let renderDelay: TimeInterval = 5

    // MARK: - Public API

    func fetchProduct(url: String) async throws -> ScrapedProduct {
        guard let _ = URL(string: url) else { throw ScraperError.invalidURL }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.loadPage(urlString: url)
        }
    }

    // MARK: - Private

    private func loadPage(urlString: String) {
        // Clean up any previous webview
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        let config = WKWebViewConfiguration()
        // Use a non-persistent data store so we don't leave cookies
        config.websiteDataStore = .nonPersistent()

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.navigationDelegate = self

        // Use a realistic mobile user-agent
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        self.webView = wv

        // Start timeout timer
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(20 * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.handleTimeout()
        }

        let request = URLRequest(url: URL(string: urlString)!, cachePolicy: .reloadIgnoringLocalCacheData)
        wv.load(request)
    }

    private func handleTimeout() {
        // Even on timeout, try to extract whatever we have
        extractProductData()
    }

    private func extractProductData() {
        guard let wv = webView else {
            finishWith(error: ScraperError.noData)
            return
        }

        // JavaScript with robust extraction — prioritizes JSON-LD, then DOM selectors
        let js = """
        (function() {
            var result = { name: '', price: 0, currency: 'BRL', imageURL: '' };

            // Helper: parse Brazilian price text like "R$ 1.299,90" or "519,00"
            function parseBRLPrice(text) {
                if (!text) return 0;
                // Remove currency symbols and whitespace
                var cleaned = text.replace(/R\\$|BRL/gi, '').trim();
                // Handle Brazilian format: 1.299,90 -> 1299.90
                // Remove thousands separator (dots) then replace decimal comma with dot
                cleaned = cleaned.replace(/\\./g, '').replace(',', '.');
                var val = parseFloat(cleaned);
                return (isNaN(val) || val <= 0) ? 0 : val;
            }

            // ===== STRATEGY 1: JSON-LD (most reliable) =====
            var scripts = document.querySelectorAll('script[type="application/ld+json"]');
            for (var i = 0; i < scripts.length; i++) {
                try {
                    var raw = JSON.parse(scripts[i].textContent);
                    // Handle both direct objects and arrays
                    var items = Array.isArray(raw) ? raw : [raw];
                    for (var j = 0; j < items.length; j++) {
                        var json = items[j];
                        if (json['@type'] === 'Product') {
                            // Name
                            if (json.name) result.name = json.name;
                            // Image
                            if (json.image) {
                                result.imageURL = Array.isArray(json.image) ? json.image[0] : json.image;
                            }
                            // Offers — can be object or array
                            if (json.offers) {
                                var offersList = Array.isArray(json.offers) ? json.offers : [json.offers];
                                for (var k = 0; k < offersList.length; k++) {
                                    var offer = offersList[k];
                                    // Handle AggregateOffer
                                    if (offer['@type'] === 'AggregateOffer') {
                                        var p = parseFloat(offer.lowPrice || offer.price);
                                        if (p > 0) { result.price = p; break; }
                                    }
                                    var p = parseFloat(offer.price);
                                    if (p > 0) {
                                        result.price = p;
                                        if (offer.priceCurrency) result.currency = offer.priceCurrency;
                                        break;
                                    }
                                }
                            }
                        }
                    }
                } catch(e) {}
            }

            // ===== STRATEGY 2: DOM selectors for price =====
            if (result.price === 0) {
                // Zara's current price selectors (2024-2025)
                var selectors = [
                    '.money-amount__main',
                    '.price-current__amount',
                    '.price__amount',
                    '[data-qa-qualifier="product-price-amount"]',
                    '.product-detail-info__header-price .money-amount__main',
                    '.price span'
                ];
                for (var i = 0; i < selectors.length; i++) {
                    var el = document.querySelector(selectors[i]);
                    if (el) {
                        var p = parseBRLPrice(el.innerText);
                        if (p > 0) { result.price = p; break; }
                    }
                }
            }

            // ===== STRATEGY 3: meta tags =====
            if (result.price === 0) {
                var metaPrice = document.querySelector('meta[property="product:price:amount"]');
                if (metaPrice) {
                    result.price = parseFloat(metaPrice.getAttribute('content')) || 0;
                }
            }

            // ===== STRATEGY 4: Regex scan for R$ patterns =====
            if (result.price === 0) {
                var allElements = document.querySelectorAll('span, p, div');
                for (var i = 0; i < Math.min(allElements.length, 500); i++) {
                    var text = allElements[i].innerText;
                    if (!text || text.length > 50) continue;
                    var match = text.match(/R\\$\\s*([0-9]{1,3}(?:\\.[0-9]{3})*,[0-9]{2})/);
                    if (match) {
                        var p = parseBRLPrice(match[0]);
                        if (p > 0 && p < 50000) {
                            result.price = p;
                            break;
                        }
                    }
                }
            }

            // ===== NAME fallbacks =====
            if (!result.name || result.name.length === 0) {
                var h1 = document.querySelector('h1');
                if (h1 && h1.innerText.trim().length > 0) {
                    result.name = h1.innerText.trim();
                }
            }
            if (!result.name || result.name.length === 0) {
                var ogTitle = document.querySelector('meta[property="og:title"]');
                if (ogTitle) result.name = ogTitle.getAttribute('content') || '';
            }
            if (!result.name || result.name.length === 0) {
                result.name = document.title.replace(/\\s*[|\\-].*$/, '').trim();
            }

            // ===== IMAGE fallbacks =====
            if (!result.imageURL || result.imageURL.length === 0) {
                var ogImage = document.querySelector('meta[property="og:image"]');
                if (ogImage) result.imageURL = ogImage.getAttribute('content') || '';
            }
            if (!result.imageURL || result.imageURL.length === 0) {
                var imgs = document.querySelectorAll('img[src*="static.zara"], img[src*="zara.com"], picture img');
                for (var i = 0; i < imgs.length; i++) {
                    var src = imgs[i].src || '';
                    if (src.length > 10 && !src.includes('logo') && !src.includes('icon')) {
                        result.imageURL = src.split(' ')[0];
                        break;
                    }
                }
            }

            // ===== CURRENCY =====
            if (result.currency === 'BRL') {
                var metaCurrency = document.querySelector('meta[property="product:price:currency"]');
                if (metaCurrency) result.currency = metaCurrency.getAttribute('content') || 'BRL';
            }

            return JSON.stringify(result);
        })();
        """

        wv.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self else { return }

            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let name = dict["name"] as? String ?? "Produto Zara"
                let price = dict["price"] as? Double ?? 0.0
                let currency = dict["currency"] as? String ?? "BRL"
                let imageURL = dict["imageURL"] as? String

                let product = ScrapedProduct(
                    name: name.isEmpty ? "Produto Zara" : name,
                    price: price,
                    currency: currency,
                    imageURL: (imageURL?.isEmpty ?? true) ? nil : imageURL
                )

                self.finishWith(product: product)
            } else {
                self.finishWith(error: ScraperError.parsingError)
            }
        }
    }

    private func finishWith(product: ScrapedProduct) {
        cleanup()
        continuation?.resume(returning: product)
        continuation = nil
    }

    private func finishWith(error: Error) {
        cleanup()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    private func cleanup() {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
    }
}

// MARK: - WKNavigationDelegate

extension ZaraScraper: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait a bit for client-side JS to render product data
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(self.renderDelay * 1_000_000_000))
            self.timeoutTask?.cancel()
            self.extractProductData()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.finishWith(error: ScraperError.noData)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.finishWith(error: ScraperError.noData)
        }
    }
}

// MARK: - Public JS Extraction Logic (for external use)

extension ZaraScraper {
    /// Extracts product data from any given WKWebView instance.
    func extractProduct(from webView: WKWebView) async throws -> ScrapedProduct {
        return try await withCheckedThrowingContinuation { continuation in
            evaluateExtractionScript(on: webView) { result in
                switch result {
                case .success(let product):
                    continuation.resume(returning: product)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func evaluateExtractionScript(on webView: WKWebView, completion: @escaping (Result<ScrapedProduct, Error>) -> Void) {
        webView.evaluateJavaScript(Self.extractionScript) { result, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let jsonString = result as? String,
               let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                
                let name = dict["name"] as? String ?? "Produto Zara"
                let price = dict["price"] as? Double ?? 0.0
                let currency = dict["currency"] as? String ?? "BRL"
                let imageURL = dict["imageURL"] as? String
                
                let product = ScrapedProduct(
                    name: name.isEmpty ? "Produto Zara" : name,
                    price: price,
                    currency: currency,
                    imageURL: (imageURL?.isEmpty ?? true) ? nil : imageURL
                )
                
                completion(.success(product))
            } else {
                completion(.failure(ScraperError.parsingError))
            }
        }
    }

    /// The JavaScript code used to extract product data.
    static let extractionScript = """
    (function() {
        var result = { name: '', price: 0, currency: 'BRL', imageURL: '' };

        // Helper: parse Brazilian price text like "R$ 1.299,90" or "519,00"
        function parseBRLPrice(text) {
            if (!text) return 0;
            // Remove currency symbols and whitespace
            var cleaned = text.replace(/R\\$|BRL/gi, '').trim();
            // Handle Brazilian format: 1.299,90 -> 1299.90
            // Remove thousands separator (dots) then replace decimal comma with dot
            cleaned = cleaned.replace(/\\./g, '').replace(',', '.');
            var val = parseFloat(cleaned);
            return (isNaN(val) || val <= 0) ? 0 : val;
        }

        // ===== STRATEGY 1: JSON-LD (most reliable) =====
        var scripts = document.querySelectorAll('script[type="application/ld+json"]');
        for (var i = 0; i < scripts.length; i++) {
            try {
                var raw = JSON.parse(scripts[i].textContent);
                // Handle both direct objects and arrays
                var items = Array.isArray(raw) ? raw : [raw];
                for (var j = 0; j < items.length; j++) {
                    var json = items[j];
                    if (json['@type'] === 'Product') {
                        // Name
                        if (json.name) result.name = json.name;
                        // Image
                        if (json.image) {
                            result.imageURL = Array.isArray(json.image) ? json.image[0] : json.image;
                        }
                        // Offers — can be object or array
                        if (json.offers) {
                            var offersList = Array.isArray(json.offers) ? json.offers : [json.offers];
                            for (var k = 0; k < offersList.length; k++) {
                                var offer = offersList[k];
                                // Handle AggregateOffer
                                if (offer['@type'] === 'AggregateOffer') {
                                    var p = parseFloat(offer.lowPrice || offer.price);
                                    if (p > 0) { result.price = p; break; }
                                }
                                var p = parseFloat(offer.price);
                                if (p > 0) {
                                    result.price = p;
                                    if (offer.priceCurrency) result.currency = offer.priceCurrency;
                                    break;
                                }
                            }
                        }
                    }
                }
            } catch(e) {}
        }

        // ===== STRATEGY 2: DOM selectors for price =====
        if (result.price === 0) {
            // Zara's current price selectors (2024-2025)
            var selectors = [
                '.money-amount__main',
                '.price-current__amount',
                '.price__amount',
                '[data-qa-qualifier="product-price-amount"]',
                '.product-detail-info__header-price .money-amount__main',
                '.price span'
            ];
            for (var i = 0; i < selectors.length; i++) {
                var el = document.querySelector(selectors[i]);
                if (el) {
                    var p = parseBRLPrice(el.innerText);
                    if (p > 0) { result.price = p; break; }
                }
            }
        }

        // ===== STRATEGY 3: meta tags =====
        if (result.price === 0) {
            var metaPrice = document.querySelector('meta[property="product:price:amount"]');
            if (metaPrice) {
                result.price = parseFloat(metaPrice.getAttribute('content')) || 0;
            }
        }

        // ===== STRATEGY 4: Regex scan for R$ patterns =====
        if (result.price === 0) {
            var allElements = document.querySelectorAll('span, p, div');
            for (var i = 0; i < Math.min(allElements.length, 500); i++) {
                var text = allElements[i].innerText;
                if (!text || text.length > 50) continue;
                var match = text.match(/R\\$\\s*([0-9]{1,3}(?:\\.[0-9]{3})*,[0-9]{2})/);
                if (match) {
                    var p = parseBRLPrice(match[0]);
                    if (p > 0 && p < 50000) {
                        result.price = p;
                        break;
                    }
                }
            }
        }

        // ===== NAME fallbacks =====
        if (!result.name || result.name.length === 0) {
            var h1 = document.querySelector('h1');
            if (h1 && h1.innerText.trim().length > 0) {
                result.name = h1.innerText.trim();
            }
        }
        if (!result.name || result.name.length === 0) {
            var ogTitle = document.querySelector('meta[property="og:title"]');
            if (ogTitle) result.name = ogTitle.getAttribute('content') || '';
        }
        if (!result.name || result.name.length === 0) {
            result.name = document.title.replace(/\\s*[|\\-].*$/, '').trim();
        }

        // ===== IMAGE fallbacks =====
        if (!result.imageURL || result.imageURL.length === 0) {
            var ogImage = document.querySelector('meta[property="og:image"]');
            if (ogImage) result.imageURL = ogImage.getAttribute('content') || '';
        }
        if (!result.imageURL || result.imageURL.length === 0) {
            var imgs = document.querySelectorAll('img[src*="static.zara"], img[src*="zara.com"], picture img');
            for (var i = 0; i < imgs.length; i++) {
                var src = imgs[i].src || '';
                if (src.length > 10 && !src.includes('logo') && !src.includes('icon')) {
                    result.imageURL = src.split(' ')[0];
                    break;
                }
            }
        }

        // ===== CURRENCY =====
        if (result.currency === 'BRL') {
            var metaCurrency = document.querySelector('meta[property="product:price:currency"]');
            if (metaCurrency) result.currency = metaCurrency.getAttribute('content') || 'BRL';
        }

        return JSON.stringify(result);
    })();
    """
}

