import SwiftUI
import AVFoundation

struct ButtonPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct MainFlowView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var currentProject: Project?
    @State private var showGallery = false
    @State private var viewingProject: Project? // For viewing after save
    @State private var shouldShowViewer = false
    @AppStorage("hasSeenIntro") private var hasSeenIntro = false
    @State private var showIntro = false
    
    init() {
        // For development/testing: Reset intro flag on launch (uncomment if needed)
        // UserDefaults.standard.set(false, forKey: "hasSeenIntro")
    }
    
    
    var body: some View {
        Group {
            if let project = currentProject {
                CollageEditorView(
                    project: binding(for: project),
                    onReset: {
                        // Return to initial capture screen for a new moment
                        currentProject = nil
                    },
                    onSave: {
                        // Project is already saved to store by CollageEditorView
                        print("🎨 Save button clicked")
                        SoundEffectPlayer.shared.playClick()
                        
                        // Get the updated project from store
                        if let project = currentProject,
                           let updated = store.projects.first(where: { $0.id == project.id }) {
                            viewingProject = updated
                        }
                    }
                )
            } else {
                InitialCaptureView(onProjectCreated: { project in
                    currentProject = project
                })
            }
        }
        .onAppear {
            print("🎬 MainFlowView onAppear - hasSeenIntro: \(hasSeenIntro)")
            // Show intro on first launch - check immediately
            if !hasSeenIntro {
                print("🎬 Has not seen intro, showing now")
                // Use immediate dispatch to show intro right away
                DispatchQueue.main.async {
                    print("🎬 Setting showIntro to true immediately")
                    showIntro = true
                }
            } else {
                print("🎬 Intro already seen (hasSeenIntro = true), skipping")
            }
        }
        // Hide the default navigation bar and its background so the corkboard
        // can extend fully to the top edge without a white band.
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showGallery) {
            NavigationStack {
                GalleryView(onSelectProject: { project in
                    currentProject = project
                    showGallery = false
                })
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showGallery = false
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $viewingProject) { project in
            CollageViewerView(project: project, assetURLProvider: { fileName in
                store.urlForProjectAsset(projectId: project.id, fileName: fileName)
            })
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $showIntro) {
            IntroView(
                isPresented: $showIntro,
                introText: "Some memories live in sound—first notes, laughter, the noise of a place. Échollage weaves audio and images into a collage you can replay, so the moment comes rushing back."
            )
            .onDisappear {
                print("🎬 IntroView disappeared, marking as seen")
                hasSeenIntro = true
            }
        }
        .onChange(of: showIntro) { newValue in
            print("🎬 showIntro changed to: \(newValue)")
        }
    }
    
    private func binding(for project: Project) -> Binding<Project> {
        Binding(
            get: {
                store.projects.first(where: { $0.id == project.id }) ?? project
            },
            set: { newValue in
                if let index = store.projects.firstIndex(where: { $0.id == project.id }) {
                    store.projects[index] = newValue
                }
            }
        )
    }
}

struct InitialCaptureView: View {
    @EnvironmentObject private var store: ProjectStore
    let onProjectCreated: (Project) -> Void
    
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var viewModel = CaptureAudioViewModel()
    @State private var tempProject: Project?
    @State private var isStoppingRecording = false
    @State private var earlyRecognitionTask: Task<Void, Never>?
    @State private var earlyRecognitionFoundMusic = false // Track if early recognition found music
    
