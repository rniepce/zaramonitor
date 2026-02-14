import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.lastChecked, order: .reverse) private var products: [Product]
    @State private var showingAddProduct = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(products) { product in
                    NavigationLink(destination: ProductDetailView(product: product)) {
                        HStack {
                            AsyncImage(url: URL(string: product.imageURL ?? "")) { image in
                                image.resizable()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 50, height: 75)
                            .cornerRadius(4)
                            
                            VStack(alignment: .leading) {
                                Text(product.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                HStack {
                                    Text(product.currentPrice, format: .currency(code: "BRL"))
                                        .bold()
                                    if let target = product.targetPrice, product.currentPrice <= target {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Zara Monitor")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddProduct = true }) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProduct) {
                AddProductView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(products[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Product.self, inMemory: true)
}
