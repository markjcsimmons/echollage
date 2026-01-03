import AVFoundation
import UIKit
import AudioToolbox

/// Manages UI sound effects with analog feel
class SoundEffectPlayer {
    static let shared = SoundEffectPlayer()
    
    private var clickPlayer: AVAudioPlayer?
    private var tearPlayer: AVAudioPlayer?
    
    private init() {
        setupAudioSession()
        preloadSounds()
        print("🔊 SoundEffectPlayer initialized")
    }
    
    private func setupAudioSession() {
        do {
            // Use playback category for sound effects
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 Audio session setup successful")
        } catch {
            print("❌ Failed to setup audio session: \(error)")
        }
    }
    
    private func preloadSounds() {
        // Generate click sound programmatically
        clickPlayer = createClickSound()
        tearPlayer = createTearSound()
        
        print("🔊 Click player: \(clickPlayer != nil ? "✅" : "❌")")
        print("🔊 Tear player: \(tearPlayer != nil ? "✅" : "❌")")
    }
    
    /// Play mechanical click sound (analog keyboard feel)
    func playClick() {
        guard let player = clickPlayer else {
            // Fallback to system sound
            AudioServicesPlaySystemSound(1104) // Tock sound
            return
        }
        
        // Ensure consistent volume every time
        player.volume = 0.4
        player.currentTime = 0
        player.play()
        
        // Add consistent haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred(intensity: 0.6) // Consistent medium intensity
    }
    
    /// Play paper tear sound with haptic
    func playTear() {
        // Just haptic feedback for tear - no sound
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
    }
    
    // MARK: - Programmatic Sound Generation
    
    private func createClickSound() -> AVAudioPlayer? {
        // Generate authentic typewriter sound (key strike + mechanical clack)
        let sampleRate = 44100.0
        let duration = 0.08 // 80ms for full typewriter action
        
        let frameCount = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: frameCount)
        
        let amplitude: Double = 15000
        
        for i in 0..<frameCount {
            let time = Double(i) / sampleRate
            let progress = Double(i) / Double(frameCount)
            
            var value: Double = 0
            
            // Phase 1: Initial key strike (0-30% of duration)
            if progress < 0.3 {
                let strikeProgress = progress / 0.3
                
                // Sharp metallic impact - high frequency noise burst
                let noise = Double.random(in: -1.0...1.0) * 0.7
                
                // Metal resonance at ~2kHz
                let metalRing = sin(2.0 * .pi * 2000.0 * time) * 0.4
                
                // Sharp envelope for initial impact
                let strikeEnvelope = pow(1.0 - strikeProgress, 3.0)
                
                value = (noise + metalRing) * strikeEnvelope
            }
            
            // Phase 2: Mechanical clack/return (30-100% of duration)
            if progress >= 0.2 {
                let clackProgress = (progress - 0.2) / 0.8
                
                // Lower frequency mechanical sound ~400Hz
                let clack = sin(2.0 * .pi * 400.0 * time) * 0.5
                
                // Add some rattling texture
                let rattle = Double.random(in: -0.3...0.3)
                
                // Slower decay for mechanical clack
                let clackEnvelope = pow(1.0 - clackProgress, 2.0)
                
                value += (clack + rattle) * clackEnvelope * 0.6
            }
            
            samples[i] = Int16(value * amplitude)
        }
        
        return createAudioPlayer(from: samples, sampleRate: sampleRate)
    }
    
    private func createTearSound() -> AVAudioPlayer? {
        // Generate a ripping/tearing sound (white noise with envelope)
        let sampleRate = 44100.0
        let duration = 0.3 // 300ms
        
        let frameCount = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: frameCount)
        
        let amplitude: Double = 6000
        
        for i in 0..<frameCount {
            // Random noise
            let randomValue = Double.random(in: -1.0...1.0) * amplitude
            
            // Apply envelope (gradual decay)
            let progress = Double(i) / Double(frameCount)
            let envelope = 1.0 - pow(progress, 0.5) // Square root for natural decay
            
            samples[i] = Int16(randomValue * envelope)
        }
        
        return createAudioPlayer(from: samples, sampleRate: sampleRate)
    }
    
    private func createAudioPlayer(from samples: [Int16], sampleRate: Double) -> AVAudioPlayer? {
        // Create WAV file with proper header
        var data = Data()
        
        let sampleCount = samples.count
        let dataSize = sampleCount * 2 // 16-bit samples
        let fileSize = 44 + dataSize // WAV header is 44 bytes
        
        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // fmt chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // audio format (PCM)
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // num channels
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) }) // sample rate
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Data($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Data($0) }) // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Data($0) }) // bits per sample
        
        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        
        // Append sample data
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Data($0) })
        }
        
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = 0.4 // Consistent volume for all buttons
            player.prepareToPlay()
            print("🔊 Created audio player with \(samples.count) samples, duration: \(player.duration)s, volume: \(player.volume)")
            return player
        } catch {
            print("❌ Failed to create audio player: \(error)")
            return nil
        }
    }
}

