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
                        
                        // Recognition result (elegant display)
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
                    
                    // Centered button (hide during save/recognition)
                    if !viewModel.isRecognizing {
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
                    // Timer
                    if viewModel.recordingState == .recording {
                        Text("\(viewModel.timeRemaining)s")
                            .font(.system(size: 52, weight: .thin))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                            .transition(.opacity)
                    }
                    
                    // Recapture button
                    if viewModel.recordingState == .finished && !viewModel.isRecognizing {
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
                    
                    // Recognition progress
                    if viewModel.isRecognizing {
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
        case .recording: return "Stop"
        case .finished: return "Save"
        }
    }
    
    private func handleMainButtonTap() {
        switch viewModel.recordingState {
        case .idle:
            startRecording()
        case .recording:
            stopRecording()
        case .finished:
            // Show loading indicator immediately for instant feedback
            viewModel.isRecognizing = true
            saveAndContinue()
        }
    }
    
    private func startRecording() {
        // Update UI immediately for instant feedback
        viewModel.recordingState = .recording
        viewModel.timeRemaining = 12
        viewModel.startTimer()
        
        // Then do the setup work asynchronously
        Task {
        let project = store.createNewProject()
        tempProject = project
        
            let fileName = "audio_\(UUID().uuidString).m4a"
        let url = store.urlForProjectAsset(projectId: project.id, fileName: fileName)
        
        do {
            try recorder.startRecording(to: url)
        } catch {
                print("❌ Failed to start recording: \(error)")
                // Don't create empty file - just fail gracefully
        }
        
        if var proj = tempProject {
            proj.audioFileName = fileName
            store.update(proj)
            tempProject = proj
        }
        }
    }
    
    private func stopRecording() {
        Task {
            await recorder.stopRecording()
            await MainActor.run {
        viewModel.stopTimer()
        viewModel.recordingState = .finished
            }
        }
    }
    
    private func startAgain() {
        if let project = tempProject, let audioName = project.audioFileName {
            let url = store.urlForProjectAsset(projectId: project.id, fileName: audioName)
            try? FileManager.default.removeItem(at: url)
            store.delete(project)
        }
        tempProject = nil
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
        viewModel.isRecognizing = true
        
        Task {
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
            
            // Retry loading duration up to 3 times with delays
            var duration: TimeInterval? = nil
            for attempt in 1...3 {
                let audioAsset = AVAsset(url: audioURL)
                duration = try? await audioAsset.load(.duration).seconds
                
                if let dur = duration, dur > 0 {
                    print("✅ Audio duration loaded on attempt \(attempt): \(dur)s")
                    break
                } else {
                    print("⚠️ Attempt \(attempt): Could not load duration, waiting...")
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second between retries
                }
            }
            
            await MainActor.run {
                if let duration = duration, duration > 0 {
                    project.audioDuration = duration
                    print("✅ Audio duration saved: \(duration)s")
                } else {
                    print("❌ Could not load audio duration after 3 attempts - file may be corrupted")
                    viewModel.isRecognizing = false
                    viewModel.recognitionResult = "Recording failed"
                    return
                }
            }
            
            do {
                if let metadata = try await ACRCloudService.recognizeMusic(fromAudioAt: audioURL) {
                    await MainActor.run {
                        project.musicMetadata = metadata
                        store.update(project)
                        viewModel.recognitionResult = "\(metadata.title)\n\(metadata.artist)"
                    }
                } else {
                    await MainActor.run {
                        viewModel.recognitionResult = "No music detected"
                    }
                }
            } catch {
                await MainActor.run {
                    viewModel.recognitionResult = "Unable to identify"
                }
            }
            
            await MainActor.run {
                // Keep isRecognizing true (showing spinner) while we transition
                // Show result for 1 second, then proceed
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    store.update(project)
                    onProjectCreated(project)
                    // Will be reset when view disappears
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

