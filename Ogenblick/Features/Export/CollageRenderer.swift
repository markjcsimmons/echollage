import Foundation
import SwiftUI
import UIKit
import PencilKit

/// Renders a collage project to a single flattened UIImage
enum CollageRenderer {
    /// Renders the collage at full screen dimensions (canvas fills entire screen in editor)
    static func render(project: Project, assetURLProvider: (String) -> URL?) -> UIImage? {
        // Canvas fills entire screen in editor (toolbar is overlaid on top)
        let size = UIScreen.main.bounds.size
        let scale: CGFloat = 1.0
        
        print("🎨 Rendering at full screen: \(size), project canvas: \(project.canvasWidth)x\(project.canvasHeight)")
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let ctx = context.cgContext
            
            // Render background based on project backgroundType
            switch project.backgroundType {
            case .corkboard:
                // Cork background - render exactly like editor
                if let corkImage = loadCorkImage(),
                   let rotatedCork = rotateCorkImage(corkImage, degrees: 90) {
                // Use scaleAspectFill to match editor
                let corkAspect = rotatedCork.size.width / rotatedCork.size.height
                let screenAspect = size.width / size.height
                
                var drawSize = size
                if corkAspect > screenAspect {
                    // Cork is wider, scale to height and extend width
                    drawSize.height = size.height + 100 // Extra 50pt on each edge
                    drawSize.width = drawSize.height * corkAspect
                } else {
                    // Cork is taller, scale to width and extend height
                    drawSize.width = size.width + 100 // Extra 50pt on each edge
                    drawSize.height = drawSize.width / corkAspect
                }
                
                // Center the cork with offset
                let drawRect = CGRect(
                    x: (size.width - drawSize.width) / 2,
                    y: (size.height - drawSize.height) / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                
                    rotatedCork.draw(in: drawRect)
                    print("🎨 Drew cork background at \(drawRect)")
                } else {
                    // Fallback to cork-colored background
                    ctx.setFillColor(UIColor(red: 0.82, green: 0.68, blue: 0.50, alpha: 1.0).cgColor)
                    ctx.fill(CGRect(origin: .zero, size: size))
                    print("🎨 Drew fallback cork color background")
                }
            case .white:
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                print("🎨 Drew white background")
            case .skyBlue:
                ctx.setFillColor(UIColor(red: 0.53, green: 0.81, blue: 0.98, alpha: 1.0).cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                print("🎨 Drew sky blue background")
            case .black:
                ctx.setFillColor(UIColor.black.cgColor)
                ctx.fill(CGRect(origin: .zero, size: size))
                print("🎨 Drew black background")
            }
            
            // Image layers - render exactly as positioned in editor
            print("🎨 Rendering \(project.imageLayers.count) image layers")
            for (index, layer) in project.imageLayers.enumerated() {
                // Load base image
                guard let url = assetURLProvider(layer.imageFileName),
                      let image = UIImage(contentsOfFile: url.path) else {
                    print("❌ Failed to load image: \(layer.imageFileName)")
                    continue
                }
                
                print("🎨 Layer \(index): size=\(image.size), transform=\(layer.transform)")
                
                ctx.saveGState()
                
                // Calculate base image size (matching editor's baseImageSize function)
                let aspect = image.size.width / image.size.height
                let maxDimension = min(size.width, size.height) * 0.45
                var width = maxDimension
                var height = width / aspect
                if height > maxDimension {
                    height = maxDimension
                    width = height * aspect
                }
                let baseSize = CGSize(width: width, height: height)
                
                // Transform exactly as in editor: center + offset
                let centerX = size.width / 2 + CGFloat(layer.transform.x)
                let centerY = size.height / 2 + CGFloat(layer.transform.y)
                ctx.translateBy(x: centerX, y: centerY)
                ctx.rotate(by: CGFloat(layer.transform.rotation))
                ctx.scaleBy(x: CGFloat(layer.transform.scale), y: CGFloat(layer.transform.scale))
                
                let rect = CGRect(x: -baseSize.width / 2, y: -baseSize.height / 2,
                                  width: baseSize.width, height: baseSize.height)

                // Apply mask if present (white keep, black erase)
                if let maskName = layer.maskFileName,
                   let maskURL = assetURLProvider(maskName),
                   let maskImage = UIImage(contentsOfFile: maskURL.path),
                   let cgMask = maskImage.cgImage {
                    ctx.clip(to: rect, mask: cgMask)
                }

                image.draw(in: rect, blendMode: .normal, alpha: CGFloat(layer.opacity))
                ctx.restoreGState()
            }
            
            // Text layers
            for layer in project.textLayers {
                ctx.saveGState()
                
                let centerX = size.width / 2 + CGFloat(layer.transform.x) * scale
                let centerY = size.height / 2 + CGFloat(layer.transform.y) * scale
                ctx.translateBy(x: centerX, y: centerY)
                ctx.rotate(by: CGFloat(layer.transform.rotation))
                ctx.scaleBy(x: CGFloat(layer.transform.scale), y: CGFloat(layer.transform.scale))
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: layer.fontName, size: CGFloat(layer.fontSize) * scale) ?? UIFont.systemFont(ofSize: CGFloat(layer.fontSize) * scale),
                    .foregroundColor: UIColor(hexString: layer.hexColor) ?? UIColor.white
                ]
                let attrString = NSAttributedString(string: layer.text, attributes: attributes)
                let textSize = attrString.size()
                attrString.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
                
                ctx.restoreGState()
            }
            
            // Drawing layer - render at screen size to match editor
            if let drawingBase64 = project.drawingDataBase64,
               let drawingData = Data(base64Encoded: drawingBase64),
               let drawing = try? PKDrawing(data: drawingData) {
                // Render the drawing at screen size (same as the canvas view in editor)
                let drawingImage = drawing.image(from: CGRect(origin: .zero, size: size), scale: UIScreen.main.scale)
                drawingImage.draw(in: CGRect(origin: .zero, size: size))
                print("🎨 Drew global canvas drawing at size: \(size)")
            }
        }
    }
    
    // Helper functions to load and rotate cork image (matching editor)
    private static func loadCorkImage() -> UIImage? {
        let possibleNames = ["cork", "corkboard", "cork-texture", "cork_texture"]
        
        for name in possibleNames {
            if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        
        if let image = UIImage(named: "cork") {
            return image
        }
        
        return nil
    }
    
    private static func rotateCorkImage(_ image: UIImage, degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                             width: image.size.width, height: image.size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }
}

extension UIColor {
    convenience init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

