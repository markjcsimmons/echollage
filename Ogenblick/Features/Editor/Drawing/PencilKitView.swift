import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var drawingData: Data
    var isDrawingEnabled: Bool
    var isEraseMode: Bool = false
    var strokeColor: Color = .white
    var strokeWidth: CGFloat = 8
    var expectedSize: CGSize? = nil // Optional expected size for bounds matching
    var onDrawingChanged: ((Data) -> Void)?
    var onTapOnly: (() -> Void)? = nil // Callback when user taps (not draws) to deselect paint tool

    func makeUIView(context: Context) -> BoundedPencilKitCanvasView {
        let view = BoundedPencilKitCanvasView(expectedSize: expectedSize)
        view.drawingPolicy = isDrawingEnabled ? .anyInput : .pencilOnly
        view.backgroundColor = .clear
        view.isOpaque = false
        // Ensure coordinate system matches exactly - disable content scale factor compensation
        // This ensures drawing coordinates match display coordinates exactly
        view.contentScaleFactor = UIScreen.main.scale
        if let drawing = try? PKDrawing(data: drawingData) {
            view.drawing = drawing
        }
        view.delegate = context.coordinator
        view.onTapOnly = onTapOnly // Pass callback to view
        
        // Set tool with pressure sensitivity
        updateTool(for: view)
        
        return view
    }

    func updateUIView(_ uiView: BoundedPencilKitCanvasView, context: Context) {
        uiView.drawingPolicy = isDrawingEnabled ? .anyInput : .pencilOnly
        
        // Update expected size for bounds matching
        uiView.expectedSize = expectedSize
        
        // Update drawing if data changed externally (e.g., undo)
        let currentDrawing = uiView.drawing.dataRepresentation()
        if currentDrawing != drawingData {
            print("🎨 PencilKitView: Drawing data changed externally, updating canvas")
            if let newDrawing = try? PKDrawing(data: drawingData) {
                uiView.drawing = newDrawing
                print("🎨 Canvas updated with new drawing, size: \(drawingData.count) bytes")
            }
        }
        
        // Update tool based on current settings
        updateTool(for: uiView)
        
        // Update callbacks
        context.coordinator.onDrawingChanged = onDrawingChanged
        uiView.onTapOnly = onTapOnly
    }
    
    private func updateTool(for view: PKCanvasView) {
        if isEraseMode {
            view.tool = PKEraserTool(.vector)
        } else {
            // Use marker for better pressure sensitivity
            // Marker tool has better pressure response than pen
            // Width is minimum - pressure will scale it up significantly
            let uiColor = UIColor(strokeColor)
            view.tool = PKInkingTool(.marker, color: uiColor, width: strokeWidth * 0.5)
        }
    }

    func makeCoordinator() -> Coordinator { 
        Coordinator(drawingData: $drawingData, onDrawingChanged: onDrawingChanged) 
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawingData: Data
        var onDrawingChanged: ((Data) -> Void)?
        private var isDrawingStroke = false
        
        init(drawingData: Binding<Data>, onDrawingChanged: ((Data) -> Void)?) { 
            _drawingData = drawingData 
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let newData = canvasView.drawing.dataRepresentation()
            
            // Track if we're actively drawing
            if !isDrawingStroke {
                isDrawingStroke = true
                print("🎨 canvasViewDrawingDidChange - started stroke")
            }
            
            drawingData = newData
        }
        
        // This is called when drawing interaction ends (finger lifted)
        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            print("🎨 canvasViewDidEndUsingTool called!")
            let newData = canvasView.drawing.dataRepresentation()
            onDrawingChanged?(newData) // Save to history when stroke completes
            isDrawingStroke = false
            print("🎨 Stroke completed, saved to history, data size: \(newData.count)")
        }
        
        // Fallback: also check when drawing ends if the delegate method doesn't fire
        func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
            if isDrawingStroke {
                print("🎨 canvasViewDidFinishRendering - stroke finished via fallback")
                let newData = canvasView.drawing.dataRepresentation()
                onDrawingChanged?(newData)
                isDrawingStroke = false
            }
        }
    }
}

