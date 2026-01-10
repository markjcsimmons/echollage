import SwiftUI
import PencilKit

/// Renders PencilKit drawing bound to a specific image in its coordinate space
struct ImageBoundDrawingView: UIViewRepresentable {
    let drawingData: Data
    let imageSize: CGSize
    let isInteractive: Bool
    
    func makeUIView(context: Context) -> BoundedPKCanvasView {
        let view = BoundedPKCanvasView(expectedSize: imageSize)
        view.drawingPolicy = .anyInput
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Drawing done elsewhere
        view.isOpaque = false
        // Ensure coordinate system matches exactly - same as drawing canvas
        view.contentScaleFactor = UIScreen.main.scale
        
        // Load drawing if available
        if let drawing = try? PKDrawing(data: drawingData) {
            view.drawing = drawing
        }
        
        return view
    }
    
    func updateUIView(_ uiView: BoundedPKCanvasView, context: Context) {
        // Update expected size (this will trigger layoutSubviews to adjust bounds)
        uiView.expectedSize = imageSize
        
        // Update drawing if changed
        if let drawing = try? PKDrawing(data: drawingData), drawing != uiView.drawing {
            uiView.drawing = drawing
            print("🔄 ImageBoundDrawingView: Updated drawing, size: \(imageSize)")
        }
    }
}

/// PKCanvasView subclass that ensures bounds match the expected size for coordinate consistency
/// CRITICAL: PencilKit records coordinates relative to bounds, so bounds must match exactly
/// between when drawing is created and when it's displayed
class BoundedPKCanvasView: PKCanvasView {
    var expectedSize: CGSize = .zero {
        didSet {
            if oldValue != expectedSize {
                setNeedsLayout()
            }
        }
    }
    
    private var hasSetInitialBounds = false
    
    init(expectedSize: CGSize) {
        self.expectedSize = expectedSize
        super.init(frame: CGRect(origin: .zero, size: expectedSize))
        // Set bounds immediately in init to ensure they match from the start
        if expectedSize.width > 0 && expectedSize.height > 0 {
            bounds = CGRect(origin: .zero, size: expectedSize)
            hasSetInitialBounds = true
            print("🔄 BoundedPKCanvasView init: Set bounds to \(expectedSize)")
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        // CRITICAL: Set bounds BEFORE super.layoutSubviews() so PencilKit uses correct coordinate space
        // PencilKit displays coordinates relative to bounds, so bounds must match expected size exactly
        if expectedSize.width > 0 && expectedSize.height > 0 {
            if bounds.size != expectedSize {
                bounds = CGRect(origin: .zero, size: expectedSize)
                if !hasSetInitialBounds {
                    print("🔄 BoundedPKCanvasView: Setting bounds to \(expectedSize) before layout (frame: \(frame.size))")
                    hasSetInitialBounds = true
                } else {
                    print("🔄 BoundedPKCanvasView: Correcting bounds to \(expectedSize) before layout (was \(bounds.size), frame: \(frame.size))")
                }
            }
        }
        
        super.layoutSubviews()
        
        // Ensure bounds are still correct after super.layoutSubviews() (it might change them)
        if expectedSize.width > 0 && expectedSize.height > 0 {
            if bounds.size != expectedSize {
                bounds = CGRect(origin: .zero, size: expectedSize)
                print("🔄 BoundedPKCanvasView: Corrected bounds after layout to \(expectedSize) (was \(bounds.size), frame: \(frame.size))")
            }
        }
    }
}




