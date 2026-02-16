import SwiftUI
import SwiftData
import WebKit

struct AddProductView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingProducts: [Product]

    @StateObject private var webViewState = WebViewState()
    @State private var scrapedProduct: ScrapedProduct?
    @State private var showPreview = false
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var showDuplicateAlert = false

    // Zara product URLs usually contain "-p" followed by digits (the product ID)
    var isProductPage: Bool {
        guard let url = webViewState.currentURL?.absoluteString else { return false }
        return url.contains("-p") && url.range(of: "\\d{4,}", options: .regularExpression) != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Browser
                WebViewContainer(url: URL(string: "https://www.zara.com/br/")!, state: webViewState)
                    .ignoresSafeArea(edges: .bottom)
                
                // Loading Indicator
                if webViewState.isLoading {
                    VStack {
                        ProgressView()
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                        Spacer()
                    }
                    .padding(.top, 20)
                }

                // Floating Action Button
                if isProductPage {
                    Button(action: analyzeProduct) {
                        HStack(spacing: 12) {
                            if isAnalyzing {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 16))
                                Text("MONITORAR PRODUTO")
                                    .font(.system(size: 14, weight: .bold))
                                    .tracking(1)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 24)
                        .background(
                            Capsule()
                                .fill(Color.black)
                                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        )
                    }
                    .padding(.bottom, 20)
                    .disabled(isAnalyzing)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring, value: isProductPage)
                }
            }
            .navigationTitle(webViewState.pageTitle ?? "Zara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    if webViewState.isLoading {
                        ProgressView()
                    }
                }
            }
            .sheet(isPresented: $showPreview) {
                if let product = scrapedProduct {
                    ProductPreviewSheet(product: product, onSave: saveProduct)
                        .presentationDetents([.height(350)])
                        .presentationDragIndicator(.visible)
                }
            }
            .alert("Erro", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "Erro desconhecido")
            }
            .alert("Produto Duplicado", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Este produto já está sendo monitorado.")
            }
        }
    }

    private func analyzeProduct() {
        guard let webView = webViewState.webView else { return }
        
        isAnalyzing = true
        
        Task {
            do {
                // Use the refactored extraction method on the current webview
                let product = try await ZaraScraper.shared.extractProduct(from: webView)
                
                await MainActor.run {
                    self.scrapedProduct = product
                    self.showPreview = true
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Não foi possível extrair os dados. Tente recarregar a página."
                    self.isAnalyzing = false
                }
            }
        }
    }

    private func saveProduct() {
        guard let scraped = scrapedProduct, let url = webViewState.currentURL?.absoluteString else { return }

        let normalizedURL = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDuplicate = existingProducts.contains {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedURL
        }

        if isDuplicate {
            showDuplicateAlert = true
            showPreview = false
            return
        }

        let newProduct = Product(
            url: url,
            name: scraped.name,
            currentPrice: scraped.price,
            currency: scraped.currency,
            imageURL: scraped.imageURL
        )

        modelContext.insert(newProduct)
        showPreview = false
        dismiss()
    }
}

struct ProductPreviewSheet: View {
    let product: ScrapedProduct
    let onSave: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
            
            Text("Adicionar Produto")
                .font(.headline)
            
            HStack(alignment: .top, spacing: 16) {
                // Image
                if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            Rectangle().fill(Color(.systemGray6))
                        }
                    }
                    .frame(width: 100, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
                } else {
                    Rectangle().fill(Color(.systemGray6))
                        .frame(width: 100, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(product.name)
                        .font(.subheadline)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    Text("\(product.currency) \(String(format: "%.2f", product.price))")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Spacer()
            
            Button(action: onSave) {
                HStack {
                    Spacer()
                    Text("Confirmar e Monitorar")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .padding()
                .background(Color.black)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(.ultraThinMaterial)
    }
}

#Preview {
    AddProductView()
}

// MARK: - WebView Container

class WebViewState: ObservableObject {
    @Published var currentURL: URL?
    @Published var isLoading: Bool = false
    @Published var canGoBack: Bool = false
    @Published var pageTitle: String?
    
    // We keep a weak reference to the webView to run scripts on it
    weak var webView: WKWebView?
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebViewState
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // Privacy: don't save cookies/history
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        webView.allowsBackForwardNavigationGestures = true
        
        // KVO Observation for SPA support
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.url), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.title), options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        
        context.coordinator.webView = webView
        state.webView = webView
        
        webView.load(URLRequest(url: url))
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.url))
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.title))
        uiView.removeObserver(coordinator, forKeyPath: #keyPath(WKWebView.canGoBack))
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var state: WebViewState
        weak var webView: WKWebView?
        
        init(state: WebViewState) {
            self.state = state
        }
        
        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            Task { @MainActor in
                guard let webView = object as? WKWebView else { return }
                if keyPath == #keyPath(WKWebView.url) {
                    state.currentURL = webView.url
                } else if keyPath == #keyPath(WKWebView.title) {
                    state.pageTitle = webView.title
                } else if keyPath == #keyPath(WKWebView.canGoBack) {
                    state.canGoBack = webView.canGoBack
                }
            }
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                state.isLoading = false
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                state.isLoading = false
            }
        }
    }
}

