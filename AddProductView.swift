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
            ScrollView {
                VStack(spacing: 20) {
                    // URL Input Card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("URL do Produto")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextField("https://www.zara.com/...", text: $urlString)
                            .font(.system(size: 14, weight: .light))
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .textFieldStyle(.roundedBorder)

                        Button(action: fetchProduct) {
                            HStack {
                                Spacer()
                                if isLoading {
                                    ProgressView()
                                } else {
                                    Text("Buscar")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(urlString.isEmpty || isLoading)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))

                    // Preview
                    if let product = scrapedProduct {
                        VStack(spacing: 0) {
                            // Product image
                            if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable()
                                            .aspectRatio(contentMode: .fit)
                                    default:
                                        Rectangle().fill(Color(.systemGray6))
                                            .frame(height: 200)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Text(product.name.uppercased())
                                    .font(.system(size: 12, weight: .regular))
                                    .tracking(1.5)
                                    .foregroundStyle(.primary)
                                    .padding(.top, 16)

                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(formatPrice(product.price))
                                        .font(.system(size: 18, weight: .light))
                                        .foregroundStyle(.primary)
                                    Text(product.currency)
                                        .font(.system(size: 9, weight: .light))
                                        .foregroundStyle(.secondary)
                                }

                                Button(action: saveProduct) {
                                    HStack {
                                        Spacer()
                                        Text("Adicionar ao Monitor")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.glassProminent)
                                .padding(.top, 8)
                            }
                        }
                        .padding(20)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    }

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12, weight: .light))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .navigationTitle("Adicionar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
            }
            .alert("Produto Duplicado", isPresented: $showDuplicateAlert) {
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
