import UIKit

struct ImageSplitter {
    /// Split an image along a path, returning two images (top and bottom pieces)
    /// - Parameters:
    ///   - image: The original image to split
    ///   - alongPath: The UIBezierPath defining the split line
    /// - Returns: Tuple of (topImage, bottomImage) as UIImage? optionals
    static func splitImage(_ image: UIImage, alongPath path: UIBezierPath) -> (UIImage?, UIImage?) {
        guard let cgImage = image.cgImage else {
            return (nil, nil)
        }
        
        let size = image.size
        let scale = image.scale
        
        // Create a closed path by extending to edges
        let extendedPath = extendPathToEdges(path, imageSize: size)
        
        // Create masks for top and bottom regions
        guard let topMask = createMask(for: extendedPath, size: size, invert: false),
              let bottomMask = createMask(for: extendedPath, size: size, invert: true) else {
            return (nil, nil)
        }
        
        // Apply masks to create split images
        let topImage = applyMask(topMask, to: cgImage, size: size, scale: scale)
        let bottomImage = applyMask(bottomMask, to: cgImage, size: size, scale: scale)
        
        return (topImage, bottomImage)
    }
    
    // MARK: - Private Helpers
    
    private static func extendPathToEdges(_ path: UIBezierPath, imageSize: CGSize) -> UIBezierPath {
        guard !path.isEmpty else {
            return path
        }
        
        // Get first and last points from the path
        var firstPoint: CGPoint?
        var lastPoint: CGPoint?
        
        path.cgPath.applyWithBlock { element in
            let point = element.pointee.points[0]
            if element.pointee.type == .moveToPoint {
                firstPoint = point
            }
            lastPoint = point // Track the last point we encounter
        }
        
        guard let first = firstPoint, let last = lastPoint else {
            return path
        }
        
        // Build extended path: top edge -> original path -> bottom edge
        let extended = UIBezierPath()
        
        // Start from top edge if first point isn't at the top
        if first.y > 0 {
            extended.move(to: CGPoint(x: first.x, y: 0))
            extended.addLine(to: first)
        } else {
            extended.move(to: first)
        }
        
        // Add all points from the original path (skip the first moveToPoint since we already moved there)
        var isFirstMove = true
        path.cgPath.applyWithBlock { element in
            let point = element.pointee.points[0]
            if element.pointee.type == .moveToPoint {
                if !isFirstMove {
                    extended.move(to: point)
                }
                isFirstMove = false
            } else if element.pointee.type == .addLineToPoint {
                extended.addLine(to: point)
            }
        }
        
        // Extend to bottom edge if last point isn't at the bottom
        if last.y < imageSize.height {
            extended.addLine(to: CGPoint(x: last.x, y: imageSize.height))
        }
        
        // Close the path to create a region
        extended.close()
        
        return extended
    }
    
    private static func createMask(for path: UIBezierPath, size: CGSize, invert: Bool) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let maskImage = renderer.image { context in
            let cgContext = context.cgContext
            
            if invert {
                // Fill entire area
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.fill(CGRect(origin: .zero, size: size))
                
                // Then clear the path area (subtract)
                cgContext.setFillColor(UIColor.black.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.fillPath()
            } else {
                // Fill only the path area
                cgContext.setFillColor(UIColor.white.cgColor)
                cgContext.addPath(path.cgPath)
                cgContext.fillPath()
            }
        }
        
        return maskImage.cgImage
    }
    
    private static func applyMask(_ mask: CGImage, to image: CGImage, size: CGSize, scale: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            
            // Clip to mask
            cgContext.clip(to: rect, mask: mask)
            
            // Draw the image
            cgContext.draw(image, in: rect)
        }
    }
}
