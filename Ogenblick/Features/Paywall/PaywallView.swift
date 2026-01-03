import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var loading = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Go Pro to export unlimited moments")
                .font(.title2).bold()
                .multilineTextAlignment(.center)
                .padding(.top)

            Text("You have \(purchases.freeExportsRemaining) free exports left.")
                .foregroundStyle(.secondary)

            if loading {
                ProgressView().task { await purchases.loadProducts(); loading = false }
            } else {
                ForEach(purchases.products, id: \.id) { product in
                    Button {
                        Task { await purchases.purchase(product); if purchases.isSubscribed { dismiss() } }
                    } label: {
                        HStack { Text(product.displayName); Spacer(); Text(product.displayPrice).bold() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Button("Maybe later") { dismiss() }
                .padding(.top, 8)
        }
        .padding()
    }
}





