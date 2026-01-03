import SwiftUI
import UIKit

struct TearableImageView: UIViewRepresentable {
    let image: UIImage
    let projectId: UUID
    let store: ProjectStore
    let onImageSplit: (String, String) -> Void // Returns two new image filenames
    
    func makeUIView(context: Context) -> TearContainerView {
        let view = TearContainerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isMultipleTouchEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: TearContainerView, context: Context) {
        uiView.configure(
            image: image,
            projectId: projectId,
            store: store,
            onSplit: onImageSplit
        )
    }
}

class TearContainerView: UIView {
    private var imageView: UIImageView!
    private var originalImage: UIImage?
    private var projectId: UUID?
    private var store: ProjectStore?
    private var onSplit: ((String, String) -> Void)?
    
    private var tearPath = UIBezierPath()
    private var tearLineLayer: CAShapeLayer?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)
    }
    
    func configure(image: UIImage, projectId: UUID, store: ProjectStore, onSplit: @escaping (String, String) -> Void) {
        self.originalImage = image
        self.projectId = projectId
        self.store = store
        self.onSplit = onSplit
        imageView.image = image
        imageView.frame = bounds
        setNeedsLayout()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
    }
    
    // MARK: - Touch Handling
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Accept touches within our bounds
        return bounds.contains(point)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        tearPath = UIBezierPath()
        tearPath.move(to: point)
        
        // Create visual feedback layer
        tearLineLayer?.removeFromSuperlayer()
        let layerShape = CAShapeLayer()
        layerShape.strokeColor = UIColor.red.cgColor
        layerShape.lineWidth = 3
        layerShape.fillColor = UIColor.clear.cgColor
        layerShape.lineCap = .round
        layer.addSublayer(layerShape)
        tearLineLayer = layerShape
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        tearPath.addLine(to: point)
        tearLineLayer?.path = tearPath.cgPath
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let originalImage = originalImage,
              let projectId = projectId,
              let store = store,
              let onSplit = onSplit else { return }
        
        // Remove visual feedback
        tearLineLayer?.removeFromSuperlayer()
        tearLineLayer = nil
        
        // Convert path to image coordinate space
        let imagePath = convertPathToImageCoordinates(tearPath, imageSize: originalImage.size, viewSize: bounds.size)
        
        // Run split and file writes off main thread
        DispatchQueue.global(qos: .userInitiated).async {
            let (firstResult, secondResult) = ImageSplitter.splitImage(originalImage, alongPath: imagePath)
            
            guard let result1 = firstResult, let result2 = secondResult else { return }
            
            let topFileName = "torn_top_\(UUID().uuidString).png"
            let bottomFileName = "torn_bottom_\(UUID().uuidString).png"
            
            let topURL = store.urlForProjectAsset(projectId: projectId, fileName: topFileName)
            let bottomURL = store.urlForProjectAsset(projectId: projectId, fileName: bottomFileName)
            
            if let topData = result1.pngData(),
               let bottomData = result2.pngData() {
                do {
                    try topData.write(to: topURL)
                    try bottomData.write(to: bottomURL)
                    
                    // Notify on main thread
                    DispatchQueue.main.async {
                        onSplit(topFileName, bottomFileName)
                    }
                } catch {
                    // Silently fail
                }
            }
        }
        
        tearPath = UIBezierPath()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        tearLineLayer?.removeFromSuperlayer()
        tearLineLayer = nil
        tearPath = UIBezierPath()
    }

    // MARK: - Coordinate Conversion
    private func convertPathToImageCoordinates(_ path: UIBezierPath, imageSize: CGSize, viewSize: CGSize) -> UIBezierPath {
        // Calculate how the image is displayed (aspect fit)
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        var displayedImageSize: CGSize
        var offset: CGPoint
        if imageAspect > viewAspect {
            displayedImageSize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
            offset = CGPoint(x: 0, y: (viewSize.height - displayedImageSize.height) / 2)
        } else {
            displayedImageSize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
            offset = CGPoint(x: (viewSize.width - displayedImageSize.width) / 2, y: 0)
        }
        let converted = UIBezierPath()
        var isFirst = true
        path.cgPath.applyWithBlock { element in
            let p = element.pointee.points[0]
            let adjX = (p.x - offset.x) / displayedImageSize.width * imageSize.width
            let adjY = (p.y - offset.y) / displayedImageSize.height * imageSize.height
            let ip = CGPoint(x: max(0, min(imageSize.width, adjX)), y: max(0, min(imageSize.height, adjY)))
            if isFirst { converted.move(to: ip); isFirst = false } else { converted.addLine(to: ip) }
        }
        return converted
    }
}

