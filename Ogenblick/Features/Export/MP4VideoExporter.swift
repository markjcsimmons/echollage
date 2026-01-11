import AVFoundation
import UIKit
import Foundation

/// Exports a collage image with audio as an MP4 video using AVMutableComposition
/// This approach is more reliable than AVAssetWriter for static images
class MP4VideoExporter {
    
    enum ExportError: Error {
        case imageRenderingFailed
        case audioNotFound
        case exportFailed(String)
    }
    
    /// Export a collage with audio as an MP4 video
    /// - Parameters:
    ///   - image: The rendered collage image
    ///   - audioURL: URL to the audio file
    ///   - duration: Duration of the audio
    ///   - outputURL: Where to save the video file
    ///   - musicMetadata: Optional music metadata to display
    ///   - progress: Progress callback (0.0 to 1.0)
    static func export(
        image: UIImage,
        audioURL: URL,
        duration: TimeInterval,
        outputURL: URL,
        musicMetadata: MusicMetadata? = nil,
        progress: @escaping (Double) -> Void
    ) async throws {
        
        // Delete existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        progress(0.1)
        
        // Add overlay with app name (and music metadata if available)
        let finalImage = addOverlay(to: image, musicMetadata: musicMetadata)
        
        guard let cgImage = finalImage.cgImage else {
            throw ExportError.imageRenderingFailed
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Create a temporary video file with a single frame using AVAssetWriter
        // This is simpler and more reliable than trying to append multiple frames
        let tempVideoURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp_video_\(UUID().uuidString).mov")
        try? FileManager.default.removeItem(at: tempVideoURL)
        
        // Create video writer for temporary file
        let writer = try AVAssetWriter(outputURL: tempVideoURL, fileType: .mov)
        
        // Video settings (H.264, high quality)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: imageSize.width,
            AVVideoHeightKey: imageSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: imageSize.width,
            kCVPixelBufferHeightKey as String: imageSize.height
        ]
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )
        
        writer.add(videoInput)
        
