import Foundation
import AVFoundation

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording: Bool = false
    @Published var meterLevel: Double = 0.0
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
    
    func startRecording(to url: URL) throws {
        guard !isRecording else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already recording"])
        }
        
        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        
        // Configure recorder settings - using M4A format
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        recordingURL = url
        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        
        guard audioRecorder?.record() == true else {
            throw NSError(domain: "AudioRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to start recording"])
        }
        
        audioRecorder?.isMeteringEnabled = true
        
        // Start meter updates
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }
        
        isRecording = true
        print("🎤 Recording started to: \(url.path)")
    }
    
    private func updateMeters() {
        guard let recorder = audioRecorder, isRecording else { return }
        recorder.updateMeters()
        let level = recorder.averagePower(forChannel: 0)
        // Convert from dB (-160 to 0) to 0.0-1.0 range
        meterLevel = Double(max(0.0, min(1.0, (level + 60.0) / 60.0)))
    }
    
    func stopRecording() async {
        guard isRecording, let recorder = audioRecorder else {
            return
        }
        
        recorder.stop()
        // Don't set isRecording = false here - wait for delegate callback
        print("🎤 Stop recording requested")
        
        // Wait for delegate callback and buffer flush
        await withCheckedContinuation { continuation in
            // Store continuation to resume after delegate callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                continuation.resume()
            }
        }
    }
    
    // MARK: - AVAudioRecorderDelegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        print("🎤 audioRecorderDidFinishRecording called, success: \(flag)")
        
        // Wait for M4A buffer flush (as per memory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.meterTimer?.invalidate()
            self.meterTimer = nil
            self.meterLevel = 0.0
            self.isRecording = false
            self.audioRecorder = nil
            print("🎤 Recording finished and buffer flushed")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Audio recorder error: \(error?.localizedDescription ?? "Unknown error")")
        isRecording = false
        audioRecorder = nil
    }
}
