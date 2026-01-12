import Foundation
import SwiftUI
import UIKit
import AVFoundation
import AVKit
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
            case .psych:
                // Psych background - render image similar to cork
                if let psychImage = loadPsychImage() {
                    // Use scaleAspectFill to match editor
                    let psychAspect = psychImage.size.width / psychImage.size.height
                    let screenAspect = size.width / size.height
                    
                    var drawSize = size
                    if psychAspect > screenAspect {
                        // Psych image is wider, scale to height and extend width
                        drawSize.height = size.height + 100 // Extra 50pt on each edge
                        drawSize.width = drawSize.height * psychAspect
                    } else {
                        // Psych image is taller, scale to width and extend height
                        drawSize.width = size.width + 100 // Extra 50pt on each edge
                        drawSize.height = drawSize.width / psychAspect
                    }
                    
                    // Center the psych image with offset
                    let drawRect = CGRect(
                        x: (size.width - drawSize.width) / 2,
                        y: (size.height - drawSize.height) / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                    
                    psychImage.draw(in: drawRect)
                    print("🎨 Drew psych background at \(drawRect)")
                } else {
                    // Fallback to black background
                    ctx.setFillColor(UIColor.black.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: size))
                    print("🎨 Drew fallback black background for psych")
                }
            case .orange, .stripes, .colored, .psychedelic, .floralPattern, .texture, .watercolor:
                // Image backgrounds - render similar to psych
                let (imageName, imageType) = imageNameAndType(for: project.backgroundType)
                if let bgImage = loadBackgroundImage(imageName: imageName, imageType: imageType) {
                    // Use scaleAspectFill to match editor
                    let bgAspect = bgImage.size.width / bgImage.size.height
                    let screenAspect = size.width / size.height
                    
                    var drawSize = size
                    if bgAspect > screenAspect {
                        // Background is wider, scale to height and extend width
                        drawSize.height = size.height + 100 // Extra 50pt on each edge
                        drawSize.width = drawSize.height * bgAspect
                    } else {
                        // Background is taller, scale to width and extend height
                        drawSize.width = size.width + 100 // Extra 50pt on each edge
                        drawSize.height = drawSize.width / bgAspect
                    }
                    
                    // Center the background image with offset
                    let drawRect = CGRect(
                        x: (size.width - drawSize.width) / 2,
                        y: (size.height - drawSize.height) / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                    
                    bgImage.draw(in: drawRect)
                    print("🎨 Drew background (\(imageName).\(imageType)) at \(drawRect)")
                } else {
                    // Fallback to black background
                    ctx.setFillColor(UIColor.black.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: size))
                    print("🎨 Drew fallback black background for: \(imageName).\(imageType)")
                }
            case .fireworks, .mountains, .waves, .tiny, .medium, .small:
                // Video backgrounds - extract first frame for static export
                let videoName = videoName(for: project.backgroundType)
                if let videoFrame = extractFirstFrame(videoName: videoName) {
                    // Use scaleAspectFill to match editor
                    let videoAspect = videoFrame.size.width / videoFrame.size.height
                    let screenAspect = size.width / size.height
                    
                    var drawSize = size
                    if videoAspect > screenAspect {
                        // Video is wider, scale to height and extend width
                        drawSize.height = size.height + 100 // Extra 50pt on each edge
                        drawSize.width = drawSize.height * videoAspect
                    } else {
                        // Video is taller, scale to width and extend height
                        drawSize.width = size.width + 100 // Extra 50pt on each edge
                        drawSize.height = drawSize.width / videoAspect
                    }
                    
                    // Center the video frame with offset
                    let drawRect = CGRect(
                        x: (size.width - drawSize.width) / 2,
                        y: (size.height - drawSize.height) / 2,
                        width: drawSize.width,
                        height: drawSize.height
                    )
                    
                    videoFrame.draw(in: drawRect)
                    print("🎬 Drew video background (\(videoName)) first frame at \(drawRect)")
                } else {
                    // Fallback to black background
                    ctx.setFillColor(UIColor.black.cgColor)
                    ctx.fill(CGRect(origin: .zero, size: size))
                    print("🎬 Drew fallback black background for video: \(videoName)")
                }
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
                
                // Removed: Image-specific drawing rendering - drawing is now always canvas-wide
                
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
    
    // Helper function to load psych image (matching editor)
    private static func loadPsychImage() -> UIImage? {
        // Try multiple possible names and methods (matching editor)
        let possibleNames = ["psych", "psych.jpg", "psych.png"]
        
        // First try UIImage(named:) - this is most reliable if file is in bundle
        for name in possibleNames {
            if let image = UIImage(named: name) {
                print("🎨 Found psych image using UIImage(named: \"\(name)\"), size: \(image.size)")
                return image
            }
        }
        
        // Then try loading from Resources folder path
        if let path = Bundle.main.path(forResource: "psych", ofType: "jpg"),
           let image = UIImage(contentsOfFile: path) {
            print("🎨 Found psych.jpg at path: \(path), size: \(image.size)")
            return image
        }
        
        // Try PNG version
        if let path = Bundle.main.path(forResource: "psych", ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            print("🎨 Found psych.png at path: \(path), size: \(image.size)")
            return image
        }
        
        // Try finding in main bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let psychJPGPath = (resourcePath as NSString).appendingPathComponent("psych.jpg")
            if FileManager.default.fileExists(atPath: psychJPGPath),
               let image = UIImage(contentsOfFile: psychJPGPath) {
                print("🎨 Found and loaded psych.jpg from resourcePath, size: \(image.size)")
                return image
            }
        }
        
        print("❌ Failed to load psych image from any source")
        return nil
    }
    
    // Helper function to get image name and type for background type
    private static func imageNameAndType(for backgroundType: BackgroundType) -> (name: String, type: String) {
        switch backgroundType {
        case .orange: return ("orange", "png")
        case .stripes: return ("stripes", "jpg")
        case .colored: return ("colored-7292420_1920", "jpg")
        case .psychedelic: return ("psychedelic-9957735_1920", "jpg")
        case .floralPattern: return ("floral-pattern-7411179_1280", "png")
        case .texture: return ("texture-794826_1280", "png")
        case .watercolor: return ("watercolor-7129105_1920", "png")
        default: return ("", "jpg")
        }
    }
    
    // Helper function to load background image
    private static func loadBackgroundImage(imageName: String, imageType: String) -> UIImage? {
        let nameWithExt = "\(imageName).\(imageType)"
        
        // Try UIImage(named:) first - most reliable if file is in bundle
        if let image = UIImage(named: imageName) {
            print("🎨 Found \(imageName) image using UIImage(named:), size: \(image.size)")
            return image
        }
        
        // Try with extension in name
        if let image = UIImage(named: nameWithExt) {
            print("🎨 Found \(nameWithExt) image using UIImage(named:), size: \(image.size)")
            return image
        }
        
        // Try loading from Resources folder path
        if let path = Bundle.main.path(forResource: imageName, ofType: imageType),
           let image = UIImage(contentsOfFile: path) {
            print("🎨 Found \(nameWithExt) at path: \(path), size: \(image.size)")
            return image
        }
        
        // Try finding in main bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let imagePath = (resourcePath as NSString).appendingPathComponent(nameWithExt)
            if FileManager.default.fileExists(atPath: imagePath),
               let image = UIImage(contentsOfFile: imagePath) {
                print("🎨 Found and loaded \(nameWithExt) from resourcePath, size: \(image.size)")
                return image
            }
        }
        
        print("❌ Failed to load background image from any source: \(nameWithExt)")
        return nil
    }
    
    // Helper function to get video filename for background type
    private static func videoName(for backgroundType: BackgroundType) -> String {
        switch backgroundType {
        case .fireworks: return "fireworks"
        case .mountains: return "mountains"
        case .waves: return "waves"
        case .tiny: return "214784_tiny"
        case .medium: return "305858_medium"
        case .small: return "310961_small"
        default: return ""
        }
    }
    
    // Extract first frame from video as UIImage for static export
    private static func extractFirstFrame(videoName: String) -> UIImage? {
        guard let videoURL = loadVideoURL(videoName: videoName) else {
            print("❌ Failed to find video file: \(videoName).mp4")
            return nil
        }
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            let uiImage = UIImage(cgImage: cgImage)
            print("🎬 Extracted first frame from \(videoName).mp4, size: \(uiImage.size)")
            return uiImage
        } catch {
            print("❌ Failed to extract first frame from \(videoName).mp4: \(error)")
            return nil
        }
    }
    
    // Helper function to load video URL from bundle
    private static func loadVideoURL(videoName: String) -> URL? {
        // Try loading from Resources folder
        if let path = Bundle.main.path(forResource: videoName, ofType: "mp4") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                print("🎬 Found video at path: \(path)")
                return url
            }
        }
        
        // Try loading from bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let videoPath = (resourcePath as NSString).appendingPathComponent("\(videoName).mp4")
            if FileManager.default.fileExists(atPath: videoPath) {
                let url = URL(fileURLWithPath: videoPath)
                print("🎬 Found video at resourcePath: \(videoPath)")
                return url
            }
        }
        
        // Try loading from main bundle
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            print("🎬 Found video using Bundle.main.url: \(url)")
            return url
        }
        
        print("❌ Failed to find video file: \(videoName).mp4")
        return nil
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

