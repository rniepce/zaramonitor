import SwiftUI
import SwiftData

struct AddProductView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var urlString = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var scrapedProduct: ScrapedProduct?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Product URL")) {
                    TextField("https://www.zara.com/...", text: $urlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button(action: fetchProduct) {
                        if isLoading {
                            ProgressView()
                        } else {
                            Text("Fetch Details")
                        }
                    }
                    .disabled(urlString.isEmpty || isLoading)
                }
                
                if let product = scrapedProduct {
                    Section(header: Text("Preview")) {
                        if let imageUrl = product.imageURL, let url = URL(string: imageUrl) {
                            AsyncImage(url: url) { image in
                                image.resizable()
                                     .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(height: 200)
                        }
                        
                        Text(product.name)
                            .font(.headline)
                        
                        HStack {
                            Text("Current Price:")
                            Spacer()
                            Text(product.price, format: .currency(code: product.currency))
                                .bold()
                        }
                    }
                    
                    Section {
                        Button("Add to Monitor") {
                            saveProduct()
                        }
                        .disabled(isLoading)
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func fetchProduct() {
        guard let _ = URL(string: urlString) else {
            errorMessage = "Invalid URL"
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
                    self.errorMessage = "Failed to fetch: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func saveProduct() {
        guard let scraped = scrapedProduct else { return }
        
        // Check if already exists? (Optional, but good practice)
        // For now, just add.
        
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
}

#Preview {
    AddProductView()
}
