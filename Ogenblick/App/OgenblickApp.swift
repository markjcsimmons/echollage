import SwiftUI

@main
struct OgenblickApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var purchaseManager = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                MainFlowView()
            }
            .environmentObject(projectStore)
            .environmentObject(purchaseManager)
        }
    }
}


