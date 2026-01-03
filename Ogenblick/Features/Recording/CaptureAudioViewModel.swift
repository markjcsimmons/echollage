import Foundation
import SwiftUI

@MainActor
class CaptureAudioViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .idle
    @Published var timeRemaining: Int = 12
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
                    self.recordingState = .finished
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
        timeRemaining = 12
        recognitionResult = nil
    }
}

