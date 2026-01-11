import Foundation
import SwiftUI

@MainActor
class CaptureAudioViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var timeRemaining: Int = 15
    @Published var isRecognizing = false
    @Published var recognitionResult: String?
    
    private var timer: Timer?
    
    enum RecordingState {
        case idle, recording, finished
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.timeRemaining -= 1
                print("Time remaining: \(self.timeRemaining)")
                if self.timeRemaining <= 0 {
                    self.stopTimer()
                    // Don't set recordingState = .finished here - let stopRecording() handle it
                    // This prevents the button from being enabled before duration is saved
                }
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func reset() {
        stopTimer()
        recordingState = .idle
        timeRemaining = 15
        recognitionResult = nil
    }
}

