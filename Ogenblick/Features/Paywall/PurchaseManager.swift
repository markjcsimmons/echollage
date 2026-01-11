import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published private(set) var isSubscribed: Bool = false
    @Published private(set) var freeExportsRemaining: Int = max(0, 3 - UserDefaults.standard.integer(forKey: "exportCount"))

    var canExport: Bool { 
        // For development: allow unlimited exports
        // TODO: Remove this before production release
        #if DEBUG
        return true
        #else
        return isSubscribed || freeExportsRemaining > 0
        #endif
    }

    func registerSuccessfulExport() {
        guard !isSubscribed else { return }
        let current = UserDefaults.standard.integer(forKey: "exportCount")
        UserDefaults.standard.set(current + 1, forKey: "exportCount")
        freeExportsRemaining = max(0, 3 - (current + 1))
    }

    // MARK: - StoreKit 2 scaffolding
    private let productIds: [String] = [
        "com.ogenblick.pro.monthly",
        "com.ogenblick.pro.yearly"
    ]

    @Published var products: [Product] = []

    func loadProducts() async {
        do {
            products = try await Product.products(for: productIds)
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification { case .unverified: break; case .verified: isSubscribed = true }
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productType == .autoRenewable {
                isSubscribed = true
                return
            }
        }
        isSubscribed = false
    }
    
    // For testing: Reset export count
    #if DEBUG
    func resetExportCount() {
        UserDefaults.standard.set(0, forKey: "exportCount")
        freeExportsRemaining = 3
    }
    #endif
}





