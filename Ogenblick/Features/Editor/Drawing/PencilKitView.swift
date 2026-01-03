import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var drawingData: Data
    var isDrawingEnabled: Bool
    var isEraseMode: Bool = false
    var strokeColor: Color = .white
    var strokeWidth: CGFloat = 8
    var onDrawingChanged: ((Data) -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = isDrawingEnabled ? .anyInput : .pencilOnly
        view.backgroundColor = .clear
        if let drawing = try? PKDrawing(data: drawingData) {
            view.drawing = drawing
        }
        view.delegate = context.coordinator
        
        // Set tool with pressure sensitivity
        updateTool(for: view)
        
        return view
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawingPolicy = isDrawingEnabled ? .anyInput : .pencilOnly
        
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
        
        // Update callback
        context.coordinator.onDrawingChanged = onDrawingChanged
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