/// PKCanvasView subclass that ensures bounds match expected size for coordinate consistency
/// CRITICAL: PencilKit records coordinates relative to bounds, so bounds must match exactly
/// between when drawing is created and when it's displayed
class BoundedPencilKitCanvasView: PKCanvasView {
    var expectedSize: CGSize? {
        didSet {
            if oldValue != expectedSize {
                setNeedsLayout()
            }
        }
    }
    
    var onTapOnly: (() -> Void)? = nil // Callback when user taps (not draws)
    private var touchStartLocation: CGPoint? = nil
    private var hasMoved = false
    private var hasSetInitialBounds = false
    
    init(expectedSize: CGSize?) {
        self.expectedSize = expectedSize
        let size = expectedSize ?? CGSize(width: 100, height: 100) // Default size
        super.init(frame: CGRect(origin: .zero, size: size))
        // Set bounds immediately in init to ensure they match from the start
        if let expected = expectedSize, expected.width > 0 && expected.height > 0 {
            bounds = CGRect(origin: .zero, size: expected)
            hasSetInitialBounds = true
            print("🔄 BoundedPencilKitCanvasView init: Set bounds to \(expected)")
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        // CRITICAL: Set bounds BEFORE super.layoutSubviews() so PencilKit uses correct coordinate space
        // PencilKit records coordinates relative to bounds, so bounds must match expected size exactly
        if let expected = expectedSize, expected.width > 0 && expected.height > 0 {
            if bounds.size != expected {
                bounds = CGRect(origin: .zero, size: expected)
                if !hasSetInitialBounds {
                    print("🔄 BoundedPencilKitCanvasView: Setting bounds to \(expected) before layout (frame: \(frame.size))")
                    hasSetInitialBounds = true
                } else {
                    print("🔄 BoundedPencilKitCanvasView: Correcting bounds to \(expected) before layout (was \(bounds.size), frame: \(frame.size))")
                }
            }
        }
        
        super.layoutSubviews()
        
        // Ensure bounds are still correct after super.layoutSubviews() (it might change them)
        if let expected = expectedSize, expected.width > 0 && expected.height > 0 {
            if bounds.size != expected {
                bounds = CGRect(origin: .zero, size: expected)
                print("🔄 BoundedPencilKitCanvasView: Corrected bounds after layout to \(expected) (was \(bounds.size), frame: \(frame.size))")
            }
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // CRITICAL: Ensure bounds are correct before handling touches
        // Touch coordinates are converted to view's coordinate space, which depends on bounds
        if let expected = expectedSize, expected.width > 0 && expected.height > 0 {
            if bounds.size != expected {
                bounds = CGRect(origin: .zero, size: expected)
                print("🔄 BoundedPencilKitCanvasView touchesBegan: Corrected bounds to \(expected) before touch (was \(bounds.size))")
            }
        }
        
        // Track touch start location to detect taps vs draws
        if let touch = touches.first {
            touchStartLocation = touch.location(in: self)
            hasMoved = false
        }
        
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Ensure bounds remain correct during touch move
        if let expected = expectedSize, expected.width > 0 && expected.height > 0 {
            if bounds.size != expected {
                bounds = CGRect(origin: .zero, size: expected)
            }
        }
        
        // Track if touch has moved (means it's a draw, not a tap)
        if touchStartLocation != nil {
            hasMoved = true
        }
        
        super.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        // If touch ended without moving (was a tap, not a draw), call callback
        if let startLocation = touchStartLocation, !hasMoved, let touch = touches.first {
            let endLocation = touch.location(in: self)
            let distance = hypot(endLocation.x - startLocation.x, endLocation.y - startLocation.y)
            
            // If touch moved less than 5 points, consider it a tap
            if distance < 5.0 {
                print("🎨 Detected tap on canvas (not draw) - calling onTapOnly callback")
                DispatchQueue.main.async {
                    self.onTapOnly?()
                }
            }
        }
        
        // Reset tracking
        touchStartLocation = nil
        hasMoved = false
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        // Reset tracking on cancel
        touchStartLocation = nil
        hasMoved = false
    }
}