        // Start writing
        guard writer.startWriting() else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Failed to start writing")
        }
        
        writer.startSession(atSourceTime: .zero)
        progress(0.2)
        
        // Append single frame at time zero
        guard let pixelBuffer = pixelBuffer(from: cgImage, size: imageSize) else {
            throw ExportError.imageRenderingFailed
        }
        
        let frameTime = CMTime.zero
        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) else {
            throw ExportError.exportFailed("Failed to append video frame")
        }
        
        videoInput.markAsFinished()
        progress(0.3)
        
        // Finish writing temporary video
        await writer.finishWriting()
        
        guard writer.status == .completed else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Failed to write video")
        }
        
        progress(0.4)
        
        // Now use AVMutableComposition to combine the single-frame video with audio
        // This will stretch the video frame to match the audio duration
        let composition = AVMutableComposition()
        
        // Add video track from temporary file
        let tempVideoAsset = AVAsset(url: tempVideoURL)
        guard let videoTrack = try await tempVideoAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.exportFailed("Failed to load video track")
        }
        
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        
        let videoDuration = CMTime(seconds: duration, preferredTimescale: 600)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 0.1, preferredTimescale: 600)),
            of: videoTrack,
            at: .zero
        )
        compositionVideoTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: CMTime(seconds: 0.1, preferredTimescale: 600)),
            toDuration: videoDuration
        )
        
        progress(0.5)
        
        // Add audio track
        let audioAsset = AVAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.audioNotFound
        }
        
        // Get the actual audio duration and time range
        let audioDuration = try await audioAsset.load(.duration)
        let audioTimeRange = try await audioTrack.load(.timeRange)
        print("📊 Audio asset duration: \(audioDuration.seconds)s")
        print("📊 Audio track time range: start=\(audioTimeRange.start.seconds)s, duration=\(audioTimeRange.duration.seconds)s")
        
        // Use the full duration - prefer track duration over asset duration
        // The track's timeRange.duration represents the actual available audio data
        let fullDuration = audioTimeRange.duration
        print("📊 Using full audio duration: \(fullDuration.seconds)s")
        
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )!
        
        // Insert the full audio track - insertTimeRange's timeRange is relative to the source track
        // For audio files, timeRange usually starts at .zero, so we insert from .zero to fullDuration
        let sourceTimeRange = CMTimeRange(start: .zero, duration: fullDuration)
        print("📊 Inserting audio time range: start=\(sourceTimeRange.start.seconds)s, duration=\(sourceTimeRange.duration.seconds)s")
        
        try compositionAudioTrack.insertTimeRange(
            sourceTimeRange,
            of: audioTrack,
            at: .zero
        )
        
        // Verify the inserted track duration
        let insertedDuration = try await compositionAudioTrack.load(.timeRange).duration
        print("📊 Inserted audio track duration: \(insertedDuration.seconds)s")
        
        // Verify composition duration
        let compositionDuration = try await composition.load(.duration)
        print("📊 Composition duration: \(compositionDuration.seconds)s")
        
        progress(0.6)
        
        // Export using AVAssetExportSession
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.exportFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)
        
        print("📊 Export session time range: start=0, duration=\(compositionDuration.seconds)s")
        
        // Export synchronously using async/await
        await exportSession.export()
        
        progress(0.9)
        
        // Clean up temporary file
        try? FileManager.default.removeItem(at: tempVideoURL)
        
        if exportSession.status == .completed {
            progress(1.0)
            print("✅ MP4 video created successfully: \(outputURL.lastPathComponent)")
        } else {
            throw ExportError.exportFailed(exportSession.error?.localizedDescription ?? "Export failed")
        }
    }
    
    /// Create pixel buffer from CGImage
    private static func pixelBuffer(from cgImage: CGImage, size: CGSize) -> CVPixelBuffer? {
        let options: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32ARGB,
            options as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        )
        
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))
        
        return buffer
    }
    
    /// Add overlay with app name (and music metadata if available) at bottom
    private static func addOverlay(to image: UIImage, musicMetadata: MusicMetadata?) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            // Draw the original image
            image.draw(at: .zero)
            
            // Draw rounded rectangle (lozenge) at bottom
            let hasMusic = musicMetadata != nil
            // Allow for up to 3 lines of text + app name + padding
            let lozengeHeight: CGFloat = hasMusic ? 100 : 50
            let lozengePadding: CGFloat = 20
            let lozengeRect = CGRect(
                x: lozengePadding,
                y: image.size.height - lozengeHeight - lozengePadding,
                width: image.size.width - (lozengePadding * 2),
                height: lozengeHeight
            )
            
            // Draw rounded rectangle background with semi-transparent black
            let lozengePath = UIBezierPath(
                roundedRect: lozengeRect,
                cornerRadius: lozengeHeight / 2
            )
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
            context.cgContext.addPath(lozengePath.cgPath)
            context.cgContext.fillPath()
            
            // Draw text
            let textStyle = NSMutableParagraphStyle()
            textStyle.alignment = .center
            textStyle.lineBreakMode = .byWordWrapping // Enable word wrapping for multi-line text
            
            // Music info (title and artist) - only if present
            if let music = musicMetadata {
                let musicText = "\(music.title) • \(music.artist)"
                let horizontalPadding: CGFloat = 30 // More space on each side
                let verticalPadding: CGFloat = 12 // Slightly reduced for better fit
                let maxWidth = lozengeRect.width - (horizontalPadding * 2)
                
                // Use font that allows multi-line wrapping
                let fontSize: CGFloat = 14 // Slightly smaller to fit 3 lines better
                let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
                
                var musicAttrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: textStyle
                ]
                
                // Calculate the bounding rect for the text to see how many lines it needs
                let constraintSize = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
                let boundingRect = (musicText as NSString).boundingRect(
                    with: constraintSize,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: musicAttrs,
                    context: nil
                )
                
                // Use the calculated height, but cap at 3 lines worth of height
                let lineHeight = font.lineHeight
                let maxHeightFor3Lines = lineHeight * 3
                let textHeight = min(boundingRect.height, maxHeightFor3Lines)
                
                // Draw text with multi-line wrapping (no truncation)
                let musicTextRect = CGRect(
                    x: lozengeRect.minX + horizontalPadding,
                    y: lozengeRect.minY + verticalPadding,
                    width: maxWidth,
                    height: textHeight
                )
                
                // Use NSString drawing which supports multi-line wrapping
                (musicText as NSString).draw(
                    with: musicTextRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: musicAttrs,
                    context: nil
                )
            }
            
            // App name (always shown)
            let appName = "Échollage"
            let horizontalPadding: CGFloat = 30 // Match music text padding
            let appNameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: hasMusic ? 12 : 16, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(hasMusic ? 0.8 : 1.0),
                .paragraphStyle: textStyle
            ]
            let appNameTextSize = appName.size(withAttributes: appNameAttrs)
            let appNameTextRect = CGRect(
                x: lozengeRect.minX + horizontalPadding,
                y: hasMusic ? (lozengeRect.maxY - appNameTextSize.height - 15) : (lozengeRect.midY - appNameTextSize.height / 2),
                width: lozengeRect.width - (horizontalPadding * 2),
                height: appNameTextSize.height
            )
            appName.draw(in: appNameTextRect, withAttributes: appNameAttrs)
        }
    }
}
