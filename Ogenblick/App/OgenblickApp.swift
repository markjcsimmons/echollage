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
            .onAppear {
                Logger.info("App WindowGroup appeared", category: .general)
            }
            .environmentObject(projectStore)
            .environmentObject(purchaseManager)
        }
    }
}