    var body: some View {
        ZStack {
            // Elegant gradient background
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // Top content area (title, waveform, or result)
                    VStack {
                        Spacer().frame(height: 140)
                        
                        VStack(spacing: 20) {
                        // App title
                        if viewModel.recordingState == .idle {
                            VStack(spacing: 8) {
                                Text("Échollage")
                                    .font(.system(size: 48, weight: .thin))
                                    .foregroundStyle(.white)
                                
                                Text("Catch the moment")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                        
                        // Waveform visualization
                        if viewModel.recordingState == .recording {
                            WaveformView(level: recorder.meterLevel)
                                .frame(height: 120)
                                .padding(.horizontal, 60)
                                .transition(.opacity.combined(with: .scale))
                        }
                        
                        // Recognition result (elegant display) - only show after Save is clicked
                        if let result = viewModel.recognitionResult, viewModel.recordingState == .finished {
                            VStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.white.opacity(0.9))
                                
                                Text(result)
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                            }
                            .transition(.opacity.combined(with: .scale))
                        }
                    }
                    
                        Spacer()
                    }
                    
                    // Centered button (hide during recognition or while stopping)
                    if !viewModel.isRecognizing && !isStoppingRecording {
                    Button {
                        SoundEffectPlayer.shared.playClick()
                        handleMainButtonTap()
                    } label: {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(buttonGradient)
                                    .frame(width: 120, height: 120)
                                    .shadow(color: buttonColor.opacity(0.4), radius: 20)
                                
                                Image(systemName: buttonIcon)
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .scaleEffect(viewModel.recordingState == .recording ? 0.95 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.recordingState)
                            
                            Text(buttonText)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                        }
                    }
                    .position(
                        x: geo.size.width / 2,
                        y: UIScreen.main.bounds.height / 2
                    )
                        .transition(.opacity.combined(with: .scale))
                    }
                
                // Bottom content area (timer, recapture, progress)
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                    // Timer - hide immediately when it reaches 0 to avoid showing "0" for long
                    if viewModel.recordingState == .recording && viewModel.timeRemaining > 0 {
                        Text("\(viewModel.timeRemaining)s")
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                            .transition(.opacity)
                    }
                    
                    // Recapture button - hidden during recognition
                    if viewModel.recordingState == .finished && !viewModel.isRecognizing && viewModel.recognitionResult != nil {
                        Button {
                            SoundEffectPlayer.shared.playClick()
                            startAgain()
                        } label: {
                            Text("Recapture")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.vertical, 12)
                                .padding(.horizontal, 32)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.1))
                                )
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Recognition progress - only show after Save is clicked
                    if viewModel.isRecognizing && viewModel.recordingState == .finished {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Identifying music...")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity) // Center in available space
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                    }
                    }
                    .frame(height: 120)
                    .padding(.bottom, 80)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.recordingState)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isRecognizing)
        .animation(.easeInOut(duration: 0.3), value: viewModel.recognitionResult)
        .onChange(of: viewModel.timeRemaining) { newValue in
            // When timer reaches 0, automatically stop recording
            // Use == 0 instead of <= 0 to only trigger once when transitioning from 1 to 0
            if newValue == 0 && viewModel.recordingState == .recording && recorder.isRecording && !isStoppingRecording {
                print("🎤 Timer reached 0, automatically stopping recording...")
                stopRecording()
            }
        }
    }
    
    private var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [buttonColor, buttonColor.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var buttonColor: Color {
        switch viewModel.recordingState {
        case .idle: return Color(hex: "e74c3c")
        case .recording: return Color(hex: "f39c12")
        case .finished: return Color(hex: "27ae60")
        }
    }
    
    private var buttonIcon: String {
        switch viewModel.recordingState {
        case .idle: return "waveform"
        case .recording: return "stop.circle"
        case .finished: return "checkmark.circle"
        }
    }
    
    private var buttonText: String {
        switch viewModel.recordingState {
        case .idle: return "Capture Sound"
        case .recording: return "Save"
        case .finished: return "" // Button hidden when finished
        }
    }
    
    private func handleMainButtonTap() {
        switch viewModel.recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .finished:
            // Button should be hidden in finished state, but handle just in case
            break
        }
    }
    
    private func startRecording() {
        // Update UI immediately for instant feedback
        viewModel.recordingState = .recording
        viewModel.timeRemaining = 15
        viewModel.startTimer()
        
        // Reset early recognition flag
        earlyRecognitionFoundMusic = false
        
        // Then do the setup work asynchronously
        Task {
        let project = store.createNewProject()
        tempProject = project
        
            let fileName = "audio_\(UUID().uuidString).m4a"
        let url = store.urlForProjectAsset(projectId: project.id, fileName: fileName)
        
        do {
            try recorder.startRecording(to: url)
            
            // Only save filename if recording started successfully
            if var proj = tempProject {
                proj.audioFileName = fileName
                store.update(proj)
                tempProject = proj
            }
            
            // Start early recognition after 5 seconds of recording
            await startEarlyRecognition(audioURL: url)
        } catch {
                print("❌ Failed to start recording: \(error)")
                // Reset UI state on failure
                await MainActor.run {
                    viewModel.recordingState = .idle
                    viewModel.stopTimer()
                    tempProject = nil
                    // Show user-friendly error message
                    viewModel.recognitionResult = "Unable to start recording. Please check microphone permissions."
                }
        }
        }
    }
    
    private func stopRecording() {
        // Prevent multiple calls
        guard !isStoppingRecording && viewModel.recordingState == .recording else {
            print("⚠️ stopRecording() already in progress or not recording")
            return
        }
        
        // Cancel early recognition task if still running
        earlyRecognitionTask?.cancel()
        earlyRecognitionTask = nil
        
        // Set flag to prevent multiple calls
        isStoppingRecording = true
        
        // Calculate duration from timer BEFORE stopping (15 seconds - timeRemaining)
        let timerDuration = 15.0 - Double(viewModel.timeRemaining)
        print("🎤 Timer-based duration: \(timerDuration)s (15 - \(viewModel.timeRemaining))")
        
        Task {
            // Stop the recorder (it will try to capture duration from currentTime)
            let recorderDuration = await recorder.stopRecording()
            print("🎤 Recorder duration: \(recorderDuration?.description ?? "nil")")
            
            // Use recorder duration if available and > 0, otherwise use timer duration
            // Timer duration is more reliable since it's always accurate
            let duration: TimeInterval
            if let recorderDuration = recorderDuration, recorderDuration > 0 {
                duration = recorderDuration
            } else {
                duration = timerDuration
            }
            print("🎤 Final duration to save: \(duration)s")
            
            await MainActor.run {
                viewModel.stopTimer()
                viewModel.recordingState = .finished
                
                // Save duration immediately
                guard var project = tempProject else {
                    print("❌ tempProject is nil in stopRecording()")
                    isStoppingRecording = false
                    return
                }
                
                if duration > 0 {
                    project.audioDuration = duration
                    store.update(project)
                    tempProject = project
                    print("✅ Audio duration saved: \(duration)s")
                } else {
                    print("❌ Duration is 0 or negative: \(duration)s")
                }
                
                // Clear flag now that stopping is complete
                isStoppingRecording = false
                
                // Automatically start recognition after stopping
                viewModel.recordingState = .finished
                viewModel.isRecognizing = true
                saveAndContinue()
            }
        }
    }
    
    private func startEarlyRecognition(audioURL: URL) async {
        // Wait 5 seconds to ensure we have enough audio
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        // Check if still recording
        guard recorder.isRecording, viewModel.recordingState == .recording else {
            print("🎵 Early recognition cancelled - recording stopped")
            return
        }
        
        print("🎵 Starting early recognition while recording continues...")
        
        // Start recognition in background while recording continues (silently, no UI updates)
        earlyRecognitionTask = Task {
            do {
                // Try to recognize music from the partially recorded file
                if let metadata = try await ACRCloudService.recognizeMusic(fromAudioAt: audioURL) {
                    await MainActor.run {
                        guard var project = tempProject else { return }
                        project.musicMetadata = metadata
                        store.update(project)
                        tempProject = project
                        earlyRecognitionFoundMusic = true
                        // Don't update UI - result will be shown when Save is clicked
                        print("✅ Early recognition successful (silent): \(metadata.title) by \(metadata.artist)")
                    }
                } else {
                    await MainActor.run {
                        earlyRecognitionFoundMusic = false
                    }
                    print("🎵 Early recognition: No music detected (silent)")
                }
            } catch {
                // Don't show error during early recognition - will retry after recording finishes
                print("⚠️ Early recognition failed (will retry after Save): \(error.localizedDescription)")
            }
        }
    }
    
    private func startAgain() {
        // Cancel early recognition if it's running
        earlyRecognitionTask?.cancel()
        earlyRecognitionTask = nil
        
        // Reset early recognition flag
        earlyRecognitionFoundMusic = false
        
        if let project = tempProject, let audioName = project.audioFileName {
            let url = store.urlForProjectAsset(projectId: project.id, fileName: audioName)
            try? FileManager.default.removeItem(at: url)
            store.delete(project)
        }
        tempProject = nil
        isStoppingRecording = false  // Reset flag
        viewModel.reset()
    }
    
    private func saveAndContinue() {
        guard var project = tempProject else {
            onProjectCreated(store.createNewProject())
            return
        }
        
        guard let audioName = project.audioFileName else {
            onProjectCreated(project)
            return
        }
        
        let audioURL = store.urlForProjectAsset(projectId: project.id, fileName: audioName)
        
        // If early recognition already found music, show it immediately
        if earlyRecognitionFoundMusic, let metadata = project.musicMetadata {
            print("✅ Using early recognition result, showing immediately")
            viewModel.recognitionResult = "\(metadata.title)\n\(metadata.artist)"
            viewModel.isRecognizing = false
            // Wait a moment to show the result, then continue
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    onProjectCreated(project)
                }
            }
            return
        }
        
        // If early recognition found no music, continue trying for up to 3 seconds with the complete file
        // isRecognizing is already set to true in handleMainButtonTap() before calling this function
        
        Task {
            // Add minimum delay to ensure file is fully finalized
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second minimum delay
            // Verify file exists and is readable
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                print("❌ Audio file does not exist after recording")
                await MainActor.run {
                    viewModel.isRecognizing = false
                    viewModel.recognitionResult = "Recording failed"
                }
                return
            }
            
            // Check file size
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
            print("📁 Audio file size: \(fileSize) bytes")
            
            guard fileSize > 1000 else {
                print("❌ Audio file too small (\(fileSize) bytes) - likely corrupt")
                await MainActor.run {
                    viewModel.isRecognizing = false
                    viewModel.recognitionResult = "Recording failed"
                }
                return
            }
            
            // Use duration from project (captured from recorder before stop)
            // This avoids needing to read the file, which may not be finalized yet
            guard let duration = project.audioDuration, duration > 0 else {
                print("❌ Audio duration not available in project")
                await MainActor.run {
                    viewModel.isRecognizing = false
                    viewModel.recognitionResult = "Recording failed"
                }
                return
            }
            
            print("✅ Using audio duration from project: \(duration)s")
            
            do {
                // Try recognition - if early recognition found no music, this gives us another chance with the full file
                if let metadata = try await ACRCloudService.recognizeMusic(fromAudioAt: audioURL) {
                    // Music found - show immediately
                    await MainActor.run {
                        project.musicMetadata = metadata
                        store.update(project)
                        viewModel.recognitionResult = "\(metadata.title)\n\(metadata.artist)"
                        viewModel.isRecognizing = false
                    }
                    // Wait a moment to show the result, then continue
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        onProjectCreated(project)
                    }
                } else {
                    // No music detected
                    await MainActor.run {
                        viewModel.recognitionResult = "No music detected"
                        viewModel.isRecognizing = false
                    }
                    // Wait a moment to show the result, then continue
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        onProjectCreated(project)
                    }
                }
            } catch {
                // Extract user-friendly error message
                let errorMessage: String
                if let nsError = error as NSError?,
                   let userMessage = nsError.userInfo[NSLocalizedDescriptionKey] as? String {
                    errorMessage = userMessage
                } else {
                    errorMessage = "Unable to identify music. \(error.localizedDescription)"
                }
                
                print("❌ Music recognition error: \(errorMessage)")
                
                await MainActor.run {
                    viewModel.recognitionResult = errorMessage
                    viewModel.isRecognizing = false
                }
                // Wait a moment to show the error, then continue
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    onProjectCreated(project)
                }
            }
        }
    }
}

private struct WaveformView: View {
    let level: Double
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<25, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(.white.opacity(0.9))
                    .frame(width: 5, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.15), value: level)
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 20
        let maxHeight: CGFloat = 100
        let variation = sin(Double(index) * 0.5) * 0.3 + 0.7
        return baseHeight + (CGFloat(level) * maxHeight * variation)
    }
}

