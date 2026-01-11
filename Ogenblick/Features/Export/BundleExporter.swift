import Foundation
import UIKit
import UniformTypeIdentifiers

enum BundleExporter {
    struct ExportedBundle {
        let bundleURL: URL
        let previewImage: UIImage
    }
    
    /// Exports a project as a .ogenblick bundle (zip with collage PNG + audio + metadata)
    static func exportBundle(project: Project, assetURLProvider: (String) -> URL?) throws -> ExportedBundle {
        guard let collageImage = CollageRenderer.render(project: project, assetURLProvider: assetURLProvider) else {
            throw NSError(domain: "BundleExporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to render collage"])
        }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Save collage as JPEG
        let collageURL = tempDir.appendingPathComponent("collage.jpg")
        guard let jpegData = collageImage.jpegData(compressionQuality: 0.85) else {
            throw NSError(domain: "BundleExporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode collage"])
        }
        try jpegData.write(to: collageURL)
        
        // Copy audio if present
        var audioFileName: String? = nil
        if let audioName = project.audioFileName, let audioSrc = assetURLProvider(audioName) {
            let audioDest = tempDir.appendingPathComponent("audio.m4a")
            try? FileManager.default.copyItem(at: audioSrc, to: audioDest)
            audioFileName = "audio.m4a"
        }
        
        // Write metadata
        let metadata: [String: Any] = [
            "name": project.name,
            "createdAt": ISO8601DateFormatter().string(from: project.createdAt),
            "collageFile": "collage.jpg",
            "audioFile": audioFileName as Any,
            "musicMetadata": project.musicMetadata.map { ["title": $0.title, "artist": $0.artist, "source": $0.source] } as Any
        ]
        let metaData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
        try metaData.write(to: tempDir.appendingPathComponent("metadata.json"))
        
        // Zip the bundle - use .zip extension so it can be opened by standard zip utilities
        let bundleName = "\(project.name.replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(8)).zip"
        let bundleURL = FileManager.default.temporaryDirectory.appendingPathComponent(bundleName)
        try zipDirectory(at: tempDir, to: bundleURL)
        
        // Cleanup temp
        try? FileManager.default.removeItem(at: tempDir)
        
        return ExportedBundle(bundleURL: bundleURL, previewImage: collageImage)
    }
    
    /// Exports just a static PNG share card with metadata overlay
    static func exportStaticCard(project: Project, assetURLProvider: (String) -> URL?) throws -> UIImage {
        guard var collageImage = CollageRenderer.render(project: project, assetURLProvider: assetURLProvider) else {
            throw NSError(domain: "BundleExporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to render collage"])
        }
        
        // Overlay a small "play" icon and music info if present
        let renderer = UIGraphicsImageRenderer(size: collageImage.size)
        collageImage = renderer.image { context in
            collageImage.draw(at: .zero)
            
            // Draw semi-transparent play button in center
            let playSize: CGFloat = 80
            let playRect = CGRect(x: (collageImage.size.width - playSize) / 2,
                                  y: (collageImage.size.height - playSize) / 2,
                                  width: playSize, height: playSize)
            context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.5).cgColor)
            context.cgContext.fillEllipse(in: playRect)
            
            // Simple triangle play icon
            context.cgContext.setFillColor(UIColor.white.cgColor)
            let trianglePath = UIBezierPath()
            let inset: CGFloat = 20
            trianglePath.move(to: CGPoint(x: playRect.minX + inset, y: playRect.minY + inset))
            trianglePath.addLine(to: CGPoint(x: playRect.maxX - inset, y: playRect.midY))
            trianglePath.addLine(to: CGPoint(x: playRect.minX + inset, y: playRect.maxY - inset))
            trianglePath.close()
            context.cgContext.addPath(trianglePath.cgPath)
            context.cgContext.fillPath()
            
            // Draw music metadata at bottom if present
            if let music = project.musicMetadata {
                let textRect = CGRect(x: 20, y: collageImage.size.height - 80, width: collageImage.size.width - 40, height: 60)
                context.cgContext.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
                context.cgContext.fill(textRect)
                
                let textStyle = NSMutableParagraphStyle()
                textStyle.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 18),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: textStyle
                ]
                let text = "\(music.title)\n\(music.artist)"
                text.draw(in: textRect, withAttributes: attrs)
            }
        }
        
        return collageImage
    }
    
    private static func zipDirectory(at sourceURL: URL, to destinationURL: URL) throws {
        // Use NSFileCoordinator's forUploading option which creates a proper zip file
        // Remove destination if it exists
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?
        
        coordinator.coordinate(readingItemAt: sourceURL, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                // Copy the zip file created by the coordinator to our destination
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
                print("✅ Zip file copied successfully from: \(zipURL.path) to: \(destinationURL.path)")
            } catch {
                print("❌ Zip copy failed: \(error)")
                copyError = error
            }
        }
        
        // Check for coordinator errors
        if let coordinatorError = coordinatorError {
            print("❌ File coordinator error: \(coordinatorError)")
            throw coordinatorError
        }
        
        // Check for copy errors
        if let copyError = copyError {
            throw copyError
        }
        
        // Verify the zip file was created and is valid
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw NSError(domain: "BundleExporter", code: -4, userInfo: [NSLocalizedDescriptionKey: "Zip file was not created"])
        }
        
        // Verify it's a valid zip by checking file size (should be > 0)
        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        guard let fileSize = attributes[.size] as? Int, fileSize > 0 else {
            throw NSError(domain: "BundleExporter", code: -5, userInfo: [NSLocalizedDescriptionKey: "Zip file is empty or invalid"])
        }
        
        print("✅ Zip file created successfully: \(destinationURL.lastPathComponent) (\(fileSize) bytes)")
    }
}




