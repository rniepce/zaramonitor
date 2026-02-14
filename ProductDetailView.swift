import SwiftUI
import SwiftData
import Charts

struct ProductDetailView: View {
    @Bindable var product: Product
    @Environment(\.openURL) var openURL
    @State private var isRefreshing = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { image in
                            image.resizable()
                                 .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 80, height: 100)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(product.name)
                            .font(.headline)
                        
                        Text(product.currentPrice, format: .currency(code: "BRL"))
                            .font(.title2)
                            .bold()
                            .foregroundColor(product.targetPrice != nil && product.currentPrice <= product.targetPrice! ? .green : .primary)
                    }
                }
                
                Button("View on Zara Website") {
                    if let url = URL(string: product.url) {
                        openURL(url)
                    }
                }
            }
            
            Section(header: Text("Settings")) {
                Toggle("Monitoring Active", isOn: $product.isMonitoring)
                
                HStack {
                    Text("Target Price")
                    Spacer()
                    TextField("Target", value: $product.targetPrice, format: .currency(code: "BRL"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }
            
            Section(header: Text("Price History")) {
                if product.priceHistory.isEmpty {
                    Text("No history yet.")
                } else {
                    // Simple chart using Swift Charts if available, or just a list
                    Chart(product.priceHistory) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.price)
                        )
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Price", point.price)
                        )
                    }
                    .frame(height: 150)
                    .padding(.vertical)
                    
                    ForEach(product.priceHistory.sorted(by: { $0.date > $1.date }), id: \.date) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .shortened))
                            Spacer()
                            Text(point.price, format: .currency(code: "BRL"))
                        }
                    }
                }
            }
            
            Section {
                Button(action: refreshPrice) {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Text("Refresh Price Now")
                    }
                }
                .disabled(isRefreshing)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func refreshPrice() {
        isRefreshing = true
        Task {
            do {
                let scraped = try await ZaraScraper.shared.fetchProduct(url: product.url)
                await MainActor.run {
                    if scraped.price != product.currentPrice {
                        product.addPricePoint(price: scraped.price)
                        product.imageURL = scraped.imageURL // Update image if changed
                    }
                    product.lastChecked = Date()
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    // Show error?
                }
            }
        }
    }
}
