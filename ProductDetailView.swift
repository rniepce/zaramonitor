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
                // Hero image
                heroImage

                // Product info wrapped in glass card
                VStack(alignment: .leading, spacing: 24) {
                    productHeader
                    priceSection
                    settingsSection
                    priceHistorySection
                    actionsSection
                }
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Detalhes")
        .navigationBarTitleDisplayMode(.inline)
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
                        .overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Product Header

    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(product.name.uppercased())
                .font(.system(size: 13, weight: .regular))
                .tracking(2)
                .foregroundStyle(.primary)
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
                        .foregroundStyle(.primary)
                    Text(product.currency)
                        .font(.system(size: 10, weight: .light))
                        .foregroundStyle(.secondary)
                }

                // Original price (strikethrough) if changed
                if product.initialPrice != product.currentPrice {
                    Text(formatPrice(product.initialPrice))
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.secondary)
                        .strikethrough()
                }
            }

            // Percentage change
            let pct = product.priceChangePercent
            if abs(pct) > 0.5 {
                HStack(spacing: 4) {
                    Image(systemName: pct < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.system(size: 9, weight: .medium))
                    Text(String(format: "%@%.1f%%", pct > 0 ? "+" : "", pct))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                }
                .foregroundStyle(pct < 0 ? .green : .red)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
            }

            // Last checked
            Text("Atualizado \(product.lastChecked.formatted(.relative(presentation: .named)))")
                .font(.system(size: 10, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Configurações")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Monitoramento")
                    .font(.system(size: 13, weight: .light))
                Spacer()
                Toggle("", isOn: $product.isMonitoring)
                    .tint(.accentColor)
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
            Text("Histórico de Preços")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if product.priceHistory.isEmpty {
                Text("Sem dados ainda")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(.tertiary)
            } else {
                // Chart
                Chart(product.priceHistory) { point in
                    LineMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(.primary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))

                    AreaMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.accentColor.opacity(0.15), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    PointMark(
                        x: .value("Data", point.date),
                        y: .value("Preço", point.price)
                    )
                    .foregroundStyle(.primary)
                    .symbolSize(20)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(.tertiary)
                        AxisValueLabel()
                            .font(.system(size: 8, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)

                // History list
                VStack(spacing: 0) {
                    ForEach(product.priceHistory.sorted(by: { $0.date > $1.date }), id: \.date) { point in
                        HStack {
                            Text(point.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11, weight: .light))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatPrice(point.price))
                                .font(.system(size: 11, weight: .light, design: .monospaced))
                                .foregroundStyle(.primary)
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
                        ProgressView()
                    } else {
                        Label("Atualizar Preço", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Spacer()
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isRefreshing)

            Button(action: {
                if let url = URL(string: product.url) { openURL(url) }
            }) {
                HStack {
                    Spacer()
                    Label("Ver na Zara", systemImage: "safari")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
            }
            .buttonStyle(.glass)
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
