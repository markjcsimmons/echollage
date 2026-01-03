import Foundation
import UIKit
import Vision

/// Utility for removing backgrounds from images containing people using Vision framework
class BackgroundRemover {
    
    /// Remove background from an image using person segmentation
    /// - Parameter image: The input image
    /// - Returns: Image with background removed (transparent), or nil if no person detected or processing failed
    static func removeBackground(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else {
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
                
                // Apply mask to original image
                guard let resultImage = self.applyMask(observation, to: image) else {
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
        guard let cgImage = image.cgImage else { return nil }
        
        let pixelBuffer = observation.pixelBuffer
        let imageSize = image.size
        
        // Create Core Image context
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])
        
        // Convert pixel buffer to CIImage
        let maskCIImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // Scale mask to match image size
        let maskExtent = maskCIImage.extent
        let scaleX = imageSize.width / maskExtent.width
        let scaleY = imageSize.height / maskExtent.height
        let scaledMask = maskCIImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Convert mask to CGImage
        guard let maskCGImage = ciContext.createCGImage(scaledMask, from: CGRect(origin: .zero, size: imageSize)) else {
            print("❌ BackgroundRemover: Failed to create mask CGImage")
            return nil
        }
        
        // Create output image with transparent background
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        
        let renderer = UIGraphicsImageRenderer(size: imageSize, format: format)
        return renderer.image { rendererContext in
            let cgContext = rendererContext.cgContext
            let rect = CGRect(origin: .zero, size: imageSize)
            
            // Save graphics state
            cgContext.saveGState()
            
            // Clip to mask (person area)
            cgContext.clip(to: rect, mask: maskCGImage)
            
            // Draw the original image (only in the clipped area)
            cgContext.draw(cgImage, in: rect)
            
            // Restore graphics state
            cgContext.restoreGState()
        }
    }
}

