import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var products: [Product]
    @State private var showingAddProduct = false
    @State private var isRefreshingAll = false

    /// Products sorted by biggest price decrease first
    private var sortedProducts: [Product] {
        products.sorted { $0.priceChangePercent < $1.priceChangePercent }
    }

    var body: some View {
        NavigationStack {
            Group {
                if products.isEmpty {
                    emptyState
                } else {
                    productList
                }
            }
            .navigationTitle("Zara Monitor")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !products.isEmpty {
                        Button(action: refreshAllPrices) {
                            if isRefreshingAll {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(isRefreshingAll)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddProduct = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await refreshAllPricesAsync()
            }
            .fullScreenCover(isPresented: $showingAddProduct) {
                AddProductView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nenhum Produto", systemImage: "tag")
        } description: {
            Text("Toque + para adicionar um produto da Zara.")
        }
    }

    // MARK: - Product List

    private var productList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sortedProducts) { product in
                    NavigationLink(destination: ProductDetailView(product: product)) {
                        ProductRow(product: product)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private func refreshAllPrices() {
        isRefreshingAll = true
        Task {
            await refreshAllPricesAsync()
            await MainActor.run { isRefreshingAll = false }
        }
    }

    private func refreshAllPricesAsync() async {
        for product in products where product.isMonitoring {
            do {
                let scraped = try await ZaraScraper.shared.fetchProduct(url: product.url)
                await MainActor.run {
                    if scraped.price != product.currentPrice {
                        product.addPricePoint(price: scraped.price)
                    }
                    if let newImage = scraped.imageURL {
                        product.imageURL = newImage
                    }
                    product.lastChecked = Date()
                }
            } catch {
                print("Failed to refresh \(product.name): \(error)")
            }
        }
    }
}

// MARK: - Product Row — Liquid Glass Card

struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Product image — tall, editorial aspect ratio
            AsyncImage(url: URL(string: product.imageURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Rectangle().fill(Color(.systemGray6))
                default:
                    Rectangle().fill(Color(.systemGray6))
                }
            }
            .frame(width: 90, height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Product info
            VStack(alignment: .leading, spacing: 8) {
                Text(product.name.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Price
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(formatPrice(product.currentPrice))
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.primary)

                    Text(" \(product.currency)")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.secondary)
                }

                // Original price if changed
                if product.initialPrice != product.currentPrice {
                    Text(formatPrice(product.initialPrice))
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }

                Spacer()

                // Price change indicator
                priceChangeView
            }
            .padding(.vertical, 12)

            Spacer()
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private var priceChangeView: some View {
        let pct = product.priceChangePercent

        if abs(pct) > 0.5 {
            HStack(spacing: 4) {
                Image(systemName: pct < 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(pct < 0 ? .green : .red)

                Text(String(format: "%@%.0f%%", pct > 0 ? "+" : "", pct))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(pct < 0 ? .green : .red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: .capsule)
        }
    }

    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Product.self, inMemory: true)
}
