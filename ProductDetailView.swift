import SwiftUI
import SwiftData
import Charts

struct ProductDetailView: View {
    @Bindable var product: Product
    @Environment(\.openURL) var openURL
    @State private var isRefreshing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero image — full width, editorial
                heroImage

                // Product info
                VStack(alignment: .leading, spacing: 24) {
                    productHeader
                    priceSection
                    Divider()
                    settingsSection
                    Divider()
                    priceHistorySection
                    Divider()
                    actionsSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("DETALHES")
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .tracking(3)
            }
        }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    Rectangle().fill(Color(.systemGray6))
                        .frame(height: 300)
                default:
                    Rectangle().fill(Color(.systemGray6))
                        .frame(height: 300)
                        .overlay(ProgressView().tint(.gray))
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6).opacity(0.3))
        }
    }

    // MARK: - Product Header

    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name.uppercased())
                .font(.system(size: 13, weight: .regular))
                .tracking(2)
                .foregroundColor(.black)
        }
    }

    // MARK: - Price Section

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Current price
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(formatPrice(product.currentPrice))
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.black)
                    Text(product.currency)
                        .font(.system(size: 10, weight: .light))
                        .foregroundColor(.black.opacity(0.4))
                }

                // Original price (strikethrough) if changed
                if product.initialPrice != product.currentPrice {
                    Text(formatPrice(product.initialPrice))
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(.black.opacity(0.3))
                        .strikethrough(color: .black.opacity(0.3))
                }
            }

            // Percentage change
            let pct = product.priceChangePercent
            if abs(pct) > 0.5 {
                Text(String(format: "%@%.1f%%", pct > 0 ? "+" : "", pct))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(pct < 0 ? .black : .black.opacity(0.4))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        pct < 0
                            ? Color.black.opacity(0.05)
                            : Color(.systemGray5).opacity(0.5)
                    )
            }

            // Last checked
            Text("Atualizado \(product.lastChecked.formatted(.relative(presentation: .named)))")
                .font(.system(size: 10, weight: .light))
                .foregroundColor(.black.opacity(0.3))
                .padding(.top, 4)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONFIGURAÇÕES")
                .font(.system(size: 10, weight: .regular))
                .tracking(2)
                .foregroundColor(.black.opacity(0.4))

            HStack {
                Text("Monitoramento")
                    .font(.system(size: 13, weight: .light))
                Spacer()
                Toggle("", isOn: $product.isMonitoring)
                    .tint(.black)
            }

            HStack {
                Text("Preço Alvo")
                    .font(.system(size: 13, weight: .light))
                Spacer()
                TextField("—", value: $product.targetPrice, format: .currency(code: product.currency))
                    .font(.system(size: 13, weight: .light))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
        }
    }

    // MARK: - Price History Chart

    private var priceHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HISTÓRICO DE PREÇOS")
                .font(.system(size: 10, weight: .regular))
                .tracking(2)
                .foregroundColor(.black.opacity(0.4))

            if product.priceHistory.isEmpty {
                Text("Sem dados ainda")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(.black.opacity(0.3))
            } else {
                // Chart
                Chart(product.priceHistory) { point in
                    LineMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(.black)
                    .lineStyle(StrokeStyle(lineWidth: 1))

                    AreaMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.black.opacity(0.06), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(.black)
                    .symbolSize(16)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.black.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .light))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.black.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .light))
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                .frame(height: 160)

                // History list
                VStack(spacing: 0) {
                    ForEach(product.priceHistory.sorted(by: { $0.date > $1.date }), id: \.date) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11, weight: .light))
                                .foregroundColor(.black.opacity(0.5))
                            Spacer()
                            Text(formatPrice(point.price))
                                .font(.system(size: 11, weight: .light, design: .monospaced))
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 8)

                        Divider()
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Button(action: refreshPrice) {
                HStack {
                    Spacer()
                    if isRefreshing {
                        ProgressView().tint(.white)
                    } else {
                        Text("ATUALIZAR PREÇO")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(2)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .background(Color.black)
            }
            .disabled(isRefreshing)

            Button(action: {
                if let url = URL(string: product.url) { openURL(url) }
            }) {
                HStack {
                    Spacer()
                    Text("VER NA ZARA")
                        .font(.system(size: 12, weight: .regular))
                        .tracking(2)
                    Spacer()
                }
                .foregroundColor(.black)
                .padding(.vertical, 14)
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 0.5)
                )
            }
        }
    }

    // MARK: - Helpers

    private func refreshPrice() {
        isRefreshing = true
        Task {
            do {
                let scraped = try await ZaraScraper.shared.fetchProduct(url: product.url)
                await MainActor.run {
                    if scraped.price != product.currentPrice {
                        product.addPricePoint(price: scraped.price)
                        product.imageURL = scraped.imageURL
                    }
                    product.lastChecked = Date()
                    isRefreshing = false
                }
            } catch {
                await MainActor.run { isRefreshing = false }
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
