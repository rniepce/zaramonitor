import SwiftUI
import SwiftData

struct AddProductView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingProducts: [Product]

    @State private var urlString = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scrapedProduct: ScrapedProduct?
    @State private var showDuplicateAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // URL Input
                        VStack(alignment: .leading, spacing: 12) {
                            Text("URL DO PRODUTO")
                                .font(.system(size: 10, weight: .regular))
                                .tracking(2)
                                .foregroundColor(.black.opacity(0.4))

                            TextField("https://www.zara.com/...", text: $urlString)
                                .font(.system(size: 14, weight: .light))
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.black.opacity(0.15), lineWidth: 0.5)
                                )

                            Button(action: fetchProduct) {
                                HStack {
                                    Spacer()
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text("BUSCAR")
                                            .font(.system(size: 12, weight: .regular))
                                            .tracking(2)
                                    }
                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 14)
                                .background(urlString.isEmpty || isLoading ? Color.black.opacity(0.3) : Color.black)
                            }
                            .disabled(urlString.isEmpty || isLoading)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 32)

                        // Preview
                        if let product = scrapedProduct {
                            VStack(spacing: 0) {
                                Divider()
                                    .padding(.vertical, 24)

                                // Product image
                                if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable()
                                                .aspectRatio(contentMode: .fit)
                                        default:
                                            Rectangle().fill(Color(.systemGray6))
                                                .frame(height: 280)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6).opacity(0.3))
                                }

                                VStack(alignment: .leading, spacing: 12) {
                                    Text(product.name.uppercased())
                                        .font(.system(size: 12, weight: .regular))
                                        .tracking(1.5)
                                        .foregroundColor(.black)
                                        .padding(.top, 16)

                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(formatPrice(product.price))
                                            .font(.system(size: 18, weight: .light))
                                            .foregroundColor(.black)
                                        Text(product.currency)
                                            .font(.system(size: 9, weight: .light))
                                            .foregroundColor(.black.opacity(0.4))
                                    }

                                    Button(action: saveProduct) {
                                        HStack {
                                            Spacer()
                                            Text("ADICIONAR AO MONITOR")
                                                .font(.system(size: 12, weight: .regular))
                                                .tracking(2)
                                            Spacer()
                                        }
                                        .foregroundColor(.white)
                                        .padding(.vertical, 14)
                                        .background(Color.black)
                                    }
                                    .padding(.top, 8)
                                }
                                .padding(.horizontal, 24)
                            }
                        }

                        // Error
                        if let error = errorMessage {
                            Text(error)
                                .font(.system(size: 12, weight: .light))
                                .foregroundColor(.red.opacity(0.7))
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADICIONAR")
                        .font(.system(size: 12, weight: .regular, design: .serif))
                        .tracking(3)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(.black)
                    }
                }
            }
            .alert("PRODUTO DUPLICADO", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Este produto já está sendo monitorado.")
            }
        }
    }

    private func fetchProduct() {
        guard let _ = URL(string: urlString) else {
            errorMessage = "URL inválida"
            return
        }

        isLoading = true
        errorMessage = nil
        scrapedProduct = nil

        Task {
            do {
                let product = try await ZaraScraper.shared.fetchProduct(url: urlString)
                await MainActor.run {
                    self.scrapedProduct = product
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Não foi possível buscar o produto."
                    self.isLoading = false
                }
            }
        }
    }

    private func saveProduct() {
        guard let scraped = scrapedProduct else { return }

        let normalizedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isDuplicate = existingProducts.contains {
            $0.url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedURL
        }

        if isDuplicate {
            showDuplicateAlert = true
            return
        }

        let newProduct = Product(
            url: urlString,
            name: scraped.name,
            currentPrice: scraped.price,
            currency: scraped.currency,
            imageURL: scraped.imageURL
        )

        modelContext.insert(newProduct)
        dismiss()
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
    AddProductView()
}
