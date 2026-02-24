import Foundation
import AVFoundation

final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording: Bool = false
    @Published var meterLevel: Double = 0.0
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var meterTimer: Timer?
    private var stopCompletion: CheckedContinuation<Void, Never>?
    
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
    
    func stopRecording() async -> TimeInterval? {
        guard isRecording, let recorder = audioRecorder else {
            print("⚠️ stopRecording() called but not recording or recorder is nil")
            return nil
        }
        
        // Capture duration BEFORE stopping (recorder.currentTime is accurate while recording)
        // Note: currentTime might be 0 immediately after starting, but should be accurate after a moment
        let duration = recorder.currentTime
        print("🎤 Recording duration from currentTime: \(duration)s (captured before stop)")
        print("🎤 Recorder isRecording: \(recorder.isRecording), currentTime: \(recorder.currentTime)")
        
        // If currentTime is 0 or very small, it might not be accurate yet
        // But we'll still use it if it's > 0
        guard duration > 0 else {
            print("⚠️ Duration is 0 or negative: \(duration)s")
            recorder.stop()
            await withCheckedContinuation { continuation in
                self.stopCompletion = continuation
                self.ensureStopCompletionResumesAfterTimeout()
            }
            return nil
        }
        
        recorder.stop()
        // Don't set isRecording = false here - wait for delegate callback
        print("🎤 Stop recording requested")
        
        // Wait for delegate callback to complete and file to be finalized
        await withCheckedContinuation { continuation in
            // Store continuation to resume when delegate callback completes
            self.stopCompletion = continuation
            self.ensureStopCompletionResumesAfterTimeout()
        }
        
        print("🎤 stopRecording() completed, returning duration: \(duration)s")
        return duration
    }

    private func ensureStopCompletionResumesAfterTimeout() {
        // Safety net: in rare cases the AVAudioRecorder delegate may not fire,
        // which would hang stopRecording() forever and freeze the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            guard let self = self else { return }
            guard let completion = self.stopCompletion else { return }
            
            print("⚠️ stopRecording timeout reached — forcing completion")
            self.meterTimer?.invalidate()
            self.meterTimer = nil
            self.meterLevel = 0.0
            self.isRecording = false
            self.audioRecorder = nil
            self.stopCompletion = nil
            completion.resume()
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
            
            // Resume the continuation to signal that recording is fully finished
            self.stopCompletion?.resume()
            self.stopCompletion = nil
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("❌ Audio recorder error: \(error?.localizedDescription ?? "Unknown error")")
        isRecording = false
        audioRecorder = nil
        
        // Resume continuation if waiting (critical - otherwise stopRecording() will hang)
        stopCompletion?.resume()
        stopCompletion = nil
    }
}
