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
            ZStack {
                Color.white.ignoresSafeArea()

                if products.isEmpty {
                    emptyState
                } else {
                    productList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ZARA MONITOR")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .tracking(4)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !products.isEmpty {
                        Button(action: refreshAllPrices) {
                            if isRefreshingAll {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .light))
                                    .foregroundColor(.black)
                            }
                        }
                        .disabled(isRefreshingAll)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddProduct = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .light))
                            .foregroundColor(.black)
                    }
                }
            }
            .refreshable {
                await refreshAllPricesAsync()
            }
            .sheet(isPresented: $showingAddProduct) {
                AddProductView()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("NENHUM PRODUTO")
                .font(.system(size: 13, weight: .light))
                .tracking(3)
                .foregroundColor(.black.opacity(0.4))

            Text("Toque + para adicionar")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.black.opacity(0.3))
        }
    }

    // MARK: - Product List

    private var productList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedProducts) { product in
                    NavigationLink(destination: ProductDetailView(product: product)) {
                        ProductRow(product: product)
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .padding(.horizontal, 20)
                }
            }
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

// MARK: - Product Row — Zara Editorial Style

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
            .clipped()

            // Product info — minimal, elegant typography
            VStack(alignment: .leading, spacing: 8) {
                Text(product.name.uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.5)
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()

                // Price
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(formatPrice(product.currentPrice))
                        .font(.system(size: 14, weight: .light))
                        .foregroundColor(.black)

                    Text(" \(product.currency)")
                        .font(.system(size: 9, weight: .light))
                        .foregroundColor(.black.opacity(0.4))
                }

                // Original price if changed
                if product.initialPrice != product.currentPrice {
                    Text(formatPrice(product.initialPrice))
                        .font(.system(size: 11, weight: .light))
                        .foregroundColor(.black.opacity(0.35))
                        .strikethrough(color: .black.opacity(0.35))
                }

                Spacer()

                // Price change indicator — subtle, editorial
                priceChangeView
            }
            .padding(.vertical, 12)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var priceChangeView: some View {
        let pct = product.priceChangePercent

        if abs(pct) > 0.5 {
            HStack(spacing: 4) {
                Rectangle()
                    .fill(pct < 0 ? Color.black : Color(.systemGray4))
                    .frame(width: 2, height: 12)

                Text(String(format: "%@%.0f%%", pct > 0 ? "+" : "", pct))
                    .font(.system(size: 10, weight: pct < 0 ? .medium : .light, design: .monospaced))
                    .foregroundColor(pct < 0 ? .black : .black.opacity(0.35))
            }
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
