import Foundation
import AVFoundation

final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying: Bool = false
    private var player: AVAudioPlayer?

    func play(url: URL) throws {
        print("🔊 AudioPlayer.play called with URL: \(url)")
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: url.path) {
            print("❌ Audio file does not exist at path: \(url.path)")
            throw NSError(domain: "Audio", code: -3, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // Use mixWithOthers to allow sound effects and music playback simultaneously
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
            print("🔊 Audio session activated with mixWithOthers")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
            // Try to continue anyway - the session might already be active
            print("⚠️ Continuing despite audio session error...")
        }

        do {
        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
            
            // Set maximum volume
            player?.volume = 1.0
            
            // Enable volume boost if possible
            if #available(iOS 16.0, *) {
                player?.enableRate = true
                player?.rate = 1.0
            }
            
            let duration = player?.duration ?? 0
            print("🔊 AudioPlayer created - duration: \(duration)s, volume: \(player?.volume ?? 0)")
            
            // Check if audio file is valid (has duration)
            if duration <= 0 {
                print("❌ Audio file is empty or invalid (0s duration)")
                throw NSError(domain: "Audio", code: -4, userInfo: [NSLocalizedDescriptionKey: "Audio file is empty"])
            }
            
            guard player?.play() == true else {
                print("❌ player.play() returned false")
                throw NSError(domain: "Audio", code: -2, userInfo: [NSLocalizedDescriptionKey: "Play failed"])
            }
            
        isPlaying = true
            print("🔊 ✅ Audio playback started successfully")
        } catch {
            print("❌ Failed to create or play AVAudioPlayer: \(error)")
            throw error
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        // Don't deactivate session - let other audio continue
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        // Don't deactivate session - let other audio continue
        print("🔊 Audio finished playing")
    }
}




