import SwiftUI

struct ImageBounds: Identifiable {
    let id: UUID
    let frame: CGRect
    let zIndex: Int
}

/// Full-screen overlay that captures tear gestures and identifies which image to split
struct TearOverlay: View {
    let isActive: Bool
    let imageBounds: [ImageBounds] // Actual rendered bounds of each image
    let canvasSize: CGSize
    let onTear: (UUID, [CGPoint]) -> Void // Returns layer ID and path points in canvas coordinates
    
    @State private var currentPath: [CGPoint] = []
    @State private var isDrawing = false
    
    var body: some View {
        Canvas { context, size in
            // Draw red tear line
            if !currentPath.isEmpty {
                var path = Path()
                path.move(to: currentPath[0])
                for point in currentPath.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(path, with: .color(.red), lineWidth: 3)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDrawing {
                        isDrawing = true
                        currentPath = [value.location]
                        print("✂️ TEAR: Started at \(value.location)")
                    } else {
                        currentPath.append(value.location)
                        if currentPath.count % 10 == 0 {
                            print("✂️ TEAR: Path has \(currentPath.count) points")
                        }
                    }
                }
                .onEnded { value in
                    print("✂️ TEAR: Ended with \(currentPath.count) points")
                    // Find topmost image at start point
                    let startPoint = currentPath.first ?? .zero
                    print("✂️ TEAR: Looking for image at \(startPoint)")
                    if let layerId = findTopmostImage(at: startPoint) {
                        print("✂️ TEAR: Found image \(layerId)")
                        onTear(layerId, currentPath)
                    } else {
                        print("✂️ TEAR: No image found at touch point")
                    }
                    currentPath = []
                    isDrawing = false
                }
        )
        .allowsHitTesting(isActive)
        .opacity(isActive ? 1 : 0)
        .onAppear {
            print("✂️ TEAR OVERLAY: Appeared, isActive=\(isActive)")
        }
        .onChange(of: isActive) { newValue in
            print("✂️ TEAR OVERLAY: isActive changed to \(newValue)")
        }
    }
    
    private func findTopmostImage(at point: CGPoint) -> UUID? {
        // Sort by zIndex descending (topmost first)
        let sorted = imageBounds.sorted { $0.zIndex > $1.zIndex }
        
        print("✂️ TEAR: Checking \(sorted.count) images for hit at \(point)")
        
        for bounds in sorted {
            let frame = bounds.frame
            let xRange = frame.minX...frame.maxX
            let yRange = frame.minY...frame.maxY
            
            // Add 30pt padding to make hit detection more forgiving
            let paddedFrame = frame.insetBy(dx: -30, dy: -30)
            
            print("✂️ TEAR: Image \(bounds.id.uuidString.prefix(8))")
            print("   Frame: \(frame)")
            print("   Padded frame: \(paddedFrame)")
            print("   X range: \(paddedFrame.minX) to \(paddedFrame.maxX), touch.x: \(point.x), contains: \((paddedFrame.minX...paddedFrame.maxX).contains(point.x))")
            print("   Y range: \(paddedFrame.minY) to \(paddedFrame.maxY), touch.y: \(point.y), contains: \((paddedFrame.minY...paddedFrame.maxY).contains(point.y))")
            
            if paddedFrame.contains(point) {
                print("✂️ TEAR: ✅ HIT!")
                return bounds.id
            }
        }
        print("✂️ TEAR: ❌ No hits")
        return nil
    }
}

