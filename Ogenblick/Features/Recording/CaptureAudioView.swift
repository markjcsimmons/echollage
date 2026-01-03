import SwiftUI
import AVFoundation

struct CaptureAudioView: View {
    @Binding var project: Project
    @EnvironmentObject private var store: ProjectStore
    let onComplete: () -> Void
    
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var previewPlayer = AudioPlayer()
    @StateObject private var viewModel = CaptureAudioViewModel()
    
    var body: some View {
        ZStack {
            // Background and content layer
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                headerContent
                
                // Reserve space for button overlay
                Spacer()
                    .frame(height: 180) // Space for button + text
                
                supplementalActions
                
                Spacer()
            }
            .padding(.horizontal, 24)
            
            // Absolute button overlay - independent of other content
            SharedButtonOverlay {
                Button {
                    SoundEffectPlayer.shared.playClick()
                    handleMainButtonTap()
                } label: {
                    VStack(spacing: 16) {
                        Circle()
                            .fill(buttonColor)
                            .frame(width: SharedButtonMetrics.mainDiameter, height: SharedButtonMetrics.mainDiameter)
                            .shadow(color: buttonColor.opacity(0.4), radius: 18)
                            .overlay(
                                Image(systemName: buttonIcon)
                                    .font(.system(size: SharedButtonMetrics.mainIconSize, weight: .medium))
                                    .foregroundStyle(.white)
                            )
                        
                        Text(buttonText)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        
                        if viewModel.recordingState == .recording {
                            Text("\(viewModel.timeRemaining)s")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.8))
                                .monospacedDigit()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            previewPlayer.stop()
        }
    }
    
    // MARK: - Sections
    
    private var headerContent: some View {
        Group {
            if viewModel.recordingState == .recording {
                waveform
            } else if let result = viewModel.recognitionResult {
                Text(result)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundStyle(result.contains("✓") ? Color.green : Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            } else {
                EmptyView()
            }
        }
        .frame(height: 120)
    }
    
    private var supplementalActions: some View {
        VStack(spacing: 20) {
            if viewModel.recordingState == .finished, let url = audioURL() {
                Button {
                    if previewPlayer.isPlaying {
                        previewPlayer.stop()
                    } else {
                        try? previewPlayer.play(url: url)
                    }
                } label: {
                    Label(previewPlayer.isPlaying ? "Pause" : "Play", systemImage: previewPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            
            if viewModel.recordingState == .finished && !viewModel.isRecognizing {
                Button {
                    startAgain()
                } label: {
                    Text("Recapture")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 28)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                }
            }
            
            if viewModel.isRecognizing {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Identifying music…")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.subheadline)
                }
            }
        }
    }
    
    private var waveform: some View {
        HStack(spacing: 6) {
            ForEach(0..<20, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red.opacity(0.8))
                    .frame(width: 5, height: CGFloat.random(in: 20...80) * CGFloat(max(0.2, recorder.meterLevel)))
                    .animation(.easeInOut(duration: 0.12), value: recorder.meterLevel)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - State Helpers
    
    private var buttonColor: Color {
        switch viewModel.recordingState {
        case .idle: return Color(hex: "FF3B30")
        case .recording: return Color(hex: "FF9500")
        case .finished: return Color(hex: "34C759")
        }
    }
    
    private var buttonIcon: String {
        switch viewModel.recordingState {
        case .idle: return "mic.fill"
        case .recording: return "stop.fill"
        case .finished: return "checkmark"
        }
    }
    
    private var buttonText: String {
        switch viewModel.recordingState {
        case .idle: return "Capture Sound"
        case .recording: return "Stop"
        case .finished: return "Save Recording"
        }
    }
    
    // MARK: - Actions
    
    private func handleMainButtonTap() {
        switch viewModel.recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .finished:
            saveAndContinue()
        }
    }
    
    private func startRecording() {
        print("🎤 Starting recording...")
        
        // Check microphone permission first
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("✅ Microphone permission granted")
                    self.performRecording()
                } else {
                    print("❌ Microphone permission denied")
                    self.viewModel.recognitionResult = "Microphone access required"
                }
            }
        }
    }
    
    private func performRecording() {
        previewPlayer.stop()
        let fileName = "audio_\(UUID().uuidString).wav"
        let url = store.urlForProjectAsset(projectId: project.id, fileName: fileName)
        
        print("🎤 Recording to: \(url.path)")
        
        do {
            try recorder.startRecording(to: url)
            print("✅ Recording started successfully to: \(fileName)")
            
            // Verify recorder is actually recording
            if recorder.isRecording {
                print("✅ Recorder confirmed to be recording")
            } else {
                print("❌ Recorder says it's not recording!")
            }
            
            // Only update state if recording actually started
        project.audioFileName = fileName
        viewModel.recordingState = .recording
        viewModel.timeRemaining = 12
        viewModel.startTimer()
            print("✅ State updated: recording, time=12")
        } catch let error as NSError {
            print("❌ Failed to start recording: \(error)")
            print("❌ Error domain: \(error.domain), code: \(error.code)")
            print("❌ Error details: \(error.localizedDescription)")
            print("❌ Error userInfo: \(error.userInfo)")
            // Don't update state - stay in idle so user can try again
            viewModel.recognitionResult = "Recording failed: \(error.localizedDescription)"
        }
    }
    
    private func stopRecording() {
        Task {
            await recorder.stopRecording()
            viewModel.stopTimer()
            viewModel.recordingState = .finished
        }
    }
    
    private func startAgain() {
        previewPlayer.stop()
        if let audioName = project.audioFileName {
            let url = store.urlForProjectAsset(projectId: project.id, fileName: audioName)
            try? FileManager.default.removeItem(at: url)
        }
        project.audioFileName = nil
        viewModel.reset()
    }
    
    private func saveAndContinue() {
        guard let audioName = project.audioFileName else {
            print("❌ No audio file name")
            onComplete()
            return
        }
        
        let audioURL = store.urlForProjectAsset(projectId: project.id, fileName: audioName)
        previewPlayer.stop()
        
        // Check if file exists and has content
        if let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let fileSize = attributes[.size] as? Int64 {
            print("📁 Audio file size: \(fileSize) bytes")
            if fileSize == 0 {
                print("❌ Audio file is empty (0 bytes)")
            }
        } else {
            print("❌ Audio file does not exist at: \(audioURL.path)")
        }
        
        viewModel.isRecognizing = true
        Task {
            // First, get and save the audio duration
            let audioAsset = AVAsset(url: audioURL)
            let duration = try? await audioAsset.load(.duration).seconds
            
            await MainActor.run {
                if let duration = duration, duration > 0 {
                    project.audioDuration = duration
                    print("✅ Audio duration saved: \(duration)s")
                } else {
                    print("❌ Could not load audio duration - file may be corrupted")
                    // Don't proceed if audio is invalid
                    viewModel.recognitionResult = "Recording failed - please try again"
                    viewModel.isRecognizing = false
                }
                store.update(project)
            }
            
            // Only proceed with recognition if we have valid audio
            guard let duration = duration, duration > 0 else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    onComplete()
                }
                return
            }
            
            // Then try to recognize music
            do {
                if let metadata = try await ACRCloudService.recognizeMusic(fromAudioAt: audioURL) {
                    await MainActor.run {
                        project.musicMetadata = metadata
                        let textLayer = TextLayer(
                            text: "\(metadata.title)\n\(metadata.artist)",
                            fontSize: 24,
                            hexColor: "#FFFFFF",
                            transform: .identity
                        )
                        project.textLayers.append(textLayer)
                        store.update(project)
                        
                        viewModel.recognitionResult = "✓ \(metadata.title) by \(metadata.artist)"
                        viewModel.isRecognizing = false
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        onComplete()
                    }
                } else {
                    await MainActor.run {
                        viewModel.recognitionResult = "No music detected"
                        viewModel.isRecognizing = false
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        onComplete()
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.recognitionResult = "Recognition failed"
                    viewModel.isRecognizing = false
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    onComplete()
                }
            }
        }
    }
    
    private func audioURL() -> URL? {
        guard let audioName = project.audioFileName else { return nil }
        return store.urlForProjectAsset(projectId: project.id, fileName: audioName)
    }
}

// Color hex extension is defined in CollageEditorView
