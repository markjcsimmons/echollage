import SwiftUI
import PencilKit

/// Renders PencilKit drawing bound to a specific image in its coordinate space
struct ImageBoundDrawingView: UIViewRepresentable {
    let drawingData: Data
    let imageSize: CGSize
    let isInteractive: Bool
    
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false // Drawing done elsewhere
        view.isOpaque = false
        
        // Load drawing if available
        if let drawing = try? PKDrawing(data: drawingData) {
            view.drawing = drawing
        }
        
        return view
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update drawing if changed
        if let drawing = try? PKDrawing(data: drawingData), drawing != uiView.drawing {
            uiView.drawing = drawing
        }
    }
}




