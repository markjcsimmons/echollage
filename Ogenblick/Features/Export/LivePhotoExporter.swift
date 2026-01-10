import AVFoundation
import UIKit
import Photos

/// Exports a static collage image with audio as a Live Photo
class LivePhotoExporter {
    
    enum ExportError: Error {
        case imageRenderingFailed
        case audioNotFound
        case exportFailed(String)
        case saveFailed(String)
    }
    
    /// Export a collage with audio as a Live Photo
    /// - Parameters:
    ///   - image: The rendered collage image
    ///   - audioURL: URL to the audio file
    ///   - duration: Duration of the audio
    ///   - outputDirectory: Where to save the files
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: URLs of the image and video components
    static func export(
        image: UIImage,
        audioURL: URL,
        duration: TimeInterval,
        outputDirectory: URL,
        progress: @escaping (Double) -> Void
    ) async throws -> (imageURL: URL, videoURL: URL) {
        
        // Generate unique identifier for this Live Photo
        let assetIdentifier = UUID().uuidString
        
        // Create output URLs
        let imageURL = outputDirectory.appendingPathComponent("live_photo_\(assetIdentifier).jpg")
        let videoURL = outputDirectory.appendingPathComponent("live_photo_\(assetIdentifier).mov")
        
        // Delete existing files if present
        try? FileManager.default.removeItem(at: imageURL)
        try? FileManager.default.removeItem(at: videoURL)
        
        // Save image with Live Photo metadata
        try await saveImageWithMetadata(image: image, to: imageURL, assetIdentifier: assetIdentifier)
        progress(0.3)
        
        // Create video component (MOV format for Live Photos)
        try await createVideoComponent(
            image: image,
            audioURL: audioURL,
            duration: duration,
            outputURL: videoURL,
            assetIdentifier: assetIdentifier,
            progress: { videoProgress in
                progress(0.3 + videoProgress * 0.7)
            }
        )
        
        progress(1.0)
        print("✅ Live Photo components created: \(imageURL.lastPathComponent), \(videoURL.lastPathComponent)")
        
        return (imageURL, videoURL)
    }
    
    /// Save image with Live Photo metadata
    private static func saveImageWithMetadata(
        image: UIImage,
        to url: URL,
        assetIdentifier: String
    ) async throws {
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw ExportError.imageRenderingFailed
        }
        
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let uniformTypeIdentifier = CGImageSourceGetType(source) else {
            throw ExportError.imageRenderingFailed
        }
        
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, uniformTypeIdentifier, 1, nil) else {
            throw ExportError.imageRenderingFailed
        }
        
        // Add Live Photo metadata
        let metadata: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: [
                "17": assetIdentifier // Live Photo identifier
            ]
        ]
        
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.imageRenderingFailed
        }
        
        print("📸 Saved image with Live Photo metadata")
    }
    
    /// Create video component (MOV) with Live Photo metadata
    private static func createVideoComponent(
        image: UIImage,
        audioURL: URL,
        duration: TimeInterval,
        outputURL: URL,
        assetIdentifier: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        
        guard let cgImage = image.cgImage else {
            throw ExportError.imageRenderingFailed
        }
        
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Create video writer (MOV format)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Video settings (H.264)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: imageSize.width,
            AVVideoHeightKey: imageSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 100_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 1
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
        
        // Audio settings (AAC, stereo)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = false
        writer.add(audioInput)
        
        // Add Live Photo metadata
        writer.metadata = [
            makeMetadataItem(identifier: .quickTimeMetadataContentIdentifier, value: assetIdentifier),
            makeMetadataItem(identifier: .quickTimeMetadataLocationISO6709, value: "+00.0000+000.0000/") // Required for Live Photo
        ]
        
        // Start writing
        guard writer.startWriting() else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
        
        writer.startSession(atSourceTime: .zero)
        
        // Write single video frame
        let frameDuration = CMTime(seconds: duration, preferredTimescale: 600)
        
        guard let pixelBuffer = pixelBuffer(from: cgImage, size: imageSize) else {
            throw ExportError.imageRenderingFailed
        }
        
        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: .zero)
        videoInput.markAsFinished()
        
        progress(0.5)
        
        // Write audio
        let audioAsset = AVAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExportError.audioNotFound
        }
        
        await withCheckedContinuation { continuation in
            audioInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audioQueue")) {
                let reader: AVAssetReader
                do {
                    reader = try AVAssetReader(asset: audioAsset)
                } catch {
                    audioInput.markAsFinished()
                    continuation.resume()
                    return
                }
                
                let readerOutput = AVAssetReaderTrackOutput(
                    track: audioTrack,
                    outputSettings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsNonInterleaved: false
                    ]
                )
                reader.add(readerOutput)
                reader.startReading()
                
                var shouldStop = false
                while audioInput.isReadyForMoreMediaData && !shouldStop {
                    autoreleasepool {
                        if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                            audioInput.append(sampleBuffer)
                        } else {
                            shouldStop = true
                        }
                    }
                }
                
                audioInput.markAsFinished()
                continuation.resume()
            }
        }
        
        // Finish writing
        await writer.finishWriting()
        
        if writer.status == .completed {
            progress(1.0)
            print("✅ MOV video component created")
        } else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Unknown error")
        }
    }
    
    /// Create metadata item
    private static func makeMetadataItem(identifier: AVMetadataIdentifier, value: String) -> AVMutableMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
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
}












