import SwiftUI
import UIKit

/// Edits a per-image grayscale mask (white keep, black erase). Saves on stroke end.
struct MaskEditorView: UIViewRepresentable {
    let baseImageSize: CGSize
    @Binding var maskFileName: String?
    let brushSize: CGFloat
    let projectId: UUID
    let store: ProjectStore
    let onSaved: (String) -> Void

    func makeUIView(context: Context) -> MaskCanvasView {
        let v = MaskCanvasView()
        v.baseImageSize = baseImageSize
        v.brushSize = brushSize
        v.projectId = projectId
        v.store = store
        v.maskFileName = maskFileName
        v.onSaved = onSaved
        v.loadMaskOrCreate()
        return v
    }

    func updateUIView(_ uiView: MaskCanvasView, context: Context) {
        uiView.brushSize = brushSize
        if uiView.maskFileName != maskFileName {
            uiView.maskFileName = maskFileName
            uiView.loadMaskOrCreate()
        }
    }
}

final class MaskCanvasView: UIView {
    var baseImageSize: CGSize = .zero
    var brushSize: CGFloat = 16
    var projectId: UUID!
    var store: ProjectStore!
    var maskFileName: String?
    var onSaved: ((String) -> Void)?

    private var maskImage: UIImage! // grayscale
    private var points: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func loadMaskOrCreate() {
        if let name = maskFileName {
            let url = store.urlForProjectAsset(projectId: projectId, fileName: name)
            if let img = UIImage(contentsOfFile: url.path) {
            maskImage = img
                return
            }
        }
        else {
            // Create white mask at ~1024px long side
            let maxDim: CGFloat = 1024
            let scale = maxDim / max(baseImageSize.width, baseImageSize.height)
            let size = CGSize(width: max(1, baseImageSize.width * scale), height: max(1, baseImageSize.height * scale))
            let fmt = UIGraphicsImageRendererFormat.default()
            fmt.scale = 1
            fmt.opaque = false
            let renderer = UIGraphicsImageRenderer(size: size, format: fmt)
            maskImage = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        // For debugging you could visualize mask, but we keep it transparent.
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        points = [t.location(in: self)]
        if let firstPoint = points.first {
            print("🎨 Mask editor touch began: \(firstPoint), bounds: \(bounds.size)")
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        points.append(t.location(in: self))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("🎨 Mask editor touch ended with \(points.count) points")
        applyStrokeAndSave()
        points.removeAll()
    }

    private func applyStrokeAndSave() {
        guard points.count >= 2 else {
            print("⚠️ Not enough points: \(points.count)")
            return
        }
        guard maskImage.size.width > 0 && maskImage.size.height > 0 else {
            print("❌ Mask image has zero size")
            return
        }
        let displayed = aspectFitRect(imageSize: baseImageSize, in: bounds.size)
        print("🎨 Displayed rect: \(displayed), mask size: \(maskImage.size)")

        // Convert points to mask space
        let scaleX = maskImage.size.width / displayed.width
        let scaleY = maskImage.size.height / displayed.height
        let maskPoints: [CGPoint] = points.compactMap { p in
            guard displayed.contains(p) else { return nil }
            let rel = CGPoint(x: (p.x - displayed.minX) * scaleX, y: (p.y - displayed.minY) * scaleY)
            return rel
        }
        guard maskPoints.count >= 2, let firstPoint = maskPoints.first else { return }

        // Render once per stroke
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let renderer = UIGraphicsImageRenderer(size: maskImage.size, format: fmt)
        let newMask = renderer.image { ctx in
            maskImage.draw(at: .zero)
            let cg = ctx.cgContext
            cg.setBlendMode(.normal)
            cg.setStrokeColor(UIColor.black.cgColor) // black = erase
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let lw = max(1, brushSize * max(scaleX, scaleY))
            cg.setLineWidth(lw)
            cg.beginPath()
            cg.move(to: firstPoint)
            for p in maskPoints.dropFirst() { cg.addLine(to: p) }
            cg.strokePath()
        }

        maskImage = newMask

        // Save
        if let data = newMask.pngData() {
            let name = maskFileName ?? "mask_\(UUID().uuidString).png"
            let url = store.urlForProjectAsset(projectId: projectId, fileName: name)
            do {
                try data.write(to: url)
                print("✅ Saved mask: \(name) (\(data.count) bytes)")
                maskFileName = name
                onSaved?(name)
            } catch {
                print("❌ Failed to save mask: \(error)")
            }
        } else {
            print("❌ Failed to get PNG data from mask")
        }
    }

    private func aspectFitRect(imageSize: CGSize, in view: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = view.width / view.height
        if imageAspect > viewAspect {
            let h = view.width / imageAspect
            return CGRect(x: 0, y: (view.height - h)/2, width: view.width, height: h)
        } else {
            let w = view.height * imageAspect
            return CGRect(x: (view.width - w)/2, y: 0, width: w, height: view.height)
        }
    }
}


