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
    
    /// Export a collage with a **playing** video background, foreground overlay, and audio.
    /// Uses AVMutableVideoComposition + Core Animation to composite the overlay on the video.
    static func exportWithVideoBackground(
        backgroundVideoURL: URL,
        overlayImage: UIImage,
        audioURL: URL,
        outputURL: URL,
        canvasSize: CGSize,
        screenScale: CGFloat,
        musicMetadata: MusicMetadata? = nil,
        progress: @escaping (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        progress(0.05)
        
        let finalOverlay = addOverlay(to: overlayImage, musicMetadata: musicMetadata)
        guard let overlayCGImage = finalOverlay.cgImage else {
            throw ExportError.imageRenderingFailed
        }
        
        let bgAsset = AVAsset(url: backgroundVideoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let bgVideoTrack = try await bgAsset.loadTracks(withMediaType: .video).first else {
            throw ExportError.exportFailed("Failed to load background video track")
        }
        guard let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.audioNotFound
        }
        
        let audioTrackRange = try await sourceAudioTrack.load(.timeRange)
        let totalDuration = audioTrackRange.duration
        let bgDuration = try await bgAsset.load(.duration)
        let videoNaturalSize = try await bgVideoTrack.load(.naturalSize)
        let videoPreferredTransform = try await bgVideoTrack.load(.preferredTransform)
        
        let transformedRect = CGRect(origin: .zero, size: videoNaturalSize)
            .applying(videoPreferredTransform)
        let displaySize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
        
        progress(0.1)
        
        // Pixel dimensions for the output video
        let renderSize = CGSize(
            width: canvasSize.width * screenScale,
            height: canvasSize.height * screenScale
        )
        
        let composition = AVMutableComposition()
        
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Failed to create composition video track")
        }
        
        guard let compAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Failed to create composition audio track")
        }
        
        // Loop the background video to fill the entire audio duration
        var currentTime = CMTime.zero
        while currentTime < totalDuration {
            let remaining = totalDuration - currentTime
            let insertDuration = CMTimeMinimum(bgDuration, remaining)
            try compVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: bgVideoTrack,
                at: currentTime
            )
            currentTime = currentTime + insertDuration
        }
        
        // Insert the full audio
        try compAudioTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: totalDuration),
            of: sourceAudioTrack,
            at: .zero
        )
        
        progress(0.3)
        
        // --- Video composition: scale video to fill + overlay ---
        
        // Transform: preferredTransform -> scale to aspect-fill renderSize -> center
        var tx = videoPreferredTransform
        tx.tx -= transformedRect.origin.x
        tx.ty -= transformedRect.origin.y
        
        let fillScale = max(
            renderSize.width / displaySize.width,
            renderSize.height / displaySize.height
        )
        let scaledW = displaySize.width * fillScale
        let scaledH = displaySize.height * fillScale
        let offsetX = (renderSize.width - scaledW) / 2
        let offsetY = (renderSize.height - scaledH) / 2
        
        let finalTransform = tx
            .concatenating(CGAffineTransform(scaleX: fillScale, y: fillScale))
            .concatenating(CGAffineTransform(translationX: offsetX, y: offsetY))
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compVideoTrack
        )
        layerInstruction.setTransform(finalTransform, at: .zero)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        instruction.layerInstructions = [layerInstruction]
        
        // Core Animation layer tree: parent -> [videoLayer, overlayLayer]
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)
        
        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = overlayCGImage
        overlayLayer.contentsGravity = .resize
        overlayLayer.isGeometryFlipped = true
        
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [instruction]
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        progress(0.5)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Failed to create export session")
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        exportSession.timeRange = CMTimeRange(start: .zero, duration: totalDuration)
        
        print("🎬 Exporting video-background MP4: renderSize=\(renderSize), duration=\(totalDuration.seconds)s")
        
        await exportSession.export()
        
        progress(0.95)
        
        guard exportSession.status == .completed else {
            throw ExportError.exportFailed(
                exportSession.error?.localizedDescription ?? "Video background export failed"
            )
        }
        
        progress(1.0)
        print("✅ Video-background MP4 created: \(outputURL.lastPathComponent)")
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
        // Guarantee cleanup of the temp .mov even if we throw early.
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }
        
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
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Failed to create composition video track")
        }
        
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
        
        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ExportError.exportFailed("Failed to create composition audio track")
        }
        
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
            let lozengeOuterPadding: CGFloat = 20
            let lozengeInnerHorizontalPadding: CGFloat = 30
            let lozengeInnerVerticalPadding: CGFloat = 12
            let gapBetweenMusicAndAppName: CGFloat = 4
            
            // Keep width full-size; adjust height dynamically based on text.
            let lozengeWidth = image.size.width - (lozengeOuterPadding * 2)
            let maxTextWidth = lozengeWidth - (lozengeInnerHorizontalPadding * 2)
            
            // Draw rounded rectangle background with semi-transparent black
            let textStyle = NSMutableParagraphStyle()
            textStyle.alignment = .center
            textStyle.lineBreakMode = .byWordWrapping // Enable word wrapping for multi-line text
            
            // App name (always shown)
            let appName = "Échollage"
            let appNameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: hasMusic ? 12 : 16, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(hasMusic ? 0.8 : 1.0),
                .paragraphStyle: textStyle
            ]
            let appNameTextSize = appName.size(withAttributes: appNameAttrs)

            // Music info (title and artist) - only if present
            let fontSize: CGFloat = 14 // Slightly smaller to fit 3 lines better
            let musicFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let musicAttrs: [NSAttributedString.Key: Any] = [
                .font: musicFont,
                .foregroundColor: UIColor.white,
                .paragraphStyle: textStyle
            ]

            var musicText: String? = nil
            var musicTextHeight: CGFloat = 0
            if let music = musicMetadata {
                let combined = "\(music.title) • \(music.artist)"
                musicText = combined
                
                let constraintSize = CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude)
                let boundingRect = (combined as NSString).boundingRect(
                    with: constraintSize,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: musicAttrs,
                    context: nil
                )
                
                // Cap at 3 lines
                let maxHeightFor3Lines = musicFont.lineHeight * 3
                musicTextHeight = min(boundingRect.height, maxHeightFor3Lines)
            }
            
            let contentHeight: CGFloat = {
                if musicText != nil {
                    return musicTextHeight + gapBetweenMusicAndAppName + appNameTextSize.height
                } else {
                    return appNameTextSize.height
                }
            }()
            
            let computedLozengeHeight = contentHeight + (lozengeInnerVerticalPadding * 2)
            let minLozengeHeight: CGFloat = hasMusic ? 64 : 50
            let lozengeHeight = max(minLozengeHeight, computedLozengeHeight)
            
            let lozengeRect = CGRect(
                x: lozengeOuterPadding,
                y: image.size.height - lozengeHeight - lozengeOuterPadding,
                width: lozengeWidth,
                height: lozengeHeight
            )
            
            let lozengePath = UIBezierPath(
                roundedRect: lozengeRect,
                cornerRadius: lozengeHeight / 2
            )
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.75).cgColor)
            context.cgContext.addPath(lozengePath.cgPath)
            context.cgContext.fillPath()
            
            // Draw text
            if let musicText {
                let maxWidth = maxTextWidth
                let textHeight = musicTextHeight
                let topY = lozengeRect.minY + lozengeInnerVerticalPadding
                let musicTextRect = CGRect(
                    x: lozengeRect.minX + lozengeInnerHorizontalPadding,
                    y: topY,
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
                
                let appNameTextRect = CGRect(
                    x: lozengeRect.minX + lozengeInnerHorizontalPadding,
                    y: musicTextRect.maxY + gapBetweenMusicAndAppName,
                    width: lozengeRect.width - (lozengeInnerHorizontalPadding * 2),
                    height: appNameTextSize.height
                )
                appName.draw(in: appNameTextRect, withAttributes: appNameAttrs)
            } else {
                // No music: center app name in the pill.
                let appNameTextRect = CGRect(
                    x: lozengeRect.minX + lozengeInnerHorizontalPadding,
                    y: lozengeRect.midY - appNameTextSize.height / 2,
                    width: lozengeRect.width - (lozengeInnerHorizontalPadding * 2),
                    height: appNameTextSize.height
                )
                appName.draw(in: appNameTextRect, withAttributes: appNameAttrs)
            }
        }
    }
}
