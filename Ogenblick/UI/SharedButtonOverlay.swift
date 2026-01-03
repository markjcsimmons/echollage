import SwiftUI
import UIKit

/// Absolute button overlay using UIWindow coordinate space.
/// Positions button at exact screen pixel, completely independent of view hierarchy.
struct SharedButtonOverlay<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        OverlayRepresentable(content: AnyView(content))
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill entire screen
            .ignoresSafeArea(.all) // Ignore safe area to truly fill screen
    }
}

/// UIViewRepresentable to bypass SwiftUI layout entirely and use absolute UIKit coordinates
private struct OverlayRepresentable: UIViewRepresentable {
    let content: AnyView
    
    func makeUIView(context: Context) -> OverlayContainer {
        let container = OverlayContainer()
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        container.setHostingController(hostingController)
        return container
    }
    
    func updateUIView(_ uiView: OverlayContainer, context: Context) {
        if let hostingController = uiView.getHostingController() {
            hostingController.rootView = content
            uiView.setNeedsLayout()
        }
    }
}

private class OverlayContainer: UIView {
    private var hostingController: UIHostingController<AnyView>?
    private var buttonFrame: CGRect = .zero
    
    func setHostingController(_ controller: UIHostingController<AnyView>) {
        self.hostingController = controller
    }
    
    func getHostingController() -> UIHostingController<AnyView>? {
        return hostingController
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let hostingController = hostingController else { return }
        
        if hostingController.view.superview == nil {
            addSubview(hostingController.view)
        }
        
        // Get absolute screen dimensions (NOT affected by safe area)
        let screenBounds = UIScreen.main.bounds
        let screenWidth = screenBounds.width
        let screenHeight = screenBounds.height
        
        // Size the button naturally
        let buttonSize = hostingController.view.sizeThatFits(CGSize(width: screenWidth, height: screenHeight))
        
        // Calculate fixed position only once (ignore safe area changes)
        if buttonFrame == .zero {
            print("📏 Button size: \(buttonSize), screen height: \(screenHeight)")
            
            // Fixed position: center the 120pt circle at screen midpoint
            // This ensures ALL buttons appear at the exact same position regardless of their total height
            let x = (screenWidth - buttonSize.width) / 2
            
            // Position so the CENTER of the 120pt circle is at screen vertical center
            // Circle top edge is at: y
            // Circle center is at: y + 60
            // We want: y + 60 = screenHeight / 2
            // Therefore: y = (screenHeight / 2) - 60
            let circleRadius: CGFloat = 60 // Half of 120pt diameter
            let y = (screenHeight / 2) - circleRadius
            
            buttonFrame = CGRect(
                x: x,
                y: y,
                width: buttonSize.width,
                height: buttonSize.height
            )
            
            print("📍 Button positioned at y=\(y), circle center at y=\(y + circleRadius)")
            print("📍 OverlayContainer bounds=\(bounds), frame=\(frame)")
        }
        
        // Position button content
        hostingController.view.frame = buttonFrame
        
        // Make sure the hosting controller's view is interactive
        hostingController.view.isUserInteractionEnabled = true
        
        // Disable any implicit animations
        hostingController.view.layer.removeAllAnimations()
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hostingController = hostingController else {
            print("🎯 HIT TEST: No hosting controller")
            return nil
        }
        
        print("🎯 HIT TEST: point=\(point)")
        print("🎯 HIT TEST: container frame=\(frame)")
        print("🎯 HIT TEST: button frame=\(buttonFrame)")
        
        // Convert point to button coordinate space
        let buttonPoint = convert(point, to: hostingController.view)
        
        // Check if point is inside button frame
        if buttonFrame.contains(point) {
            print("🎯 HIT TEST: Point IS inside button frame!")
            // Let the hosting controller handle it
            let result = hostingController.view.hitTest(buttonPoint, with: event)
            print("🎯 HIT TEST: Hosting controller returned: \(String(describing: result))")
            return result
        } else {
            print("🎯 HIT TEST: Point OUTSIDE button frame, passing through")
            return nil
        }
    }
}

/// Shared button metrics to ensure pixel-perfect consistency
enum SharedButtonMetrics {
    static let mainDiameter: CGFloat = 120
    static let mainIconSize: CGFloat = 50
    static let smallDiameter: CGFloat = 56
    static let smallIconSize: CGFloat = 22
    static let horizontalSpacing: CGFloat = 28
}
