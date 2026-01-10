import Foundation
import CoreGraphics

enum BackgroundType: String, Codable {
    case corkboard
    case white
    case skyBlue
    case black
    case psych
    case orange
    case pattern
    case stripes
    case colored
    case psychedelic
    case floralPattern
    case texture
    case watercolor
    case fireworks
    case mountains
    case waves
    case tiny
}

struct MusicMetadata: Codable, Equatable {
    var title: String
    var artist: String
    var source: String
}

struct Transform2D: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double
    var rotation: Double

    static let identity = Transform2D(x: 0, y: 0, scale: 1, rotation: 0)
}

struct ImageLayer: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var imageFileName: String
    var opacity: Double = 1.0
    var transform: Transform2D = .identity
    var zIndex: Int = 0
    var erasedImageFileName: String? = nil  // Legacy: previously saved erased raster
    var maskFileName: String? = nil        // New: grayscale mask (white keep, black erase)
    // Removed: drawingDataBase64 - drawing is now always canvas-wide, not image-specific
}

struct TextLayer: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var fontName: String = "HelveticaNeue"
    var fontSize: Double = 24
    var hexColor: String = "#FFFFFF"
    var transform: Transform2D = .identity
    var zIndex: Int = 0
}

struct Project: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var canvasWidth: Int = 1080
    var canvasHeight: Int = 1920
    var backgroundHexColor: String = "#000000"

    var audioFileName: String? = nil
    var audioDuration: Double? = nil
    var musicMetadata: MusicMetadata? = nil
    var customAudioName: String? = nil  // User's custom name for "My Sound"

    var imageLayers: [ImageLayer] = []
    var textLayers: [TextLayer] = []

    // PencilKit drawing data archived via PKDrawing.dataRepresentation()
    var drawingDataBase64: String? = nil
    
    // Background type (corkboard, white, or black)
    var backgroundType: BackgroundType = .corkboard
    
    // Check if project has any content
    var hasContent: Bool {
        return !imageLayers.isEmpty || !textLayers.isEmpty || drawingDataBase64 != nil
    }
}


