import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        return viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if isPresented && context.coordinator.presented == false {
            let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
            
            // For iPad support
            if let popover = av.popoverPresentationController {
                popover.sourceView = uiViewController.view
                popover.sourceRect = CGRect(x: uiViewController.view.bounds.midX, y: uiViewController.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            // Set completion handler to dismiss
            av.completionWithItemsHandler = { _, completed, _, _ in
                DispatchQueue.main.async {
                    self.isPresented = false
                    context.coordinator.presented = false
                }
            }
            
            uiViewController.present(av, animated: true) {
                context.coordinator.presented = true
            }
        } else if !isPresented && context.coordinator.presented == true {
            uiViewController.dismiss(animated: true) {
                context.coordinator.presented = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject {
        var presented = false
    }
}





