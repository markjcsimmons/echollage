import Foundation
import UIKit
import Vision
import CoreVideo

/// Utility for removing backgrounds from images containing people using Vision framework
class BackgroundRemover {
    
    /// Remove background from an image using person segmentation
    /// - Parameter image: The input image
    /// - Returns: Image with background removed (transparent), or nil if no person detected or processing failed
    static func removeBackground(from image: UIImage) async -> UIImage? {
        // Normalize image orientation first to prevent rotation issues
        let normalizedImage = normalizeImageOrientation(image)
        guard let cgImage = normalizedImage.cgImage else {
            print("❌ BackgroundRemover: Failed to get CGImage")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if let error = error {
                    print("❌ BackgroundRemover: Vision request error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNPixelBufferObservation],
                      let observation = observations.first else {
                    print("⚠️ BackgroundRemover: No person detected in image")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Apply mask to normalized image
                guard let resultImage = self.applyMask(observation, to: normalizedImage) else {
                    print("❌ BackgroundRemover: Failed to apply mask")
                    continuation.resume(returning: nil)
                    return
                }
                
                print("✅ BackgroundRemover: Successfully removed background")
                continuation.resume(returning: resultImage)
            }
            
            // Use accurate quality for better results
            request.qualityLevel = .accurate
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("❌ BackgroundRemover: Failed to perform request: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Check if an image contains a person (for conditional UI)
    /// - Parameter image: The input image
    /// - Returns: True if a person is detected, false otherwise
    static func containsPerson(_ image: UIImage) async -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        return await withCheckedContinuation { continuation in
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if error != nil {
                    continuation.resume(returning: false)
                    return
                }
                
                guard let observations = request.results as? [VNPixelBufferObservation],
                      !observations.isEmpty else {
                    continuation.resume(returning: false)
                    return
                }
                
                continuation.resume(returning: true)
            }
            
            request.qualityLevel = .fast // Use fast for detection only
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private static func applyMask(_ observation: VNPixelBufferObservation, to image: UIImage) -> UIImage? {
        // Image is already normalized at this point
        guard let cgImage = image.cgImage else { return nil }
        
        let pixelBuffer = observation.pixelBuffer
        
        // Validate mask quality - check if mask has sufficient content (not empty/too small)
        // This prevents applying masks that would result in a fully transparent image
        if !isValidMask(pixelBuffer) {
            print("⚠️ BackgroundRemover: Mask is invalid or too small - rejecting to prevent image deletion")
            return nil
        }
        // Use actual pixel dimensions from CGImage, not UIImage.size which may differ
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let imageSize = CGSize(width: pixelWidth, height: pixelHeight)
        
        print("🔄 applyMask: image size: \(image.size), pixel size: \(imageSize), orientation: \(image.imageOrientation.rawValue)")
        print("🔄 applyMask: normalized image orientation: \(image.imageOrientation.rawValue), normalized CGImage size: \(cgImage.width)x\(cgImage.height)")
        
        // Get mask dimensions from pixel buffer
        let maskWidth = CVPixelBufferGetWidth(pixelBuffer)
        let maskHeight = CVPixelBufferGetHeight(pixelBuffer)
        let maskSize = CGSize(width: maskWidth, height: maskHeight)
        
        print("🔄 applyMask: mask extent: (0, 0, \(maskWidth), \(maskHeight))")
        let scaleX = imageSize.width / maskSize.width
        let scaleY = imageSize.height / maskSize.height
        print("🔄 applyMask: scale factors: x=\(scaleX), y=\(scaleY)")
        
        // Create mask CGImage directly from pixel buffer to avoid CIImage coordinate issues
        // Lock the pixel buffer to access its data
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Create a bitmap context from the pixel buffer data
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            print("❌ BackgroundRemover: Failed to create color space")
            return nil
        }
        
        // Create the mask CGImage directly from pixel buffer data
        // Vision outputs pixel buffers with top-left origin (UIKit coordinate system)
        // When creating a CGImage from pixel buffer data, we need to ensure correct orientation
        // Since we'll use it with UIGraphicsImageRenderer (which uses top-left origin), 
        // we need to flip vertically because Core Graphics uses bottom-left origin
        
        // Create context for final mask (at target size)
        guard let maskContext = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            print("❌ BackgroundRemover: Failed to create mask context")
            return nil
        }
        
        // Create temporary CGImage from pixel buffer (this reads pixels in buffer order = top-left)
        guard let tempContext = CGContext(
            data: baseAddress,
            width: maskWidth,
            height: maskHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let tempMaskCGImage = tempContext.makeImage() else {
            print("❌ BackgroundRemover: Failed to create temporary mask CGImage")
            return nil
        }
        
        // Draw the mask with flipped context to match UIKit's top-left origin
        // Core Graphics uses bottom-left origin, so we flip vertically
        maskContext.saveGState()
        maskContext.translateBy(x: 0, y: imageSize.height)
        maskContext.scaleBy(x: 1.0, y: -1.0)
        
        // Draw and scale with high quality interpolation
        // Use exact rect at origin to ensure no offset
        maskContext.interpolationQuality = .high
        maskContext.draw(tempMaskCGImage, in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        
        maskContext.restoreGState()
        
        guard let maskCGImage = maskContext.makeImage() else {
            print("❌ BackgroundRemover: Failed to create final mask CGImage")
            return nil
        }
        
        // Create output image with transparent background using pixel dimensions
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        let resultImage = renderer.image { rendererContext in
            let cgContext = rendererContext.cgContext
            let rect = CGRect(origin: .zero, size: imageSize)
            
            // Save graphics state
            cgContext.saveGState()
            
            // Clip to mask (person area) - mask is already correctly oriented for UIKit (top-left origin)
            // Use exact rect at origin (0, 0) to ensure no offset
            let clipRect = CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height)
            cgContext.clip(to: clipRect, mask: maskCGImage)
            
            // Since the mask is correctly positioned with a vertical flip during creation,
            // and the image appears rotated 180 degrees, we need to flip the image context
            // to match the mask. The mask was flipped vertically, so we flip the image
            // context vertically as well to align them.
            // UIGraphicsImageRenderer's context is already flipped for UIKit, but when drawing
            // a CGImage directly with cgContext.draw(), it might interpret it differently.
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: imageSize.height)
            cgContext.scaleBy(x: 1.0, y: -1.0)
            
            // Draw the normalized image's CGImage with the flipped context to match mask
            cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
            
            cgContext.restoreGState()
            
            // Restore graphics state
            cgContext.restoreGState()
        }
        
        print("🔄 applyMask: result image size: \(resultImage.size), orientation: \(resultImage.imageOrientation.rawValue)")
        return resultImage
    }
    
    /// Normalize image orientation to .up by creating a new image
    /// This prevents rotation issues when saving PNG files
    private static func normalizeImageOrientation(_ image: UIImage) -> UIImage {
        // If orientation is already up, return as-is
        if image.imageOrientation == .up {
            return image
        }
        
        // Get the actual pixel dimensions from CGImage
        guard let cgImage = image.cgImage else { return image }
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)
        
        // Create a new image by drawing the original image
        // UIImage.draw() automatically applies the orientation transform
        // Use actual pixel dimensions for consistency with mask creation
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        
        // Use pixel dimensions for the renderer to ensure exact size matching
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        let normalized = renderer.image { _ in
            // UIImage.draw() automatically applies the orientation transform
            // Draw at pixel size to ensure exact dimensions
            image.draw(in: CGRect(origin: .zero, size: pixelSize))
        }
        
        return normalized
    }
    
    /// Validate that a mask has sufficient content (not empty or too small)
    /// - Parameter pixelBuffer: The mask pixel buffer from Vision
    /// - Returns: True if mask is valid and has sufficient content, false otherwise
    private static func isValidMask(_ pixelBuffer: CVPixelBuffer) -> Bool {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let totalPixels = width * height
        
        // Lock buffer to read pixel data
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            print("❌ BackgroundRemover: Failed to get pixel buffer base address")
            return false
        }
        
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        // Vision person segmentation uses kCVPixelFormatType_OneComponent8 (grayscale, 0-255)
        // White pixels (255) indicate person area, black pixels (0) indicate background
        guard pixelFormat == kCVPixelFormatType_OneComponent8 else {
            print("⚠️ BackgroundRemover: Unexpected pixel format: \(pixelFormat)")
            return false
        }
        
        // Count white pixels (values > 128) to determine mask coverage
        var whitePixelCount = 0
        let threshold: UInt8 = 128 // Threshold for considering a pixel as "white" (person area)
        
        for y in 0..<height {
            let rowBase = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: y * bytesPerRow)
            for x in 0..<width {
                let pixelValue = rowBase[x]
                if pixelValue > threshold {
                    whitePixelCount += 1
                }
            }
        }
        
        let coverage = Double(whitePixelCount) / Double(totalPixels)
        let minCoverage = 0.01 // Require at least 1% of pixels to be white (person area)
        
        print("🔄 BackgroundRemover: Mask validation - coverage: \(String(format: "%.2f", coverage * 100))%, white pixels: \(whitePixelCount)/\(totalPixels)")
        
        if coverage < minCoverage {
            print("⚠️ BackgroundRemover: Mask coverage too low (\(String(format: "%.2f", coverage * 100))%) - likely no person detected")
            return false
        }
        
        return true
    }
}
