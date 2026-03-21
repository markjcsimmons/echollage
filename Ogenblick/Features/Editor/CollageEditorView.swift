import SwiftUI
import AVFoundation
import AVKit
import UIKit
import UniformTypeIdentifiers

struct CollageEditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var purchases: PurchaseManager

    @Binding var project: Project
    var onReset: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil
    @State private var showPhotoPicker = false
    @State private var showPaywall = false
    @State private var showLayerPanel = false
    @State private var showResetConfirmation = false
    @State private var exportError: String?
    @State private var showExportError = false
    @State private var drawingData: Data = Data()
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportedURL: URL?
    @State private var hasCompletedCapture = false
    @State private var showCapture = false
    @State private var isEditingAudioName = false
    @State private var editingAudioName = ""
    @State private var showCamera = false
    @State private var showImageSourcePicker = false
    @State private var isDrawing: Bool = false // Canvas-wide drawing mode (toggled by paint button)
    @State private var selectedTool: DrawingTool = .pen
    @State private var strokeWidth: CGFloat = 8 // Default to "Medium"
    @State private var strokeColor: Color = .white
    @State private var showFullToolset = false
    @State private var selectedImageId: UUID? = nil
    @State private var selectedTextId: UUID? = nil
    @State private var showTextEditor = false
    @State private var editingText = ""
    @State private var editingTextColor: Color = .black
    @State private var editingFontSize: Double = 32
    @State private var showSplitOptions = false
    @State private var tearPathPoints: [(point: CGPoint, pressure: Double)] = []
    @State private var isTearingSelectedImage = false
    @State private var showToolbarForSelectedImage = false
    @State private var isTearProcessing = false
    @State private var lastTearTimestamp: Date = .distantPast // Prevent double-tear
    @State private var isRemovingBackground = false // Track background removal processing
    // Removed: canvasMode - unified toolbar, paint is always canvas-wide
    // Removed: currentDrawingImageId - drawing is always canvas-wide, not image-specific
    // Removed: showDrawingToolbar - will show colors inline when paint is active
    
    // Undo stack to support reverting complex actions like split/add/delete
    enum UndoAction: Equatable {
        case split(original: ImageLayer, pieces: [ImageLayer])
        case addImage(layer: ImageLayer, index: Int)
        case deleteImage(layer: ImageLayer, index: Int)
        case erase(layerId: UUID, previousFileName: String?)
        case draw(previousDrawingBase64: String?) // Canvas-wide drawing only (no layerId needed)
        case eraseCanvas(previousEraseBase64: String?) // Canvas-level erase mask
        case addText(layer: TextLayer, index: Int)
        case deleteText(layer: TextLayer, index: Int)
        case removeBackground(layerId: UUID, backupFileName: String)
        case transform(layerId: UUID, previous: Transform2D, new: Transform2D)
    }
    @State private var undoStack: [UndoAction] = []
    
    // Single-step redo buffer (only valid immediately after an undo)
    private struct RedoBuffer {
        let action: UndoAction
        var drawRedoBase64: String? = nil
        var eraseRedoFileName: String? = nil
        var eraseCanvasRedoBase64: String? = nil
        var removeBackgroundProcessedFileName: String? = nil
    }
    @State private var redoBuffer: RedoBuffer? = nil
    @State private var isPerformingUndoRedo: Bool = false
    @State private var lastUndoStackTop: UndoAction? = nil
    
    // Single-step redo for paint-mode stroke undo
    @State private var drawingRedoData: Data? = nil
    @State private var isPerformingStrokeUndoRedo: Bool = false
    @State private var pencilKitCanvasNonce: Int = 0
    @State private var isFinishingDrawingSave: Bool = false
    @State private var drawingApplyToken: Int = 0
    @State private var isUndoRedoBusy: Bool = false
    
    // Prevent accidental deletions when user is manipulating an image (pinch/rotate/drag)
    @State private var lastImageManipulationAt: Date = .distantPast
    
    @AppStorage("hasSeenEditorCoachMarks") private var hasSeenEditorCoachMarks: Bool = false
    @State private var showEditorCoachMarks: Bool = false
    @State private var editorCoachStepIndex: Int = 0

    private func clearRedoForNewUserAction() {
        if redoBuffer != nil {
            clearRedoBuffer(deleteBackupForRemoveBackground: true)
        }
    }
    
    private func cleanupResources(for action: UndoAction) {
        if case let .removeBackground(_, backupFileName) = action {
            let backupURL = store.urlForProjectAsset(projectId: project.id, fileName: backupFileName)
            try? FileManager.default.removeItem(at: backupURL)
        }
    }
    
    private func recordUndo(_ action: UndoAction) {
        // Any new user action clears redo, and replaces the single-step undo.
        clearRedoForNewUserAction()
        
        // If we're replacing the existing single-step undo, clean up any resources tied to it.
        if let existing = undoStack.last {
            cleanupResources(for: existing)
        }
        
        undoStack = [action]
        lastUndoStackTop = action
    }
    
    // Track which phase of the flow we're in
    enum EditorPhase {
        case addingImages    // Show: Add Image + Done
        case tearing         // Show: Tear + Done
        case designing       // Show: Design + Done
    }
    @State private var currentPhase: EditorPhase = .addingImages
    
    // Unified metrics for all main action buttons to ensure perfect consistency
    private enum MainButtonMetrics {
        static let diameter: CGFloat = 60       // Main button size (50% smaller)
        static let iconSize: CGFloat = 24       // Icon size
        static let smallDiameter: CGFloat = 40  // Small side buttons (undo/done)
        static let smallIconSize: CGFloat = 18
        static let horizontalSpacing: CGFloat = 16
    }

    @StateObject private var recorder = AudioRecorder()
    @StateObject private var player = AudioPlayer()
    
    // Store drawing history for undo (per-image)
    @State private var drawingHistory: [Data] = []
    @State private var drawingStateBeforeEdit: String? = nil // Capture state when starting to draw (for canvas drawing only)
    @State private var isPaintErasing: Bool = false // Eraser mode within paint toolbar
    @State private var eraseDrawingData: Data = Data() // In-memory erase mask buffer
    @State private var isCanvasErasing: Bool = false // Erase tool active
    @State private var eraseHistory: [Data] = [] // Stroke-level history for erase undo
    @State private var eraseRedoData: Data? = nil
    @State private var isFinishingEraseSave: Bool = false
    @State private var stableCanvasSize: CGSize = .zero // Cached canvas size to prevent resize on draw mode toggle
    // Removed: currentDrawingImageId - drawing is always canvas-wide
    
    // Dynamic background based on project backgroundType
    @ViewBuilder
    private var backgroundView: some View {
        switch project.backgroundType {
        case .corkboard:
            CorkboardBackground()
        case .white:
            Color.white
        case .skyBlue:
            Color(red: 0.53, green: 0.81, blue: 0.98) // Sky blue
        case .black:
            Color.black
        case .psych:
            PsychBackground()
        case .orange:
            ImageBackground(imageName: "orange", imageType: "png")
        case .stripes:
            ImageBackground(imageName: "stripes", imageType: "jpg")
        case .colored:
            ImageBackground(imageName: "colored-7292420_1920", imageType: "jpg")
        case .psychedelic:
            ImageBackground(imageName: "psychedelic-9957735_1920", imageType: "jpg")
        case .floralPattern:
            ImageBackground(imageName: "floral-pattern-7411179_1280", imageType: "png")
        case .texture:
            ImageBackground(imageName: "texture-794826_1280", imageType: "png")
        case .watercolor:
            ImageBackground(imageName: "watercolor-7129105_1920", imageType: "png")
        case .fireworks:
            VideoBackground(videoName: "fireworks")
        case .mountains:
            VideoBackground(videoName: "mountains")
        case .waves:
            VideoBackground(videoName: "waves")
        case .tiny:
            VideoBackground(videoName: "214784_tiny")
        case .medium:
            VideoBackground(videoName: "305858_medium")
        case .small:
            VideoBackground(videoName: "310961_small")
        }
    }
    
    // Cycle through background types
    private func cycleBackground() {
        SoundEffectPlayer.shared.playClick()
        withAnimation(.easeInOut(duration: 0.3)) {
            switch project.backgroundType {
            case .corkboard:
                project.backgroundType = .white
            case .white:
                project.backgroundType = .skyBlue
            case .skyBlue:
                project.backgroundType = .black
            case .black:
                project.backgroundType = .psych
            case .psych:
                project.backgroundType = .orange
            case .orange:
                project.backgroundType = .stripes
            case .stripes:
                project.backgroundType = .colored
            case .colored:
                project.backgroundType = .psychedelic
            case .psychedelic:
                project.backgroundType = .floralPattern
            case .floralPattern:
                project.backgroundType = .texture
            case .texture:
                project.backgroundType = .watercolor
            case .watercolor:
                project.backgroundType = .fireworks
            case .fireworks:
                project.backgroundType = .mountains
            case .mountains:
                project.backgroundType = .waves
            case .waves:
                project.backgroundType = .tiny
            case .tiny:
                project.backgroundType = .medium
            case .medium:
                project.backgroundType = .small
            case .small:
                project.backgroundType = .corkboard
            }
        }
        store.update(project)
        print("🎨 Background changed to: \(project.backgroundType)")
    }
    
    // Shared button label for Add Image (matches CaptureAudioView style exactly)
    private var buttonLabel: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.white)
                .frame(width: SharedButtonMetrics.mainDiameter, height: SharedButtonMetrics.mainDiameter)
                .shadow(color: Color.white.opacity(0.4), radius: 18)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 1.5)
                )
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: SharedButtonMetrics.mainIconSize, weight: .medium))
                        .foregroundStyle(.black)
                )
            
            Text("Add Images")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .fixedSize() // Prevent layout shifts
    }

    var body: some View {
        contentView
    }
    
    private var contentView: some View {
        contentViewBase
            .modifier(
                EditorCoachMarksHost(
                    show: showEditorCoachMarks,
                    stepIndex: $editorCoachStepIndex,
                    onDismiss: dismissEditorCoachMarks
                )
            )
    }
    
    private var contentViewBase: some View {
        mainScene
            .coordinateSpace(name: "editor.coachmarks")
            .ignoresSafeArea(.all, edges: .all)
            .navigationBarHidden(true)
            .sheet(isPresented: $showPhotoPicker) {
                PhotoPicker(selectionLimit: 0) { images in
                    // Keep SwiftUI sheet state in sync even if the picker dismisses itself.
                    showPhotoPicker = false
                    addImages(images)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image = image {
                        addImages([image])
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showLayerPanel) {
                LayerPanel(project: $project) {
                    store.update(project)
                }
            }
            .alert("Reset Moment?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetCanvas()
                }
            } message: {
                Text("This will delete everything and return you to the home screen to start a new moment.")
            }
            .alert("Export Error", isPresented: $showExportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(exportError ?? "Unknown error occurred during export")
            }
            .overlay(textEditorOverlay)
            .onAppear(perform: handleOnAppear)
            .onChange(of: undoStack, perform: handleUndoStackChanged)
            // REMOVED: .onChange(of: drawingData) that was always updating global canvas
            // Drawing should only be saved when Done button is clicked or drawing toolbar is closed
            .fullScreenCover(isPresented: $showCapture) {
                CaptureAudioView(project: $project) {
                    hasCompletedCapture = true
                    showCapture = false
                }
                .environmentObject(store)
            }
            .alert("Name Your Sound", isPresented: $isEditingAudioName) {
                TextField("Sound name", text: $editingAudioName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    project.customAudioName = editingAudioName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if project.customAudioName?.isEmpty == true {
                        project.customAudioName = nil
                    }
                    store.update(project)
                }
            } message: {
                Text("Give this sound a custom name")
            }
            .confirmationDialog("Add Image", isPresented: $showImageSourcePicker) {
                Button("Take Photo") {
                    // Dismiss dialog first, then present sheet (prevents occasional no-op).
                    showImageSourcePicker = false
                    DispatchQueue.main.async {
                        showPhotoPicker = false
                        showCamera = true
                    }
                }
                Button("Choose from Photos") {
                    showImageSourcePicker = false
                    DispatchQueue.main.async {
                        showCamera = false
                        showPhotoPicker = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
    }
    
    private func dismissEditorCoachMarks() {
        hasSeenEditorCoachMarks = true
        showEditorCoachMarks = false
    }
    
    private struct EditorCoachMarksHost: ViewModifier {
        let show: Bool
        @Binding var stepIndex: Int
        let onDismiss: () -> Void
        
        func body(content: Content) -> some View {
            content
                .overlayPreferenceValue(EditorCoachMarkFramesPreferenceKey.self) { frames in
                    if show {
                        EditorCoachMarksOverlay(
                            frames: frames,
                            stepIndex: $stepIndex,
                            onSkipOrFinish: onDismiss
                        )
                        .zIndex(20000)
                    }
                }
        }
    }
    
    private var mainScene: some View {
        ZStack {
            backgroundLayer
            canvasLayer
            bottomToolbarLayer
            addImagesOverlay
            resetButtonOverlay
            shareButtonOverlay
            audioButtonOverlay
            drawingControlsOverlay
            eraseControlsOverlay
        }
    }

    private var backgroundLayer: some View {
        backgroundView
            .ignoresSafeArea(.all)
            .onTapGesture(perform: handleBackgroundTap)
    }
    
    private var canvasLayer: some View {
        canvasView
            .ignoresSafeArea(.all)
    }
    
    private var bottomToolbarLayer: some View {
        VStack {
            Spacer()
            actionButtonsContent
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .background(Color.white)
        }
        .ignoresSafeArea(edges: .bottom)
    }
    
    @ViewBuilder
    private var addImagesOverlay: some View {
        if project.imageLayers.isEmpty {
            SharedButtonOverlay {
                buttonLabel
                    .contentShape(Rectangle())
                    .onTapGesture {
                        SoundEffectPlayer.shared.playClick()
                        showImageSourcePicker = true
                    }
                    .editorCoachMarkTarget("editor.addImagesOverlay")
            }
        }
    }
    
    private var resetButtonOverlay: some View {
        VStack {
            HStack {
                Button {
                    SoundEffectPlayer.shared.playClick()
                    showResetConfirmation = true
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.8))
                        )
                }
                .padding(.top, 60)
                .padding(.leading, 20)

                Button {
                    SoundEffectPlayer.shared.playClick()
                    editorCoachStepIndex = 0
                    showEditorCoachMarks = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.55))
                        )
                }
                // Long-press: reset the "seen" flag and show from step 1.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        hasSeenEditorCoachMarks = false
                        editorCoachStepIndex = 0
                        showEditorCoachMarks = true
                    }
                )
                .padding(.top, 60)
                .padding(.leading, 10)
                
                Spacer()
            }
            Spacer()
        }
        .zIndex(3000)
    }
    
    private var shareButtonOverlay: some View {
        VStack {
            HStack {
                Spacer()
                
                Button {
                    SoundEffectPlayer.shared.playClick()
                    handleShareButtonTap()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(isExporting ? 0.7 : 0.9))
                            .frame(width: 44, height: 44)
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(isExporting)
                .padding(.top, 60)
                .padding(.trailing, 20)
                
                if isExporting {
                    exportStatusView
                        .padding(.top, 60)
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            Spacer()
        }
        .zIndex(3000)
        .animation(.easeInOut(duration: 0.2), value: isExporting)
    }
    
    private var exportStatusView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preparing Échollage…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
            ProgressView(value: exportProgress)
                .tint(.white)
                .frame(width: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.black.opacity(0.6))
        )
    }
    
    @ViewBuilder
    private var audioButtonOverlay: some View {
        if project.audioFileName != nil {
            VStack {
                Button {
                    toggleAudioPlayback()
                } label: {
                    audioButtonLabel
                }
                .buttonStyle(.plain)
                .padding(.top, 60)
                Spacer()
            }
            .allowsHitTesting(true)
            .zIndex(3000)
        }
    }
    
    private var audioButtonLabel: some View {
        VStack(spacing: 0) {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "waveform.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white)
            
            if player.isPlaying, let metadata = project.musicMetadata {
                VStack(spacing: 2) {
                    Text(metadata.title)
                        .font(.system(size: 14, weight: .semibold))
                        .italic()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                    Text(metadata.artist)
                        .font(.system(size: 12, weight: .regular))
                        .italic()
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(player.isPlaying ? Color.orange.opacity(0.9) : Color.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    @ViewBuilder
    private var eraseControlsOverlay: some View {
        if isCanvasErasing {
            VStack {
                Spacer()
                Button {
                    SoundEffectPlayer.shared.playClick()
                    finishEraseAndExit()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
                )
                .padding(.bottom, 30)
                .padding(.horizontal, 16)
            }
            .transition(.move(edge: .bottom))
        }
    }

    private var drawingControlsOverlay: some View {
        if isDrawing && !isCanvasErasing {
            VStack {
                Spacer()
                drawingControlsBar
                    .padding(.bottom, 30)
                    .padding(.horizontal, 16)
            }
            .transition(.move(edge: .bottom))
        }
    }
    
    private var drawingControlsBar: some View {
        HStack(spacing: 6) {
            ToolbarGridButton(
                icon: (drawingRedoData == nil) ? "arrow.uturn.backward" : "arrow.uturn.forward",
                isDisabled: (drawingRedoData == nil) ? (drawingHistory.count <= 1) : false
            ) {
                isPerformingStrokeUndoRedo = true
                DispatchQueue.main.async {
                    self.isPerformingStrokeUndoRedo = false
                }
                
                if let redo = drawingRedoData {
                    // Redo the last stroke-undo
                    drawingData = redo
                    if drawingHistory.last != redo {
                        drawingHistory.append(redo)
                    }
                    drawingRedoData = nil
                    pencilKitCanvasNonce += 1
                } else {
                    // Undo last stroke (single-step redo available)
                    if drawingHistory.count > 1 {
                        drawingRedoData = drawingHistory.last
                        drawingHistory.removeLast()
                        drawingData = drawingHistory.last ?? Data()
                        pencilKitCanvasNonce += 1
                    } else if drawingHistory.count == 1 {
                        drawingRedoData = drawingHistory.last
                        drawingData = Data()
                        drawingHistory = [Data()]
                        pencilKitCanvasNonce += 1
                    }
                }
            }
            
            ForEach([Color.white, .black, .red, .yellow, .blue, .purple], id: \.self) { color in
                Button {
                    SoundEffectPlayer.shared.playClick()
                    withAnimation(.easeOut(duration: 0.15)) {
                        strokeColor = color
                        isPaintErasing = false
                    }
                } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(!isPaintErasing && strokeColor == color ? Color.white : Color.white.opacity(0.3),
                                        lineWidth: !isPaintErasing && strokeColor == color ? 2.5 : 1)
                        )
                        .shadow(color: !isPaintErasing && strokeColor == color ? color.opacity(0.6) : Color.black.opacity(0.25),
                                radius: !isPaintErasing && strokeColor == color ? 4 : 2,
                                y: 2)
                        .scaleEffect(!isPaintErasing && strokeColor == color ? 1.1 : 1.0)
                }
            }

            // Close paint mode
            Button {
                SoundEffectPlayer.shared.playClick()
                finishDrawingAndExit()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
        )
    }
    
    @ViewBuilder
    private var textEditorOverlay: some View {
        Group {
            if showTextEditor {
                TextEditorOverlay(
                    isShowing: $showTextEditor,
                    text: $editingText,
                    textColor: $editingTextColor,
                    fontSize: $editingFontSize,
                    onDone: handleTextEditorDone,
                    onCancel: handleTextEditorCancel
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                    removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                ))
                .zIndex(10000)
            }
        }
    }
    
    private func handleOnAppear() {
        applyCanvasDrawing(base64: project.drawingDataBase64)
        hasCompletedCapture = true

        // Text: enforce single text layer going forward.
        // If legacy projects contain multiple text layers, keep the first and drop the rest.
        if project.textLayers.count > 1 {
            let keep = project.textLayers[0]
            project.textLayers = [keep]
            store.update(project)
        }
        
        if !hasSeenEditorCoachMarks {
            // Delay a tick so anchors are available for spotlight positioning.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                editorCoachStepIndex = 0
                showEditorCoachMarks = true
            }
        }
    }
    
    private func handleUndoStackChanged(_ newStack: [UndoAction]) {
        // Enforce: single-step undo + single-step redo toggle.
        // Clear redo ONLY when a new action is recorded (not when undo pops the stack).
        let oldTop = lastUndoStackTop
        let newTop = newStack.last
        lastUndoStackTop = newTop
        
        guard !isPerformingUndoRedo else { return }
        
        // New action recorded if top action changed to a non-nil value.
        let isNewRecordedAction = (newTop != nil && newTop != oldTop)
        if isNewRecordedAction, redoBuffer != nil {
            clearRedoBuffer(deleteBackupForRemoveBackground: true)
        }
        
        if newStack.count > 1, let last = newTop {
            // Clean up any resources tied to discarded undo actions.
            for action in newStack.dropLast() {
                if case let .removeBackground(_, backupFileName) = action {
                    let backupURL = store.urlForProjectAsset(projectId: project.id, fileName: backupFileName)
                    try? FileManager.default.removeItem(at: backupURL)
                }
            }
            undoStack = [last]
        }
    }
    
    private func handleBackgroundTap() {
        if isDrawing {
            SoundEffectPlayer.shared.playClick()
            finishDrawingAndExit()
        } else if selectedTool == .erase {
            SoundEffectPlayer.shared.playClick()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTool = .pen
            }
        } else {
            cycleBackground()
        }
    }
    
    private func handleTextEditorDone() {
        if let textId = selectedTextId,
           let idx = project.textLayers.firstIndex(where: { $0.id == textId }) {
            if !editingText.trimmingCharacters(in: .whitespaces).isEmpty {
                project.textLayers[idx].text = editingText
                project.textLayers[idx].hexColor = editingTextColor.toHex() ?? "#000000"
                project.textLayers[idx].fontSize = editingFontSize
                
                // If this text layer was just created, update the undo payload so redo restores
                // the final edited content (not the initial empty layer).
                if let last = undoStack.last, case .addText(let addedLayer, let addedIndex) = last, addedLayer.id == textId {
                    let updatedLayer = project.textLayers[idx]
                    let updatedAction: UndoAction = .addText(layer: updatedLayer, index: addedIndex)
                    undoStack = [updatedAction]
                    lastUndoStackTop = updatedAction
                }
            } else {
                let layer = project.textLayers[idx]
                project.textLayers.remove(at: idx)
                recordUndo(.deleteText(layer: layer, index: idx))
            }
        }
        
        selectedTextId = nil
        showTextEditor = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            store.update(project)
        }
    }
    
    private func handleTextEditorCancel() {
        if let textId = selectedTextId,
           let idx = project.textLayers.firstIndex(where: { $0.id == textId }),
           let layer = project.textLayers.first(where: { $0.id == textId }),
           layer.text.isEmpty {
            project.textLayers.remove(at: idx)
            
            // If this was a brand-new (empty) text layer, discard the undo entry for adding it.
            if let last = undoStack.last, case .addText(let addedLayer, _) = last, addedLayer.id == textId {
                undoStack.removeAll()
                lastUndoStackTop = nil
                if redoBuffer != nil {
                    clearRedoBuffer(deleteBackupForRemoveBackground: true)
                }
            }
            store.update(project)
        }
        
        selectedTextId = nil
        showTextEditor = false
    }
    
    // Cache loaded images to avoid disk I/O every frame
    @State private var imageCache: [String: UIImage] = [:]
    // Track access order for LRU cache eviction
    @State private var imageCacheAccessOrder: [String] = []
    private let maxCacheSize = 10 // Maximum images to keep in memory
    
    // Cache for expensive calculations (transparency and tight bounds)
    private struct ImageMetadata {
        let hasTransparency: Bool
        let tightBoundsSize: CGSize?
    }
    @State private var imageMetadataCache: [String: ImageMetadata] = [:]
    
    // Cache sorted layers to avoid sorting on every render
    private var sortedImageLayers: [ImageLayer] {
        project.imageLayers.sorted(by: { $0.zIndex < $1.zIndex })
    }
    
    // Create layer index map for O(1) lookups
    private var layerIndexMap: [UUID: Int] {
        Self.createLayerIndexMap(from: project.imageLayers)
    }
    
    // Static helper to create layer index map (usable from nested types)
    private static func createLayerIndexMap(from layers: [ImageLayer]) -> [UUID: Int] {
        var map: [UUID: Int] = [:]
        for (index, layer) in layers.enumerated() {
            map[layer.id] = index
        }
        return map
    }
    
    private func loadImage(fileName: String) -> UIImage? {
        // Check cache first (using non-mutating access for performance)
        if let cached = imageCache[fileName] {
            // Update access order for LRU
            updateCacheAccessOrder(for: fileName)
            return cached
        }
        
        guard let url = assetURL(for: fileName) else { return nil }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        
        // Downscale aggressively for memory (synchronously to avoid race condition)
        let maxDimension: CGFloat = 1000 // Reduced for better performance
        let downsized = downscaleImage(image, maxDimension: maxDimension)
        
        // Cache immediately before returning to prevent race conditions
        // Remove oldest entry if cache is full (LRU eviction)
        if imageCache.count >= maxCacheSize, let oldestKey = imageCacheAccessOrder.first {
            imageCache.removeValue(forKey: oldestKey)
            imageMetadataCache.removeValue(forKey: oldestKey)
            imageCacheAccessOrder.removeFirst()
        }
        
        // Add to cache and access order
        imageCache[fileName] = downsized
        updateCacheAccessOrder(for: fileName)
        
        return downsized
    }
    
    // Update access order for LRU cache (move to end)
    private func updateCacheAccessOrder(for fileName: String) {
        imageCacheAccessOrder.removeAll { $0 == fileName }
        imageCacheAccessOrder.append(fileName)
    }
    
    // Cached version of imageHasTransparency
    private func getCachedTransparency(for fileName: String, image: UIImage) -> Bool {
        if let metadata = imageMetadataCache[fileName] {
            return metadata.hasTransparency
        }
        
        let hasTransparency = imageHasTransparency(image)
        let metadata = ImageMetadata(hasTransparency: hasTransparency, tightBoundsSize: nil)
        imageMetadataCache[fileName] = metadata
        return hasTransparency
    }
    
    // Cached version of tightBoundsSize
    private func getCachedTightBoundsSize(for fileName: String, image: UIImage, baseSize: CGSize) -> CGSize {
        if let metadata = imageMetadataCache[fileName],
           let cachedSize = metadata.tightBoundsSize {
            return cachedSize
        }
        
        let tightSize = tightBoundsSize(for: image, baseSize: baseSize)
        let hasTransparency = imageMetadataCache[fileName]?.hasTransparency ?? imageHasTransparency(image)
        let metadata = ImageMetadata(hasTransparency: hasTransparency, tightBoundsSize: tightSize)
        imageMetadataCache[fileName] = metadata
        return tightSize
    }
    
    private var canvasView: some View {
        GeometryReader { geometry in
            let canvasSize = geometry.size
            let imageLayoutSize = stableCanvasSize != .zero ? stableCanvasSize : canvasSize
            ZStack {
                // Always transparent to show corkboard background
                // Note: When paint is active, tapping background (above) will deselect paint
                Color.clear
                    .editorCoachMarkTarget("editor.canvas")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Single tap on empty canvas: cycle background (canvas sits above background layer, so we must handle it here).
                        handleBackgroundTap()
                    }
                    .highPriorityGesture(
                        TapGesture(count: 2)
                            .onEnded {
                                // Double tap empty canvas to delete drawing (keep drawing layer non-hit-testable
                                // so images remain selectable after painting).
                                guard !isDrawing, !drawingData.isEmpty else { return }
                                print("🗑️ Double tap on canvas - deleting canvas drawing")
                                SoundEffectPlayer.shared.playClick()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                    SoundEffectPlayer.shared.playClick()
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    self.deleteCanvasDrawing()
                                }
                            }
                    )

                ForEach(sortedImageLayers) { layer in
                    imageLayerView(
                        for: layer,
                        canvasSize: imageLayoutSize,
                        isCoachMarkTarget: layer.id == sortedImageLayers.first?.id
                    )
                }
                
                // Only allow one text layer (the first) to be shown/edited.
                let visibleTextLayers = Array(project.textLayers.sorted(by: { $0.zIndex < $1.zIndex }).prefix(1))
                ForEach(visibleTextLayers, id: \.id) { layer in
                    TransformableText(
                        text: layer.text,
                        fontName: layer.fontName,
                        fontSize: layer.fontSize,
                        color: Color(hex: layer.hexColor),
                        transform: layer.transform,
                        isSelected: selectedTextId == layer.id
                    ) { newTransform in
                        if let idx = project.textLayers.firstIndex(where: { $0.id == layer.id }) {
                            project.textLayers[idx].transform = newTransform
                            store.update(project)
                        }
                    } onTap: {
                        guard !showTextEditor else { return } // Prevent multiple taps
                        SoundEffectPlayer.shared.playClick()
                        addTextLayer()
                    } onDoubleTap: {
                        // Long press to delete text
                        guard !showTextEditor else { return }
                        print("🗑️ Long press detected - deleting text: \(layer.id)")
                        // Play click sound
                        SoundEffectPlayer.shared.playClick()
                        // Haptic feedback for deletion
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        generator.impactOccurred(intensity: 0.7)
                        // Delay deletion to avoid gesture conflicts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            self.deleteTextLayer(layer: layer)
                        }
                    } onTextChange: { _ in
                        // Not used in simplified version
                    }
                    // While painting, text layers should not intercept touches.
                    .allowsHitTesting(!isDrawing)
                    .zIndex(2000 + Double(layer.zIndex)) // High zIndex to render on top, but only captures touches on actual text
                }
                
                // Show saved canvas-wide drawing (only when NOT actively drawing, to avoid conflicts)
                if !isDrawing, !drawingData.isEmpty {
                    ImageBoundDrawingView(
                        drawingData: drawingData,
                        imageSize: canvasSize,
                        isInteractive: false
                    )
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .allowsHitTesting(false)
                    .zIndex(500) // Above images, below active drawing
                }
                
                // PencilKit drawing layer - canvas-wide drawing (always canvas-wide, never image-specific)
                if isDrawing {
                        PencilKitView(
                            drawingData: $drawingData,
                            isDrawingEnabled: true,
                        isEraseMode: isPaintErasing, // Enable eraser within paint toolbar
                            strokeColor: strokeColor,
                            strokeWidth: strokeWidth,
                        expectedSize: canvasSize, // CRITICAL: Pass expected size for bounds matching
                            onDrawingChanged: { newData in
                            print("🎨 Canvas drawing changed, data size: \(newData.count) bytes")
                                // Ignore callback noise caused by programmatic undo/redo
                                if isPerformingStrokeUndoRedo {
                                    return
                                }
                                if !drawingHistory.isEmpty && drawingHistory.last == newData {
                                    print("🎨 Skipping duplicate")
                                    return
                                }
                                // Any new action clears the single-step redo toggle
                                clearRedoForNewUserAction()
                                drawingHistory.append(newData)
                                print("🎨 Added to history, total states: \(drawingHistory.count)")
                                // Any new drawing clears redo for stroke-undo
                                drawingRedoData = nil
                        },
                        onTapOnly: {
                            // When user taps canvas (not draws), deselect paint tool
                            print("🎨 Canvas tapped (not drawn) while paint active - deselecting paint tool")
                            SoundEffectPlayer.shared.playClick()
                            finishDrawingAndExit()
                            }
                        )
                        .id("pencilkit-canvas-\(pencilKitCanvasNonce)")
                        .frame(width: canvasSize.width, height: canvasSize.height)
                        .allowsHitTesting(true)
                    .zIndex(1000) // Above saved drawing and images
                }
                
                // Tear gesture overlay when image is selected - with pressure sensitivity
                       if selectedTool == .tear && selectedImageId != nil && !isTearProcessing {
                           PressureSensitiveTearOverlay(
                               tearPathPoints: $tearPathPoints,
                               isTearing: $isTearingSelectedImage,
                               canvasSize: canvasSize,
                               onTearComplete: { performTearOnSelectedImage(canvasSize: canvasSize) },
                               isActive: selectedImageId != nil && project.imageLayers.contains(where: { $0.id == selectedImageId }) && !isTearProcessing
                           )
                           .zIndex(1000)
                       }
                       
                       // Saved erase mask — renders with destinationOut to punch holes through canvas content
                       if !isCanvasErasing && !eraseDrawingData.isEmpty {
                           PencilKitView(
                               drawingData: .constant(eraseDrawingData),
                               isDrawingEnabled: false,
                               isEraseMode: false,
                               strokeColor: .black,
                               strokeWidth: strokeWidth,
                               expectedSize: canvasSize,
                               onDrawingChanged: { _ in },
                               onTapOnly: nil
                           )
                           .blendMode(.destinationOut)
                           .frame(width: canvasSize.width, height: canvasSize.height)
                           .allowsHitTesting(false)
                           .zIndex(900)
                       }

                       // Active erase canvas — user draws strokes that cut through everything below
                       if isCanvasErasing {
                           PencilKitView(
                               drawingData: $eraseDrawingData,
                               isDrawingEnabled: true,
                               isEraseMode: false,
                               strokeColor: .black,
                               strokeWidth: strokeWidth,
                               expectedSize: canvasSize,
                               onDrawingChanged: { newData in
                                   if isPerformingStrokeUndoRedo { return }
                                   if !eraseHistory.isEmpty && eraseHistory.last == newData { return }
                                   eraseHistory.append(newData)
                                   eraseRedoData = nil
                               },
                               onTapOnly: {
                                   SoundEffectPlayer.shared.playClick()
                                   finishEraseAndExit()
                               }
                           )
                           .blendMode(.destinationOut)
                           .id("pencilkit-erase-\(pencilKitCanvasNonce)")
                           .frame(width: canvasSize.width, height: canvasSize.height)
                           .allowsHitTesting(true)
                           .zIndex(1000)
                       }

                       // Visual debug indicator for tear processing
                       if isTearProcessing {
                           VStack {
                               Text("Processing tear...")
                                   .font(.headline)
                                   .foregroundColor(.white)
                                   .padding()
                                   .background(Color.red.opacity(0.8))
                                   .cornerRadius(10)
                               Spacer()
                           }
                           .zIndex(2000)
                       }
                       
                       
                   }
                   .compositingGroup() // Required for destinationOut erase blend mode
                   .frame(width: canvasSize.width, height: canvasSize.height)
                   .onAppear {
                       if stableCanvasSize == .zero {
                           stableCanvasSize = canvasSize
                       }
                       // Load saved erase mask into local buffer
                       if let base64 = project.eraseDrawingDataBase64,
                          let data = Data(base64Encoded: base64) {
                           eraseDrawingData = data
                       }
                   }
                   .onChange(of: canvasSize) { newSize in
                       if !isDrawing {
                           stableCanvasSize = newSize
                       }
                   }
               }
           }
    
    // Unified toolbar - always visible (no mode switching needed)
    private var actionButtonsContent: some View {
        HStack(spacing: 6) {
            unifiedToolbar()
        }
    }
    
    // Unified toolbar (always visible, no mode switching)
    @ViewBuilder
    private func unifiedToolbar() -> some View {
            // 1. Undo (also handles erase stroke undo when canvas eraser is active)
            ToolbarGridButton(
                icon: isCanvasErasing
                    ? ((eraseRedoData == nil) ? "arrow.uturn.backward" : "arrow.uturn.forward")
                    : ((redoBuffer == nil) ? "arrow.uturn.backward" : "arrow.uturn.forward"),
                isDisabled: isCanvasErasing
                    ? (eraseHistory.count <= 1 && eraseRedoData == nil)
                    : ((undoStack.isEmpty && redoBuffer == nil) || isDrawing)
            ) {
                if isCanvasErasing {
                    undoEraseStroke()
                } else {
                    undoLastAction()
                }
            }
            
            // 2. Add Image
            ToolbarGridButton(
                icon: "photo",
                isDisabled: project.imageLayers.count >= 10,
                shouldThrob: false
            ) {
                showImageSourcePicker = true
                // Deactivate any active tools when adding image
                selectedTool = .pen
                isDrawing = false
            }
            .editorCoachMarkTarget("editor.addImage")
            
            // 3. Mask/Remove Background (disabled if no image selected)
            ToolbarGridButton(
                icon: "person.crop.circle.fill",
                isDisabled: !showToolbarForSelectedImage || isRemovingBackground,
                shouldThrob: showToolbarForSelectedImage,
                isSelected: false
            ) {
                guard let imageId = selectedImageId else { return }
                print("🎭 Mask button clicked - removing background for image: \(imageId)")
                autoRemoveBackground(for: imageId)
                selectedTool = .pen
                isDrawing = false
            }
            .editorCoachMarkTarget("editor.removeBackground")
            
            // 4. Erase (canvas-level — erases paint, images, text via destinationOut blend)
            ToolbarGridButton(
                icon: "eraser",
                isDisabled: false,
                isSelected: isCanvasErasing
            ) {
                if isCanvasErasing {
                    finishEraseAndExit()
                } else {
                    // Deselect image/text and exit drawing mode before activating eraser
                    selectedImageId = nil
                    showToolbarForSelectedImage = false
                    selectedTextId = nil
                    showTextEditor = false
                    if isDrawing { finishDrawingAndExit() }
                    selectedTool = .erase
                    isCanvasErasing = true
                    // Load existing erase data from project
                    if let base64 = project.eraseDrawingDataBase64,
                       let data = Data(base64Encoded: base64) {
                        eraseDrawingData = data
                    } else {
                        eraseDrawingData = Data()
                    }
                    eraseHistory = [eraseDrawingData]
                    eraseRedoData = nil
                    print("🧹 Canvas erase activated")
                }
            }
            
            // 5. Paint (canvas-wide, always available) - toggle on/off
        ToolbarGridButton(
            icon: "paintbrush",
                isDisabled: false,
                isSelected: isDrawing // Selected when actively drawing (canvas-wide)
        ) {
                // Toggle: if already drawing, deactivate; otherwise activate
                if isDrawing && (selectedTool == .pen || selectedTool == .brush) {
                    // Deactivate drawing - save current drawing first (async) then exit.
                    finishDrawingAndExit()
                    print("🎨 Paint deactivated")
                } else {
                    // Deselect text and close text editor when activating paint
                    selectedTextId = nil
                    showTextEditor = false
                    // Also deselect any selected image
                    selectedImageId = nil
                    showToolbarForSelectedImage = false
                    
                    // Activate canvas-wide drawing
                    selectedTool = .pen
            isDrawing = true
            
                    // Capture state before drawing starts
            drawingStateBeforeEdit = project.drawingDataBase64
            print("🎨 Captured drawing state before edit: \(drawingStateBeforeEdit?.prefix(20) ?? "nil")")
            
                    // Load existing canvas drawing (decode off-main).
                    // If it's already loaded into memory, keep the current snapshot.
                    if drawingData.isEmpty {
                        applyCanvasDrawing(base64: project.drawingDataBase64)
                    } else {
                        drawingHistory = [drawingData]
                    }
            
                    print("🎨 Started canvas-wide drawing")
                }
        }
        .editorCoachMarkTarget("editor.paint")
        
            // 6. Text (canvas-wide, always available)
        ToolbarGridButton(
            icon: "textformat",
                isDisabled: false,
                isSelected: false // Text is not a persistent tool state
        ) {
            // If paint is active, save & exit first to avoid losing strokes / breaking redo.
            if isDrawing {
                finishDrawingAndExit {
                    addTextLayer()
                }
            } else {
                addTextLayer()
            }
        }
        .editorCoachMarkTarget("editor.text")
    }
    
    // Individual grid button with 3D shadow effect
    private struct ToolbarGridButton: View {
        let icon: String
        var isDisabled: Bool = false
        var isAccent: Bool = false
        var shouldThrob: Bool = false // Suggest this button to user
        var isSelected: Bool = false // Make tool prominent when active
        let action: () -> Void
        
        @State private var throbScale: CGFloat = 1.0
        @State private var isPressed: Bool = false
        
        var body: some View {
            Button(action: action) {
                ZStack {
                    // Bottom shadow layer (3D depth)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 50, height: 50)
                        .offset(y: isPressed ? 1 : 3)
                    
                    // Main button - highlighted when selected with black border
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.98),
                                    Color.white.opacity(0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Group {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.black, lineWidth: 2.5)
                                } else {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8),
                                            Color.black.opacity(0.2)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                                }
                            }
                        )
                        .shadow(color: Color.black.opacity(0.15), radius: isSelected ? 4 : 2, x: 0, y: 1)
                        .offset(y: isPressed ? 2 : 0)
                    
                    // Icon - black when selected
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(.black)
                        .offset(y: isPressed ? 2 : 0)
                }
            }
            .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
            .disabled(isDisabled || icon.isEmpty)
            .opacity(isDisabled || icon.isEmpty ? 0.3 : 1.0)
            .scaleEffect(isSelected ? 1.05 : 1.0) // Slightly larger when selected
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
    
    // Custom button style that tracks press state for 3D effect
    private struct PressableButtonStyle: ButtonStyle {
        @Binding var isPressed: Bool
        
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .onChange(of: configuration.isPressed) { newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressed = newValue
                    }
                    if newValue {
                        SoundEffectPlayer.shared.playClick()
                    }
                }
        }
    }
    
    // Plain button style that prevents any movement or animation
    private struct PlainScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                // No scale, no animation - completely static
        }
    }
    
    
    // MARK: - Pressure Sensitive Erase Overlay
    private struct PressureSensitiveEraseOverlay: UIViewRepresentable {
        let selectedImageId: UUID?
        @Binding var project: Project
        @Binding var undoStack: [UndoAction]
        let store: ProjectStore
        let brushSize: CGFloat
        
        func makeUIView(context: Context) -> PressureEraseView {
            let view = PressureEraseView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = true
            return view
        }
        
        func updateUIView(_ uiView: PressureEraseView, context: Context) {
            uiView.selectedImageId = selectedImageId
            uiView.project = project
            uiView.store = store
            uiView.brushSize = brushSize
            uiView.onEraseComplete = { updatedProject, undoAction in
                DispatchQueue.main.async {
                    self.project = updatedProject
                    if let action = undoAction {
                        // Single-step undo: record erase as the last action
                        self.undoStack = [action]
                    }
                }
            }
        }
    }
    
    // UIView that captures pressure-sensitive erase gestures
    class PressureEraseView: UIView {
        var selectedImageId: UUID?
        var project: Project?
        var store: ProjectStore?
        var brushSize: CGFloat = 20
        var onEraseComplete: ((Project, CollageEditorView.UndoAction?) -> Void)?
        
        private var erasePoints: [(point: CGPoint, pressure: Double)] = []
        private var feedbackLayer: CAShapeLayer?
        
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            
            let pressure = getPressure(from: touch)
            erasePoints = [(point: location, pressure: pressure)]
            
            print("🧹 Erase overlay touchesBegan at \(location), pressure: \(pressure)")
            
            // Create visual feedback layer
            feedbackLayer?.removeFromSuperlayer()
            let layer = CAShapeLayer()
            layer.strokeColor = UIColor.red.withAlphaComponent(0.5).cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer.addSublayer(layer)
            feedbackLayer = layer
            
            updateFeedbackPath()
        }
        
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let location = touch.location(in: self)
            
            let pressure = getPressure(from: touch)
            erasePoints.append((point: location, pressure: pressure))
            
            updateFeedbackPath()
        }
        
        private func updateFeedbackPath() {
            guard erasePoints.count >= 2 else { return }
            
            let path = UIBezierPath()
            path.move(to: erasePoints[0].point)
            
            for data in erasePoints.dropFirst() {
                path.addLine(to: data.point)
            }
            
            // Average pressure for line width
            // Safety check: ensure we don't divide by zero (shouldn't happen due to guard above, but defensive)
            let pointCount = max(1, erasePoints.count)
            let avgPressure = erasePoints.map { $0.pressure }.reduce(0, +) / Double(pointCount)
            let lineWidth = CGFloat(brushSize * (0.5 + avgPressure * 2.5))
            
            feedbackLayer?.path = path.cgPath
            feedbackLayer?.lineWidth = lineWidth
        }
        
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            print("🧹 Erase overlay touchesEnded with \(erasePoints.count) points")
            
            // Remove visual feedback immediately
            feedbackLayer?.removeFromSuperlayer()
            feedbackLayer = nil
            
            guard erasePoints.count >= 2,
                  let selectedId = selectedImageId,
                  var project = project,
                  let store = store,
                  let idx = CollageEditorView.createLayerIndexMap(from: project.imageLayers)[selectedId] else {
                print("🧹 Not enough points or no selected image")
                erasePoints = []
                return
            }
            
            print("🧹 Applying erase to image at index \(idx)")
            
            // Load the current image and capture previous state for undo
            let layer = project.imageLayers[idx]
            let previousErasedFileName = layer.erasedImageFileName // Capture for undo
            let imageURL = store.urlForProjectAsset(projectId: project.id, fileName: layer.erasedImageFileName ?? layer.imageFileName)
            guard let currentImage = UIImage(contentsOfFile: imageURL.path) else {
                print("🧹 Failed to load image from \(imageURL.path)")
                erasePoints = []
                return
            }
            
            // Calculate image position on canvas (same as tear tool)
            // SwiftUI applies transforms in order: scale -> rotation -> offset
            // So we need to reverse: undo offset -> undo rotation -> undo scale
            let canvasSize = self.bounds.size
            let baseSize = self.calculateBaseImageSize(for: currentImage, canvasSize: canvasSize)
            let transform = layer.transform
            
            let imageCenterX = canvasSize.width / 2 + transform.x
            let imageCenterY = canvasSize.height / 2 + transform.y
            let imageCenter = CGPoint(x: imageCenterX, y: imageCenterY)
            
            // Convert canvas points to image pixel coordinates
            // CRITICAL: Account for rotation and scale by reversing the transform chain
            let imagePoints = self.erasePoints.compactMap { data -> (point: CGPoint, pressure: Double)? in
                var canvasPoint = data.point
                
                // Step 1: Undo offset - translate relative to image center
                canvasPoint.x -= imageCenter.x
                canvasPoint.y -= imageCenter.y
                
                // Step 2: Undo rotation - rotate back by -rotation
                if transform.rotation != 0 {
                    let cosRotation = cos(-transform.rotation)
                    let sinRotation = sin(-transform.rotation)
                    let rotatedX = canvasPoint.x * cosRotation - canvasPoint.y * sinRotation
                    let rotatedY = canvasPoint.x * sinRotation + canvasPoint.y * cosRotation
                    canvasPoint = CGPoint(x: rotatedX, y: rotatedY)
                }
                
                // Step 3: Undo scale - divide by scale to get baseSize coordinates
                // Now canvasPoint is in baseSize space, centered at origin
                let baseX = canvasPoint.x / transform.scale
                let baseY = canvasPoint.y / transform.scale
                
                // Step 4: Convert from baseSize space (centered at origin) to image pixel coordinates
                // baseSize is centered at origin, so convert: (-baseSize/2 to +baseSize/2) -> (0 to imageSize)
                let normalizedX = (baseX / baseSize.width) + 0.5 // 0.0 to 1.0
                let normalizedY = (baseY / baseSize.height) + 0.5
                
                // Step 5: Convert to image pixel coordinates
                let imageX = normalizedX * currentImage.size.width
                let imageY = normalizedY * currentImage.size.height
                
                // Clamp to image bounds
                let clampedX = max(0, min(currentImage.size.width, imageX))
                let clampedY = max(0, min(currentImage.size.height, imageY))
                
                return (point: CGPoint(x: clampedX, y: clampedY), pressure: data.pressure)
            }
            
            guard imagePoints.count >= 2 else {
                print("🧹 No valid image points after conversion")
                self.erasePoints = []
                return
            }
            
            print("🧹 Converted \(self.erasePoints.count) canvas points to \(imagePoints.count) image points")
            
            // Apply pressure-sensitive erase stroke on background thread
            DispatchQueue.global(qos: .userInitiated).async {
                guard let erasedImage = self.applyEraseStroke(to: currentImage, points: imagePoints, brushSize: self.brushSize) else {
                    print("🧹 Failed to apply erase")
                    return
                }
                
                // Save the erased image
                let fileName = "erased_\(UUID().uuidString).png"
                guard let store = self.store, let projectId = self.project?.id else { return }
                let url = store.urlForProjectAsset(projectId: projectId, fileName: fileName)
                
                if let data = erasedImage.pngData() {
                    do {
                        try data.write(to: url)
                        print("🧹 Saved erased image: \(fileName)")
                        
                        DispatchQueue.main.async {
                            guard var updated = self.project else { return }
                            updated.imageLayers[idx].erasedImageFileName = fileName
                            self.project = updated
                            store.update(updated)
                            
                            // Create undo action with previous state
                            let undoAction = CollageEditorView.UndoAction.erase(layerId: layer.id, previousFileName: previousErasedFileName)
                            self.onEraseComplete?(updated, undoAction)
                        }
                    } catch {
                        print("🧹 Failed to save erased image: \(error)")
                    }
                }
            }
            
            erasePoints = []
        }
        
        private func applyEraseStroke(to image: UIImage, points: [(point: CGPoint, pressure: Double)], brushSize: CGFloat) -> UIImage? {
            guard points.count >= 2 else { return nil }
            
            // Create a new image with erased pixels
            let format = UIGraphicsImageRendererFormat.default()
            format.opaque = false
            format.scale = 1
            
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            return autoreleasepool {
                renderer.image { context in
                    // Draw original image
                    image.draw(at: .zero)
                    
                    // Set up erase mode (clear blend mode)
                    let cg = context.cgContext
                    cg.setBlendMode(.clear)
                    cg.setLineCap(.round)
                    cg.setLineJoin(.round)
                    
                    // Convert canvas points to image coordinates
                    // (We'll need the image's displayed rect for this)
                    // For now, use direct points - we'll fix coordinate conversion
                    
                    // Draw pressure-sensitive erase stroke
                    for i in 0..<(points.count - 1) {
                        let start = points[i]
                        let end = points[i + 1]
                        
                        // Calculate line width based on average pressure
                        // Pressure 0.0-1.0 → width 0.5x to 3x
                        let avgPressure = (start.pressure + end.pressure) / 2.0
                        let pressureMultiplier = 0.5 + (avgPressure * 2.5) // 0.5x to 3x
                        let segmentWidth = brushSize * pressureMultiplier
                        
                        cg.setLineWidth(segmentWidth)
                        cg.beginPath()
                        cg.move(to: start.point)
                        cg.addLine(to: end.point)
                        cg.strokePath()
                    }
                }
            }
        }
        
        private func getPressure(from touch: UITouch) -> Double {
            if touch.force > 0 && touch.maximumPossibleForce > 0 {
                return Double(touch.force / touch.maximumPossibleForce)
            } else {
                let radius = touch.majorRadius
                return min(max((radius - 5.0) / 15.0, 0.0), 1.0)
            }
        }
        
        private func calculateBaseImageSize(for image: UIImage, canvasSize: CGSize) -> CGSize {
            let aspect = image.size.width / image.size.height
            let maxDimension = min(canvasSize.width, canvasSize.height) * 0.45
            var width = maxDimension
            var height = width / aspect
            if height > maxDimension {
                height = maxDimension
                width = height * aspect
            }
            return CGSize(width: width, height: height)
        }
    }
    
    // MARK: - Pressure Sensitive Tear Overlay
    private struct PressureSensitiveTearOverlay: UIViewRepresentable {
        @Binding var tearPathPoints: [(point: CGPoint, pressure: Double)]
        @Binding var isTearing: Bool
        let canvasSize: CGSize
        let onTearComplete: () -> Void
        let isActive: Bool
        
        func makeUIView(context: Context) -> PressureTearView {
            let view = PressureTearView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = true
            return view
        }
        
        func updateUIView(_ uiView: PressureTearView, context: Context) {
            uiView.tearPathPoints = tearPathPoints
            uiView.onTearComplete = onTearComplete
            uiView.isActive = isActive
            uiView.updateBinding = { points, isTearing in
                DispatchQueue.main.async {
                    self.tearPathPoints = points
                    self.isTearing = isTearing
                }
            }
        }
    }
    
    // UIView that captures pressure
    class PressureTearView: UIView {
        var tearPathPoints: [(point: CGPoint, pressure: Double)] = []
        var onTearComplete: (() -> Void)?
        var isActive: Bool = true
        var updateBinding: ((_ points: [(point: CGPoint, pressure: Double)], _ isTearing: Bool) -> Void)?
        
        private var pathLayer: CAShapeLayer?
        
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isActive, !hasTriggeredTear, let touch = touches.first else { 
                print("🚫 touchesBegan blocked: isActive=\(isActive), hasTriggeredTear=\(hasTriggeredTear)")
                return 
            }
            
            let location = touch.location(in: self)
            // Use touch radius as pressure proxy for devices without 3D Touch
            let pressure: Double
            if touch.force > 0 && touch.maximumPossibleForce > 0 {
                // 3D Touch devices: use actual force
                pressure = Double(touch.force / touch.maximumPossibleForce)
                print("💪 Pressure from force: \(pressure)")
            } else {
                // Non-3D Touch: use touch radius with better range
                // majorRadius ranges from ~5 (light) to ~20+ (hard press)
                let radius = touch.majorRadius
                let normalizedRadius = min(max((radius - 5.0) / 15.0, 0.0), 1.0)
                pressure = normalizedRadius
                print("💪 Pressure from radius: \(radius) → \(pressure)")
            }
            
            tearPathPoints = [(point: location, pressure: pressure)]
            updateBinding?(tearPathPoints, true)
            
            // Play tear sound at start
            SoundEffectPlayer.shared.playTear()
            
            // Create visual feedback layer
            pathLayer?.removeFromSuperlayer()
            let layer = CAShapeLayer()
            layer.strokeColor = UIColor.red.cgColor
            layer.fillColor = UIColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer.addSublayer(layer)
            pathLayer = layer
            
            updatePath()
        }
        
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard isActive, !hasTriggeredTear, let touch = touches.first else { return }
            
            let location = touch.location(in: self)
            // Use touch radius as pressure proxy for devices without 3D Touch
            let pressure: Double
            if touch.force > 0 && touch.maximumPossibleForce > 0 {
                // 3D Touch devices: use actual force
                pressure = Double(touch.force / touch.maximumPossibleForce)
            } else {
                // Non-3D Touch: use touch radius with better range
                let radius = touch.majorRadius
                let normalizedRadius = min(max((radius - 5.0) / 15.0, 0.0), 1.0)
                pressure = normalizedRadius
            }
            
            tearPathPoints.append((point: location, pressure: pressure))
            updateBinding?(tearPathPoints, true)
            
            updatePath()
        }
        
        private var hasTriggeredTear = false
        
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            pathLayer?.removeFromSuperlayer()
            pathLayer = nil
            
            // Only trigger tear if we have valid points and haven't already triggered
            if tearPathPoints.count >= 2, isActive, !hasTriggeredTear {
                // Set flag immediately to prevent any double-trigger
                hasTriggeredTear = true
                isActive = false
                
                print("🔪 touchesEnded: Triggering tear with \(tearPathPoints.count) points")
                onTearComplete?()
                
                // Reset flags after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isActive = true
                    self.hasTriggeredTear = false
                }
            }
            
            tearPathPoints = []
            updateBinding?(tearPathPoints, false)
        }
        
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            pathLayer?.removeFromSuperlayer()
            pathLayer = nil
            tearPathPoints = []
            updateBinding?(tearPathPoints, false)
        }
        
        private func updatePath() {
            guard tearPathPoints.count >= 2 else { return }
            
            let path = UIBezierPath()
            path.move(to: tearPathPoints[0].point)
            
            // Draw path with varying width based on pressure
            for data in tearPathPoints.dropFirst() {
                path.addLine(to: data.point)
            }
            
            // Calculate average pressure for line width
            let avgPressure = tearPathPoints.map { $0.pressure }.reduce(0, +) / Double(tearPathPoints.count)
            let lineWidth = CGFloat(2 + avgPressure * 4) // 2-6pt based on pressure
            
            pathLayer?.path = path.cgPath
            pathLayer?.lineWidth = lineWidth
        }
    }
    
    // MARK: - Main Action Circle (shared component with gradient)
    private struct MainActionCircle: View {
        let gradient: LinearGradient
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                ZStack {
                    // Outer glow/shadow
                    Circle()
                        .fill(gradient)
                        .frame(width: MainButtonMetrics.diameter + 4, height: MainButtonMetrics.diameter + 4)
                        .blur(radius: 8)
                        .opacity(0.4)
                    
                    // Main button
                    Circle()
                        .fill(gradient)
                        .frame(width: MainButtonMetrics.diameter, height: MainButtonMetrics.diameter)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: MainButtonMetrics.iconSize, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        )
                }
                .contentShape(Circle())
                .fixedSize()
            }
            .buttonStyle(.plain)
        }
    }
    
    
    private var audioDisplayName: String {
        if let metadata = project.musicMetadata {
            return "\(metadata.title) • \(metadata.artist)"
        }
        return "My Sound"
    }
    
    private func toggleAudioPlayback() {
        guard let audio = audioURL() else {
            print("❌ No audio URL found")
            return
        }
        
        print("🔊 Audio file path: \(audio.path)")
        
        // Check file details
        if let attributes = try? FileManager.default.attributesOfItem(atPath: audio.path) {
            let fileSize = attributes[.size] as? Int ?? 0
            print("🔊 File size: \(fileSize) bytes")
            
            if fileSize == 0 {
                print("❌ Audio file is empty (0 bytes) - simulator recording issue")
                print("ℹ️  Audio playback only works on real devices or with actual audio input")
                return
            }
        }
        
        if player.isPlaying {
            print("🔊 Stopping playback")
            player.stop()
        } else {
            print("🔊 Starting playback")
            do {
                try player.play(url: audio)
                print("✅ Playback started successfully")
            } catch {
                print("❌ Playback failed: \(error)")
                print("ℹ️  This is likely due to simulator audio limitations")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            // Undo button
            Button {
                undoLastAction()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 24))
                    Text("Undo")
                        .font(.caption2)
                }
                .frame(width: 70)
                .foregroundStyle(.white)
            }
            .disabled(project.imageLayers.isEmpty && project.textLayers.isEmpty && (project.drawingDataBase64?.isEmpty ?? true))
            .opacity((project.imageLayers.isEmpty && project.textLayers.isEmpty && (project.drawingDataBase64?.isEmpty ?? true)) ? 0.3 : 1.0)
            
            Spacer()
            
            // Other controls (scrollable)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    Button { addTextLayer() } label: { label("Text", "textformat") }
                    
                    Button { showLayerPanel = true } label: { label("Layers", "square.3.layers.3d") }

                    Button {
                        // Set export state immediately for visual feedback
                        isExporting = true
                        exportProgress = 0
                        Task { await export() }
                    } label: { label("Share", "square.and.arrow.up") }
                    .disabled(isExporting)

                    if isExporting {
                        ProgressView(value: exportProgress)
                            .frame(width: 120)
                    }
                }
            }
        }
    }

    private func label(_ title: String, _ system: String) -> some View {
        Label(title, systemImage: system)
            .labelStyle(.iconOnly)
            .font(.system(size: 24))
    }

    private func resetCanvas() {
        // Delete the entire project and all its files
        let projectId = project.id
        
        // Delete all image files
        for layer in project.imageLayers {
            let url = store.urlForProjectAsset(projectId: projectId, fileName: layer.imageFileName)
            try? FileManager.default.removeItem(at: url)
            
            if let erasedFile = layer.erasedImageFileName {
                let erasedUrl = store.urlForProjectAsset(projectId: projectId, fileName: erasedFile)
                try? FileManager.default.removeItem(at: erasedUrl)
            }
        }
        
        // Delete the audio file
        if let audioFileName = project.audioFileName {
            let audioUrl = store.urlForProjectAsset(projectId: projectId, fileName: audioFileName)
            try? FileManager.default.removeItem(at: audioUrl)
        }
        
        // Remove project from store
        store.delete(project)
        
        print("🔄 Moment reset - returning to home screen")
        
        // Notify parent to dismiss and return to initial capture screen
        onReset?()
    }
    
    private func addImages(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        
        // Enforce the app limit (max 10 images total).
        let remainingSlots = max(0, 10 - project.imageLayers.count)
        guard remainingSlots > 0 else { return }
        let images = Array(images.prefix(remainingSlots))
        
        // Capture current state for background processing
        let projectId = project.id
        let currentLayerCount = project.imageLayers.count
        let store = store
        
        // Process images on background thread for better performance
        Task { @MainActor in
            var newLayers: [ImageLayer] = []
            
            // Process all images in parallel on background thread
            await withTaskGroup(of: ImageLayer?.self) { group in
                for (index, image) in images.enumerated() {
                    group.addTask {
                        // Process image off main thread
                        return await Task.detached(priority: .userInitiated) {
            // Downscale to max 1000px on longest side for better performance and memory
                            let downscaled = CollageEditorView.downscaleImageStatic(image, maxDimension: 1000)
            
            let fileName = "img_\(UUID().uuidString).jpg"
            // Use 60% quality for better storage efficiency
                            guard let data = downscaled.jpegData(compressionQuality: 0.60) else { return nil }
                            
                            // urlForProjectAsset is synchronous (just returns a URL, doesn't access async state)
                            let url = store.urlForProjectAsset(projectId: projectId, fileName: fileName)
                            
                            // Write file on background thread
                            do {
                                try data.write(to: url)
                            } catch {
                                print("❌ Failed to write image file \(fileName): \(error)")
                                return nil // Return nil on write failure so this image is skipped
                            }
                
                            let position = CollageEditorView.calculateImagePositionStatic(for: currentLayerCount + index)
                
                var layer = ImageLayer(imageFileName: fileName)
                            layer.transform = Transform2D(x: position.x, y: position.y, scale: 1.4, rotation: 0)
                            layer.zIndex = currentLayerCount + index
                            return layer
                        }.value
                    }
                }
                
                // Collect results
                for await layer in group {
                    if let layer = layer {
                        newLayers.append(layer)
                    }
                }
            }
            
            // Update UI on main thread
            let sortedNewLayers = newLayers.sorted(by: { $0.zIndex < $1.zIndex })
            for layer in sortedNewLayers {
                self.project.imageLayers.append(layer)
            }
            // Single-step undo: only the last added image is undoable.
            if let last = sortedNewLayers.last {
                self.recordUndo(.addImage(layer: last, index: max(0, self.project.imageLayers.count - 1)))
            }
            
            // Reset tool state when images are added - no tools should be active
            self.selectedTool = .pen
            self.isDrawing = false
            self.selectedImageId = nil
            self.showToolbarForSelectedImage = false
            
            // Save asynchronously (already optimized in ProjectStore)
            self.store.update(self.project)
        }
    }
    
    // Static helper functions for background thread execution
    private nonisolated static func downscaleImageStatic(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        return autoreleasepool {
            let size = image.size
            let maxSide = max(size.width, size.height)
            
            // If already small enough, return as-is
            guard maxSide > maxDimension else { return image }
            
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }
    
    private nonisolated static func calculateImagePositionStatic(for index: Int) -> (x: Double, y: Double) {
        let imageWidth: Double = 187 / 2
        let imageHeight: Double = 125
        
        switch index {
        case 0: return (-imageWidth, -imageHeight - 50)
        case 1: return (imageWidth, -imageHeight - 50)
        case 2: return (-imageWidth, imageHeight - 50)
        case 3: return (imageWidth, imageHeight - 50)
        default: return (0, -50)
        }
    }
    
    private func downscaleImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        return autoreleasepool {
            let size = image.size
            let maxSide = max(size.width, size.height)
            
            // If already small enough, return as-is
            guard maxSide > maxDimension else { return image }
            
            let scale = maxDimension / maxSide
            let newSize = CGSize(width: size.width * scale, height: size.height * scale)
            
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
            return renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }
    }

    @ViewBuilder
    private func imageLayerView(for layer: ImageLayer, canvasSize: CGSize, isCoachMarkTarget: Bool = false) -> some View {
        if let ui = loadImage(fileName: layer.imageFileName),
           let idx = layerIndexMap[layer.id] {
            let baseSize = baseImageSize(for: ui, canvasSize: canvasSize)
            
            // Keep same view structure always, just toggle erase mode
            let isErasing = selectedTool == .erase && selectedImageId == layer.id
            
            // Use cached transparency and tight bounds calculations
            let _ = getCachedTransparency(for: layer.imageFileName, image: ui)
            
            ZStack {
                // ALWAYS show the ErasableImageView with consistent identity
                ErasableImageView(
                    image: ui,
                    erasedImageFileName: $project.imageLayers[idx].erasedImageFileName,
                    brushSize: strokeWidth * 3,
                    projectId: project.id,
                    store: store,
                    isEraseMode: isErasing,
                    onImageErased: { fileName in
                        project.imageLayers[idx].erasedImageFileName = fileName
                        store.update(project)
                    }
                )
                .frame(width: baseSize.width, height: baseSize.height)
                .id("erasable-\(layer.id)") // Stable identity
                
                // Removed: Image-specific drawing rendering (drawing is now always canvas-wide)
                
                // Selection border - always present with fixed frame to prevent layout shifts
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 3)
                    .frame(width: baseSize.width, height: baseSize.height) // Always baseSize - never changes
                    .opacity((selectedImageId == layer.id && !isDrawing) ? 1 : 0) // Hide when not selected or when drawing
                    .allowsHitTesting(false)
                
                // Gesture overlay - always present to maintain consistent layout, but disabled when erasing or drawing
                if !isErasing {
                    Group {
                        if selectedTool == .tear {
                            // Tear mode: only tap to select, no transform gestures
                            Color.clear
                                .frame(width: baseSize.width, height: baseSize.height)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !isDrawing {
                                        selectedImageId = layer.id
                                    }
                                }
                                .allowsHitTesting(!isDrawing) // Disable when drawing
                                .zIndex(10)
                        } else {
                            // Normal mode: transform gestures + tap gestures
                            Color.clear
                                .frame(width: baseSize.width, height: baseSize.height)
                                .contentShape(Rectangle())
                                .modifier(TransformModifier(
                                    transform: $project.imageLayers[idx].transform,
                                    isEnabled: !isDrawing, // Disable drag/pinch/rotate when drawing
                                    onGestureActivity: {
                                        lastImageManipulationAt = Date()
                                    },
                                    onGestureEnd: { previous, new in
                                        guard previous != new else { return }
                                        // Record transform edits as an undoable action (single-step).
                                        self.recordUndo(.transform(layerId: layer.id, previous: previous, new: new))
                                        // Persist at gesture end for smooth interaction.
                                        self.store.update(self.project)
                                    }
                                ))
                                .simultaneousGesture(
                                    // Long press - delete image (reversible with undo)
                                    LongPressGesture(minimumDuration: 0.5)
                                        .onEnded { _ in
                                            guard !isDrawing else { return }
                                            print("🗑️ Long press detected - deleting image: \(layer.id)")
                                            
                                            SoundEffectPlayer.shared.playClick()
                                            let generator = UIImpactFeedbackGenerator(style: .medium)
                                            generator.prepare()
                                            generator.impactOccurred(intensity: 0.7)
                                            
                                            // Delay deletion to avoid gesture conflicts
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                self.deleteImage(layer: layer)
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    // Single tap - bring to front and select
                                    TapGesture(count: 1)
                                        .onEnded {
                                            if !isDrawing {
                                                print("👆 Single tap detected - bringing to front!")
                                                // Play click sound
                                                SoundEffectPlayer.shared.playClick()
                                                // Single tap brings image to front and selects it
                                                bringToFront(layer: layer)
                                                // Reset tool state when selecting a new image (no tools active)
                                                selectedTool = .pen
                                                isDrawing = false
                                                // Reset drawing when selecting image
                                                isDrawing = false
                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                    selectedImageId = layer.id
                                                    showToolbarForSelectedImage = true
                                                }
                                            }
                                        }
                                )
                                .allowsHitTesting(!isDrawing) // Disable when drawing
                                .zIndex(10)
                        }
                    }
                }
            }
            .frame(width: baseSize.width, height: baseSize.height) // Fixed frame to prevent layout shifts
            .fixedSize() // Prevent any automatic resizing
            .scaleEffect(project.imageLayers[idx].transform.scale)
            .rotationEffect(.radians(project.imageLayers[idx].transform.rotation))
            .offset(x: project.imageLayers[idx].transform.x, y: project.imageLayers[idx].transform.y)
            .zIndex(Double(layer.zIndex))
            .id("\(layer.id)-\(layer.imageFileName)")
            .applyIf(isCoachMarkTarget) { view in
                view.editorCoachMarkTarget("editor.image")
            }
        }
    }
    
    private func baseImageSize(for image: UIImage, canvasSize: CGSize) -> CGSize {
        let aspect = image.size.width / image.size.height
        let maxDimension = min(canvasSize.width, canvasSize.height) * 0.45
        var width = maxDimension
        var height = width / aspect
        if height > maxDimension {
            height = maxDimension
            width = height * aspect
        }
        return CGSize(width: width, height: height)
    }
    
    /// Check if an image has transparency (alpha channel with actual transparent pixels)
    private func imageHasTransparency(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let alphaInfo = cgImage.alphaInfo
        // Check if image format supports alpha channel
        let hasAlphaChannel = alphaInfo == .first || alphaInfo == .last || 
                               alphaInfo == .premultipliedFirst || alphaInfo == .premultipliedLast
        
        // If no alpha channel support, definitely no transparency
        guard hasAlphaChannel else { return false }
        
        // Quick check: sample corners to see if there's transparency
        // This is a heuristic - if corners are transparent, likely background was removed
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return false }
        
        // Sample a few pixels at corners (where background usually is)
        // If any corner is transparent, assume image has transparency
        let samplePoints = [
            (x: 0, y: 0),                    // Top-left
            (x: width - 1, y: 0),            // Top-right
            (x: 0, y: height - 1),           // Bottom-left
            (x: width - 1, y: height - 1)    // Bottom-right
        ]
        
        // Use a simpler approach: extract pixel data directly
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelData = context.data else { return false }
        let data = pixelData.assumingMemoryBound(to: UInt8.self)
        
        // Check sample points for transparency
        // Safety check: ensure pixel index is within bounds
        let maxPixelIndex = (width * height * bytesPerPixel) - 1
        for point in samplePoints {
            let pixelIndex = (point.y * width + point.x) * bytesPerPixel
            // Bounds check to prevent out-of-bounds access
            guard pixelIndex >= 0 && pixelIndex <= maxPixelIndex else { continue }
            let alpha = data[pixelIndex + 3]
            if alpha < 255 {
                return true // Found transparent pixel
            }
        }
        
        return false
    }
    
    /// Calculate the tight bounds of non-transparent content in an image
    /// Returns the bounding box as a CGRect in image coordinates (0,0 to imageSize)
    private func tightBounds(of image: UIImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelData = context.data else { return nil }
        
        let data = pixelData.assumingMemoryBound(to: UInt8.self)
        
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        
        // Scan for non-transparent pixels
        // Safety check: ensure we don't exceed buffer bounds
        let maxPixelIndex = (width * height * bytesPerPixel) - 1
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * bytesPerPixel
                // Bounds check to prevent out-of-bounds access
                guard pixelIndex >= 0 && pixelIndex <= maxPixelIndex else { continue }
                let alpha = data[pixelIndex + 3]
                if alpha > 0 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // If no opaque pixels found, return full bounds
        if minX > maxX || minY > maxY {
            return CGRect(origin: .zero, size: image.size)
        }
        
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    
    /// Calculate the displayed size of the tight bounds after scaling to baseSize
    private func tightBoundsSize(for image: UIImage, baseSize: CGSize) -> CGSize {
        guard let tightBounds = tightBounds(of: image) else {
            return baseSize
        }
        
        let imageSize = image.size
        let scaleX = baseSize.width / imageSize.width
        let scaleY = baseSize.height / imageSize.height
        
        return CGSize(
            width: tightBounds.width * scaleX,
            height: tightBounds.height * scaleY
        )
    }
    
    private func calculateImagePosition(for index: Int) -> (x: Double, y: Double) {
        // Position images in a 2x2 grid layout
        // Base image size is roughly 170-200 pts, so offsets place them in four quadrants
        // Leave space for audio badge at top (~100pt) and button at bottom (~300pt from bottom)
        
        let imageWidth: Double = 187 / 2  // Half of displayed width for offset from center
        let imageHeight: Double = 125     // Half of displayed height
        
        switch index {
        case 0: // Top left
            return (-imageWidth, -imageHeight - 50)
        case 1: // Top right
            return (imageWidth, -imageHeight - 50)
        case 2: // Bottom left - align top edge with bottom edge of image 1
            return (-imageWidth, imageHeight - 50)
        case 3: // Bottom right - align top edge with bottom edge of image 2
            return (imageWidth, imageHeight - 50)
        default: // Center (5th+ image layered on top)
            return (0, -50)
        }
    }

    // Handle Share button tap (top right) - saves state and immediately triggers export
    private func handleShareButtonTap() {
        print("📤 Share button clicked")
        guard !isExporting else { return }
        
        // Set export state immediately for visual feedback
        isExporting = true
        exportProgress = 0
        
        let startExport: () -> Void = {
            // Save project state
            store.update(project)
            
            // Reset tool state
            selectedTool = .pen
            isDrawing = false
            
            // Clear selection
            selectedImageId = nil
            selectedTextId = nil
            showToolbarForSelectedImage = false
            showTextEditor = false
            
            // Trigger export
            Task { await export() }
        }
        
        // If drawing is active, ensure the drawing save finishes before exporting.
        if isDrawing {
            saveDrawingToProjectIfNeeded {
                startExport()
            }
        } else {
            startExport()
        }
    }
    
    // Save canvas-wide drawing when done (called from paint button or done button)
    private func handleDoneDrawing() {
        saveDrawingToProjectIfNeeded {
            // Save-only; do not exit drawing mode here.
        }
    }
    
    private func finishEraseAndExit() {
        guard isCanvasErasing else { return }
        guard !isFinishingEraseSave else { return }
        isFinishingEraseSave = true

        let dataSnapshot = eraseDrawingData
        let previousEraseBase64 = project.eraseDrawingDataBase64

        Task.detached(priority: .userInitiated) {
            let base64 = dataSnapshot.base64EncodedString()
            let newBase64 = base64.isEmpty ? nil : base64

            await MainActor.run {
                defer { isFinishingEraseSave = false }

                if previousEraseBase64 != newBase64 {
                    recordUndo(.eraseCanvas(previousEraseBase64: previousEraseBase64))
                }

                project.eraseDrawingDataBase64 = newBase64
                store.update(project)

                eraseDrawingData = dataSnapshot
                eraseHistory = [dataSnapshot]
                eraseRedoData = nil

                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isCanvasErasing = false
                    selectedTool = .pen
                }
                print("🧹 Canvas erase saved and exited")
            }
        }
    }

    private func applyEraseDrawing(base64: String?) {
        if let b64 = base64, let data = Data(base64Encoded: b64) {
            eraseDrawingData = data
        } else {
            eraseDrawingData = Data()
        }
        eraseHistory = [eraseDrawingData]
        eraseRedoData = nil
        pencilKitCanvasNonce += 1
    }

    private func undoEraseStroke() {
        isPerformingStrokeUndoRedo = true
        DispatchQueue.main.async { self.isPerformingStrokeUndoRedo = false }

        if let redo = eraseRedoData {
            eraseDrawingData = redo
            if eraseHistory.last != redo { eraseHistory.append(redo) }
            eraseRedoData = nil
            pencilKitCanvasNonce += 1
        } else if eraseHistory.count > 1 {
            eraseRedoData = eraseHistory.last
            eraseHistory.removeLast()
            eraseDrawingData = eraseHistory.last ?? Data()
            pencilKitCanvasNonce += 1
        } else if eraseHistory.count == 1 {
            eraseRedoData = eraseHistory.last
            eraseDrawingData = Data()
            eraseHistory = [Data()]
            pencilKitCanvasNonce += 1
        }
    }

    private func finishDrawingAndExit(onComplete: @escaping () -> Void = {}) {
        isPaintErasing = false
        saveDrawingToProjectIfNeeded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isDrawing = false
                selectedTool = .pen
            }
            onComplete()
        }
    }
    
    private func saveDrawingToProjectIfNeeded(onComplete: @escaping () -> Void) {
        guard isDrawing else {
            onComplete()
            return
        }
        guard !isFinishingDrawingSave else { return }
        isFinishingDrawingSave = true
        
        let dataSnapshot = drawingData
        let previousDrawingBase64 = project.drawingDataBase64
        
        Task.detached(priority: .userInitiated) {
            let base64 = dataSnapshot.base64EncodedString()
            let newBase64 = base64.isEmpty ? nil : base64
            
            await MainActor.run {
                defer { isFinishingDrawingSave = false }
                
                // Add to undo stack if drawing changed
                if previousDrawingBase64 != newBase64 {
                    recordUndo(.draw(previousDrawingBase64: previousDrawingBase64))
                    print("🎨 Added canvas drawing to undo stack")
                }
                
                project.drawingDataBase64 = newBase64
                store.update(project)
                
                // Keep in-memory state aligned with saved state (avoid re-decoding base64 on main).
                drawingData = dataSnapshot
                drawingHistory = [dataSnapshot]
                drawingRedoData = nil
                drawingStateBeforeEdit = nil
                
                onComplete()
            }
        }
    }

    private func applyCanvasDrawing(base64: String?) {
        // Base64 decode for drawings can be large; do it off-main to avoid UI stalls.
        drawingApplyToken += 1
        let token = drawingApplyToken
        let base64Snapshot = base64
        
        Task.detached(priority: .userInitiated) {
            let decodedData: Data
            if let b64 = base64Snapshot, let data = Data(base64Encoded: b64) {
                decodedData = data
            } else {
                decodedData = Data()
            }
            
            await MainActor.run {
                guard drawingApplyToken == token else { return }
                drawingData = decodedData
                drawingHistory = [decodedData]
                drawingRedoData = nil
                pencilKitCanvasNonce += 1
            }
        }
    }

    private func addTextLayer() {
        // Don't play click here - button already plays it
        guard !showTextEditor else { return }

        // If a text layer already exists, re-open the editor for the first one (single text model).
        if project.textLayers.count > 1 {
            let keep = project.textLayers[0]
            project.textLayers = [keep]
            store.update(project)
        }
        if let existing = project.textLayers.first {
            // Delightful haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred(intensity: 0.7)
            
            selectedTextId = existing.id
            editingText = existing.text
            editingTextColor = Color(hex: existing.hexColor)
            editingFontSize = existing.fontSize
            
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self.showTextEditor = true
                }
            }
            print("✏️ Re-opening text editor for existing layer: \(existing.id)")
            return
        }
        
        // Delightful haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred(intensity: 0.7)
        
        // Use "Courier" for classic typewriter style (system font on iOS)
        // Alternative: "American Typewriter" for more stylized look
        let layer = TextLayer(
            text: "",
            fontName: "Courier-Bold",
            fontSize: 32,
            hexColor: "#000000", // Black text for visibility on cork
            transform: .identity
        )
        project.textLayers.append(layer)
        recordUndo(.addText(layer: layer, index: max(0, project.textLayers.count - 1)))
        selectedTextId = layer.id // Auto-select for editing
        editingText = ""
        editingTextColor = Color(hex: layer.hexColor)
        editingFontSize = layer.fontSize
        
        // Defer store update to avoid blocking UI
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.showTextEditor = true
            }
        }
        store.update(project)
        print("✏️ Added text layer with typewriter font - showing editor")
    }
    
    private func bringToFront(layer: ImageLayer) {
        guard let idx = layerIndexMap[layer.id] else { return }
        
        // Find the maximum zIndex
        let maxZ = project.imageLayers.map { $0.zIndex }.max() ?? 0
        
        // Set this layer's zIndex to max + 1
        let newZIndex = maxZ + 1
        project.imageLayers[idx].zIndex = newZIndex
        
        print("🔼 Bringing to front: layer \(idx), old zIndex: \(layer.zIndex), new zIndex: \(newZIndex)")
        print("   All zIndexes: \(project.imageLayers.map { $0.zIndex })")
        
        store.update(project)
    }
    
    private func sendToBack(layer: ImageLayer) {
        guard let idx = layerIndexMap[layer.id] else { return }
        
        // Find the minimum zIndex
        let minZ = project.imageLayers.map { $0.zIndex }.min() ?? 0
        
        // Set this layer's zIndex to min - 1
        project.imageLayers[idx].zIndex = minZ - 1
        store.update(project)
    }
    
    private func deleteImage(layer: ImageLayer) {
        // Prevent deletion during drawing or tool operations
        guard !isDrawing else {
            print("⚠️ Cannot delete image while drawing")
            return
        }
        
        guard let idx = project.imageLayers.firstIndex(where: { $0.id == layer.id }) else {
            print("⚠️ Image not found for deletion")
            return
        }
        
        print("🗑️ Deleting image at index \(idx)")
        
        // Add to undo stack before removing
        recordUndo(.deleteImage(layer: layer, index: idx))
        
        // Remove from project
        project.imageLayers.remove(at: idx)
        
        // Clear selection if this was the selected image
        if selectedImageId == layer.id {
            selectedImageId = nil
            showToolbarForSelectedImage = false
        }
        
        // Update on main thread to prevent race conditions
        DispatchQueue.main.async {
            self.store.update(self.project)
        }
    }
    
    private func deleteTextLayer(layer: TextLayer) {
        guard let idx = project.textLayers.firstIndex(where: { $0.id == layer.id }) else {
            print("⚠️ Text layer not found for deletion")
            return
        }
        
        print("🗑️ Deleting text layer at index \(idx)")
        
        // Add to undo stack before removing
        recordUndo(.deleteText(layer: layer, index: idx))
        
        // Remove from project
        project.textLayers.remove(at: idx)
        
        // Clear selection if this was the selected text
        if selectedTextId == layer.id {
            selectedTextId = nil
            showTextEditor = false
        }
        
        store.update(project)
        print("🗑️ Text layer deleted and added to undo stack")
    }
    
    private func deleteCanvasDrawing() {
        guard let currentDrawing = project.drawingDataBase64, !currentDrawing.isEmpty else {
            print("⚠️ No canvas drawing to delete")
            return
        }
        
        print("🗑️ Deleting canvas drawing")
        
        // Add to undo stack before removing
        recordUndo(.draw(previousDrawingBase64: currentDrawing))
        
        // Clear the drawing
        project.drawingDataBase64 = nil
        drawingData = Data()
        drawingHistory = [Data()]
        
        store.update(project)
        print("🗑️ Canvas drawing deleted and added to undo stack")
    }
    
    private func autoRemoveBackground(for imageId: UUID) {
        // Prevent multiple simultaneous removals
        guard !isRemovingBackground else {
            print("🔄 Background removal already in progress")
            return
        }
        
        guard let idx = layerIndexMap[imageId] else {
            print("⚠️ Image not found for background removal")
            return
        }
        
        let layer = project.imageLayers[idx]
        let imageURL = store.urlForProjectAsset(projectId: project.id, fileName: layer.imageFileName)
        
        guard let currentImage = UIImage(contentsOfFile: imageURL.path) else {
            print("❌ Failed to load image for background removal")
            return
        }
        
        print("🔄 Image loaded - orientation: \(currentImage.imageOrientation.rawValue), size: \(currentImage.size)")
        if let cgImage = currentImage.cgImage {
            print("   CGImage dimensions: \(cgImage.width) x \(cgImage.height)")
        }
        
        // Check if image already has transparency (indicating background was already removed)
        if imageHasTransparency(currentImage) {
            print("⚠️ Image already has background removed (has transparency), skipping")
            return
        }
        
        // Set flag immediately on main thread for immediate UI feedback
        isRemovingBackground = true
        print("🎭 Starting automatic background removal for image: \(imageId)")
        
        Task {
            // CRITICAL: Check if image contains a person BEFORE attempting background removal
            // This prevents the operation from running on images without people
            let hasPerson = await BackgroundRemover.containsPerson(currentImage)
            guard hasPerson else {
                print("⚠️ No person detected in image - skipping background removal")
                print("✅ Image file and layer remain unchanged - no modifications made")
                await MainActor.run {
                    // CRITICAL: Verify image still exists in array before resetting flag
                    if let currentIdx = layerIndexMap[imageId],
                       currentIdx < project.imageLayers.count,
                       project.imageLayers[currentIdx].id == imageId {
                        print("✅ Image layer confirmed still in array at index \(currentIdx)")
                    } else {
                        print("❌ ERROR: Image layer missing from array! This should not happen.")
                    }
                    isRemovingBackground = false
                }
                return
            }
            
            print("✅ Person detected - proceeding with background removal")
            
            // Try to remove background (only if person was detected)
            if let processedImage = await BackgroundRemover.removeBackground(from: currentImage) {
                // Save backup of original image before replacing
                let backupFileName = "backup_\(UUID().uuidString).jpg"
                let backupURL = store.urlForProjectAsset(projectId: project.id, fileName: backupFileName)
                
                // Save backup + processed image off-main to avoid UI stalls.
                let layerFileName = layer.imageFileName
                let projectId = project.id
                let layerId = layer.id
                let imageIdSnapshot = imageId
                
                Task.detached(priority: .userInitiated) {
                    guard let originalData = try? Data(contentsOf: imageURL) else {
                        print("❌ Failed to read original image data for backup")
                        await MainActor.run { isRemovingBackground = false }
                        return
                    }
                    
                    guard let processedData = processedImage.pngData() else {
                        print("❌ Failed to get PNG data from processed image")
                        await MainActor.run { isRemovingBackground = false }
                        return
                    }
                    
                    do {
                        try originalData.write(to: backupURL)
                        print("💾 Saved backup: \(backupFileName)")
                        
                        let url = store.urlForProjectAsset(projectId: projectId, fileName: layerFileName)
                        try processedData.write(to: url)
                        print("✅ Background removed and saved: \(layerFileName)")
                        
                        await MainActor.run {
                            guard let currentIdx = project.imageLayers.firstIndex(where: { $0.id == layerId }) else {
                                isRemovingBackground = false
                                return
                            }
                            
                            // Clear cache FIRST to ensure fresh load (including metadata cache)
                            imageCache.removeValue(forKey: layerFileName)
                            imageMetadataCache.removeValue(forKey: layerFileName)
                            updateCacheAccessOrder(for: layerFileName)
                            
                            // Update the layer to use the new image
                            project.imageLayers[currentIdx].erasedImageFileName = nil // Clear erased version if any
                            store.update(project)
                            
                            // Add undo action
                            let undoAction = UndoAction.removeBackground(layerId: layerId, backupFileName: backupFileName)
                            recordUndo(undoAction)
                            print("🔄 Added background removal to undo stack")
                            
                            isRemovingBackground = false
                            
                            // Clear selection to remove blue border after mask operation
                            if selectedImageId == imageIdSnapshot {
                                selectedImageId = nil
                                showToolbarForSelectedImage = false
                                print("🔄 Cleared selection after mask operation")
                            }
                        }
                    } catch {
                        print("❌ Failed to save background-removed image: \(error)")
                        try? FileManager.default.removeItem(at: backupURL)
                        await MainActor.run { isRemovingBackground = false }
                    }
                }
            } else {
                // This should rarely happen since we check for person first
                // Background removal failed despite person being detected (processing error)
                print("⚠️ Background removal failed despite person detection - keeping original image unchanged")
                await MainActor.run {
                    isRemovingBackground = false
                }
            }
        }
    }
    
    private func undoLastAction() {
        // Don't undo image actions while in drawing mode
        if isDrawing {
            print("⚠️ Undo blocked - currently in drawing mode, use drawing toolbar undo")
            return
        }
        
        guard !isUndoRedoBusy else { return }
        
        // Second tap toggles to redo.
        if redoBuffer != nil {
            redoLastAction()
            return
        }
        
        print("🔄 Undo stack size: \(undoStack.count)")
        print("🔄 Undo stack contents: \(undoStack.map { String(describing: $0) })")
        
        isPerformingUndoRedo = true
        DispatchQueue.main.async {
            self.isPerformingUndoRedo = false
        }
        
        guard let actionToUndo = undoStack.popLast() else {
            print("⚠️ No actions to undo")
            return
        }
        
        var newRedo = RedoBuffer(action: actionToUndo)
        
        print("🔄 Undoing action: \(actionToUndo)")
        switch actionToUndo {
        case let .split(original, pieces):
            project.imageLayers.removeAll { layer in
                pieces.contains(where: { $0.imageFileName == layer.imageFileName })
            }
            project.imageLayers.append(original)
            store.update(project)
            redoBuffer = newRedo
            return
            
        case let .deleteImage(layer, index):
            if index >= 0 && index <= project.imageLayers.count {
                project.imageLayers.insert(layer, at: index)
            } else {
                project.imageLayers.append(layer)
            }
            store.update(project)
            redoBuffer = newRedo
            return
            
        case let .addImage(layer, _):
            if let idx = project.imageLayers.firstIndex(where: { $0.id == layer.id }) {
                project.imageLayers.remove(at: idx)
                if selectedImageId == layer.id {
                    selectedImageId = nil
                    showToolbarForSelectedImage = false
                }
                store.update(project)
            }
            redoBuffer = newRedo
            return
            
        case let .erase(layerId, previousFileName):
            if let idx = layerIndexMap[layerId] {
                newRedo.eraseRedoFileName = project.imageLayers[idx].erasedImageFileName
                project.imageLayers[idx].erasedImageFileName = previousFileName
                store.update(project)
            }
            redoBuffer = newRedo
            return
            
        case let .draw(previousDrawingBase64):
            newRedo.drawRedoBase64 = project.drawingDataBase64

            project.drawingDataBase64 = previousDrawingBase64
            applyCanvasDrawing(base64: previousDrawingBase64)
            store.update(project)
            redoBuffer = newRedo
            return

        case let .eraseCanvas(previousEraseBase64):
            newRedo.eraseCanvasRedoBase64 = project.eraseDrawingDataBase64

            project.eraseDrawingDataBase64 = previousEraseBase64
            applyEraseDrawing(base64: previousEraseBase64)
            store.update(project)
            redoBuffer = newRedo
            return

        case let .addText(layer, _):
            project.textLayers.removeAll { $0.id == layer.id }
            store.update(project)
            redoBuffer = newRedo
            return
            
        case let .deleteText(layer, index):
            // Enforce single text layer.
            project.textLayers = [layer]
            store.update(project)
            redoBuffer = newRedo
            return
            
        case let .removeBackground(layerId, backupFileName):
            guard let idx = layerIndexMap[layerId] else {
                redoBuffer = newRedo
                return
            }
            
            isUndoRedoBusy = true
            
            let layer = project.imageLayers[idx]
            let projectId = project.id
            let layerFileName = layer.imageFileName
            let backupURL = store.urlForProjectAsset(projectId: projectId, fileName: backupFileName)
            let originalURL = store.urlForProjectAsset(projectId: projectId, fileName: layerFileName)
            
            Task.detached(priority: .userInitiated) {
                var redoProcessedFileName: String? = nil
                
                // Save current processed image so redo can re-apply it.
                if FileManager.default.fileExists(atPath: originalURL.path),
                   let processedData = try? Data(contentsOf: originalURL) {
                    let name = "redo_bgrem_\(UUID().uuidString).png"
                    let redoProcessedURL = store.urlForProjectAsset(projectId: projectId, fileName: name)
                    try? processedData.write(to: redoProcessedURL)
                    redoProcessedFileName = name
                }
                
                // Restore original from backup (keep backup so undo works again after redo).
                if FileManager.default.fileExists(atPath: backupURL.path),
                   let backupData = try? Data(contentsOf: backupURL) {
                    try? backupData.write(to: originalURL)
                }
                
                await MainActor.run {
                    newRedo.removeBackgroundProcessedFileName = redoProcessedFileName
                    
                    imageCache.removeValue(forKey: layerFileName)
                    imageMetadataCache.removeValue(forKey: layerFileName)
                    updateCacheAccessOrder(for: layerFileName)
                    store.update(project)
                    
                    redoBuffer = newRedo
                    isUndoRedoBusy = false
                }
            }
            return
            
        case let .transform(layerId, previous, _):
            if let idx = layerIndexMap[layerId] {
                project.imageLayers[idx].transform = previous
                store.update(project)
            }
            redoBuffer = newRedo
            return
        }
    }
    
    private func redoLastAction() {
        guard let redo = redoBuffer else { return }
        guard !isUndoRedoBusy else { return }
        
        isPerformingUndoRedo = true
        DispatchQueue.main.async {
            self.isPerformingUndoRedo = false
        }
        
        print("🔁 Redoing action: \(redo.action)")
        
        switch redo.action {
        case let .split(original, pieces):
            project.imageLayers.removeAll { $0.id == original.id }
            project.imageLayers.append(contentsOf: pieces)
            store.update(project)
            
        case let .addImage(layer, index):
            if project.imageLayers.contains(where: { $0.id == layer.id }) == false {
                if index >= 0 && index <= project.imageLayers.count {
                    project.imageLayers.insert(layer, at: index)
                } else {
                    project.imageLayers.append(layer)
                }
                store.update(project)
            }
            
        case let .deleteImage(layer, _):
            if let idx = project.imageLayers.firstIndex(where: { $0.id == layer.id }) {
                project.imageLayers.remove(at: idx)
                if selectedImageId == layer.id {
                    selectedImageId = nil
                    showToolbarForSelectedImage = false
                }
                store.update(project)
            }
            
        case let .erase(layerId, _):
            if let idx = layerIndexMap[layerId] {
                project.imageLayers[idx].erasedImageFileName = redo.eraseRedoFileName
                store.update(project)
            }
            
        case .draw:
            project.drawingDataBase64 = redo.drawRedoBase64
            applyCanvasDrawing(base64: redo.drawRedoBase64)
            store.update(project)

        case .eraseCanvas:
            project.eraseDrawingDataBase64 = redo.eraseCanvasRedoBase64
            applyEraseDrawing(base64: redo.eraseCanvasRedoBase64)
            store.update(project)

        case let .addText(layer, index):
            // Enforce single text layer.
            project.textLayers = [layer]
            store.update(project)
            
        case let .deleteText(layer, _):
            project.textLayers.removeAll { $0.id == layer.id }
            store.update(project)
            
        case let .removeBackground(layerId, _):
            guard let idx = layerIndexMap[layerId] else { break }
            guard let processedFileName = redo.removeBackgroundProcessedFileName else { break }
            
            isUndoRedoBusy = true
            
            let layer = project.imageLayers[idx]
            let projectId = project.id
            let layerFileName = layer.imageFileName
            let originalURL = store.urlForProjectAsset(projectId: projectId, fileName: layerFileName)
            let processedURL = store.urlForProjectAsset(projectId: projectId, fileName: processedFileName)
            
            Task.detached(priority: .userInitiated) {
                if FileManager.default.fileExists(atPath: processedURL.path),
                   let processedData = try? Data(contentsOf: processedURL) {
                    try? processedData.write(to: originalURL)
                }
                
                // Clean up the redo temp file (backup stays for potential undo).
                try? FileManager.default.removeItem(at: processedURL)
                
                await MainActor.run {
                    imageCache.removeValue(forKey: layerFileName)
                    imageMetadataCache.removeValue(forKey: layerFileName)
                    updateCacheAccessOrder(for: layerFileName)
                    store.update(project)
                    
                    // After redo, the same action becomes undoable again (single-step).
                    undoStack = [redo.action]
                    redoBuffer = nil
                    isUndoRedoBusy = false
                }
            }
            return
            
        case let .transform(layerId, _, new):
            if let idx = layerIndexMap[layerId] {
                project.imageLayers[idx].transform = new
                store.update(project)
            }
        }
        
        // After redo, the same action becomes undoable again (single-step).
        undoStack = [redo.action]
        redoBuffer = nil
    }
    
    private func clearRedoBuffer(deleteBackupForRemoveBackground: Bool) {
        guard let redo = redoBuffer else { return }
        
        if case let .removeBackground(_, backupFileName) = redo.action {
            if let processed = redo.removeBackgroundProcessedFileName {
                let processedURL = store.urlForProjectAsset(projectId: project.id, fileName: processed)
                try? FileManager.default.removeItem(at: processedURL)
            }
            
            if deleteBackupForRemoveBackground {
                let backupURL = store.urlForProjectAsset(projectId: project.id, fileName: backupFileName)
                try? FileManager.default.removeItem(at: backupURL)
            }
        }
        
        redoBuffer = nil
    }

    private func startRecording() {
        let fileName = "audio_\(UUID().uuidString).m4a"
        let url = store.urlForProjectAsset(projectId: project.id, fileName: fileName)
        do {
            try recorder.startRecording(to: url)
            project.audioFileName = fileName
            store.update(project)
        } catch {
            print("Recording failed: \(error)")
        }
    }

    private func audioURL() -> URL? {
        guard let name = project.audioFileName else { return nil }
        return store.urlForProjectAsset(projectId: project.id, fileName: name)
    }

    private func export() async {
        print("🎬 Export function called")
        
        guard purchases.canExport else {
            print("❌ Cannot export - showing paywall")
            await MainActor.run {
                isExporting = false
                exportProgress = 0
                showPaywall = true
            }
            return
        }
        
        print("✅ Export allowed, starting export process...")
        // isExporting already set to true before this function is called for immediate feedback
        
        do {
            print("🎬 Step 1: Rendering collage image...")
            // Render off-main to avoid UI freezes.
            let size = await MainActor.run { UIScreen.main.bounds.size }
            let scale = await MainActor.run { UIScreen.main.scale }
            let projectSnapshot = project
            let collageImage = await CollageRenderer.renderAsync(
                project: projectSnapshot,
                assetURLProvider: assetURL,
                canvasSize: size,
                screenScale: scale
            )
            guard let collageImage else {
                print("❌ Failed to render collage")
                await MainActor.run {
                    exportError = "Failed to render collage image"
                    showExportError = true
                    isExporting = false
                }
                return
            }
            print("✅ Collage image rendered: \(collageImage.size)")
            await MainActor.run {
                exportProgress = 0.1
            }
            
            print("🎬 Step 2: Checking audio...")
            // Get audio URL and duration
            guard let audioName = project.audioFileName else {
                print("❌ No audio file name")
                await MainActor.run {
                    exportError = "No audio file found. Please record audio first."
                    showExportError = true
                    isExporting = false
                }
                return
            }
            
            guard let audioURL = assetURL(for: audioName) else {
                print("❌ Cannot get audio URL for: \(audioName)")
                await MainActor.run {
                    exportError = "Cannot find audio file"
                    showExportError = true
                    isExporting = false
                }
                return
            }
            
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                print("❌ Audio file does not exist at: \(audioURL.path)")
                await MainActor.run {
                    exportError = "Audio file not found"
                    showExportError = true
                    isExporting = false
                }
                return
            }
            
            // Get duration from project, or calculate from audio file if not available
            var duration: TimeInterval
            if let savedDuration = project.audioDuration, savedDuration > 0 {
                duration = savedDuration
                print("✅ Using saved audio duration: \(duration)s")
            } else {
                // Calculate duration from audio file
                print("⚠️ Audio duration not in project, calculating from file...")
                let audioAsset = AVAsset(url: audioURL)
                if let calculatedDuration = try? await audioAsset.load(.duration).seconds, calculatedDuration > 0 {
                    duration = calculatedDuration
                    print("✅ Calculated audio duration from file: \(duration)s")
                    // Save it to the project for future use
                    await MainActor.run {
                        project.audioDuration = duration
                        store.update(project)
                    }
                } else {
                    print("❌ Could not calculate audio duration from file")
                    await MainActor.run {
                        exportError = "Could not read audio file. Please try recording again."
                        showExportError = true
                        isExporting = false
                    }
                    return
                }
            }
            
            print("✅ Audio found: \(audioURL.lastPathComponent), duration: \(duration)s")
            await MainActor.run {
                exportProgress = 0.2
            }
            
            // Create output video URL
            let videoName = "\(project.name.replacingOccurrences(of: " ", with: "_"))_\(UUID().uuidString.prefix(8)).mp4"
            let videoURL = FileManager.default.temporaryDirectory.appendingPathComponent(videoName)
            print("🎬 Step 3: Creating video at: \(videoURL.lastPathComponent)")
            
            // Export as MP4 video with music metadata overlay
            try await MP4VideoExporter.export(
                image: collageImage,
                audioURL: audioURL,
                duration: duration,
                outputURL: videoURL,
                musicMetadata: project.musicMetadata,
                progress: { progressValue in
                    DispatchQueue.main.async {
                        exportProgress = 0.2 + (progressValue * 0.8) // Scale to 0.2-1.0
                    }
                }
            )
            
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                print("❌ Video file was not created")
                await MainActor.run {
                    exportError = "Video file was not created"
                    showExportError = true
                    isExporting = false
                }
                return
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
            print("✅ Video created successfully: \(videoURL.lastPathComponent) (\(fileSize) bytes)")
            
            purchases.registerSuccessfulExport()
            
            // Present share sheet immediately - no delay needed
            await MainActor.run {
                print("🎬 Step 4: Presenting share sheet...")
                isExporting = false
                
                // Find the topmost view controller using the extension method that was working before
                guard let rootVC = UIApplication.shared.firstKeyWindow?.rootViewController else {
                    print("❌ Cannot find root view controller")
                    exportError = "Cannot present share sheet"
                    showExportError = true
                    return
                }
                
                print("✅ Found root view controller: \(type(of: rootVC))")
                
                // Find the topmost presented view controller
                var topViewController = rootVC
                while let presented = topViewController.presentedViewController {
                    topViewController = presented
                    print("✅ Found presented view controller: \(type(of: topViewController))")
                }
                
                print("✅ Using top view controller: \(type(of: topViewController))")
                
                // Create and present share sheet
                let av = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
                
                // For iPad support
                if let popover = av.popoverPresentationController,
                   let window = UIApplication.shared.firstKeyWindow {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                    print("✅ Configured iPad popover")
                }
                
                print("✅ About to present share sheet from: \(type(of: topViewController))")
                topViewController.present(av, animated: true) {
                    print("✅ Share sheet presented successfully")
                }
            }
        } catch {
            print("❌ Export failed with error: \(error.localizedDescription)")
            await MainActor.run {
                exportError = "Export failed: \(error.localizedDescription)"
                showExportError = true
        isExporting = false
            }
        }
    }

    private func assetURL(for fileName: String) -> URL? {
        store.urlForProjectAsset(projectId: project.id, fileName: fileName)
    }
    
    private func calculateImageBounds(canvasSize: CGSize) -> [ImageBounds] {
        var bounds: [ImageBounds] = []
        
        print("📐 BOUNDS: Canvas size: \(canvasSize)")
        
        for layer in project.imageLayers {
            guard let ui = loadImage(fileName: layer.imageFileName) else { continue }
            
            let baseSize = baseImageSize(for: ui, canvasSize: canvasSize)
            let transform = layer.transform
            
            print("📐 BOUNDS: Layer \(layer.id.uuidString.prefix(8))")
            print("   Transform: x=\(transform.x) y=\(transform.y) scale=\(transform.scale)")
            print("   Canvas center would be: (\(canvasSize.width/2), \(canvasSize.height/2))")
            print("   Transform offset from center: (\(transform.x), \(transform.y))")
            print("   Base size (before scale): \(baseSize)")
            
            // Images in ZStack are centered at canvas center, then offset by transform
            // But touch coordinates seem to be in a different space
            // Let's try WITHOUT any Y offset first to see the raw calculation
            let centerX = canvasSize.width / 2 + transform.x
            let centerY = canvasSize.height / 2 + transform.y
            
            let scaledWidth = baseSize.width * transform.scale
            let scaledHeight = baseSize.height * transform.scale
            
            let rawFrame = CGRect(
                x: centerX - scaledWidth / 2,
                y: centerY - scaledHeight / 2,
                width: scaledWidth,
                height: scaledHeight
            )
            
            print("   Raw frame (no offset): \(rawFrame)")
            
            // Now add the empirical offset we've been using
            let yOffset: CGFloat = 250
            let adjustedFrame = rawFrame.offsetBy(dx: 0, dy: yOffset)
            print("   Adjusted frame (+\(yOffset)pt Y): \(adjustedFrame)")
            
            bounds.append(ImageBounds(id: layer.id, frame: adjustedFrame, zIndex: layer.zIndex))
        }
        
        return bounds
    }
    
    private enum SplitDirection {
        case horizontal, vertical
    }
    
    private func performTearOnSelectedImage(canvasSize: CGSize) {
        let now = Date()
        print("🔍 performTearOnSelectedImage called. isTearProcessing: \(isTearProcessing), time since last: \(now.timeIntervalSince(lastTearTimestamp))s")
        
        // Prevent double-tear with both flag and timestamp check
        guard !isTearProcessing else {
            print("⏸️ Tear already in progress, skipping")
            return
        }
        
        // Also prevent tears within 1 second of each other
        guard now.timeIntervalSince(lastTearTimestamp) > 1.0 else {
            print("⏸️ Tear too soon after last tear, skipping")
            return
        }
        
        guard let selectedId = selectedImageId,
              let idx = layerIndexMap[selectedId],
              let ui = loadImage(fileName: project.imageLayers[idx].imageFileName),
              tearPathPoints.count >= 2 else {
            print("❌ Tear failed: insufficient data - selectedId: \(String(describing: selectedImageId)), points: \(tearPathPoints.count)")
            selectedImageId = nil
            isTearProcessing = false
            return
        }
        
        print("✂️ Starting tear on image \(selectedId), index: \(idx), points: \(tearPathPoints.count), current layer count: \(project.imageLayers.count)")
        
        // IMPORTANT: Capture data BEFORE clearing state
        let layer = project.imageLayers[idx]
        let baseSize = baseImageSize(for: ui, canvasSize: canvasSize)
        let transform = layer.transform
        let capturedTearPoints = tearPathPoints // Capture before clearing!
        
        // Set flags immediately and clear state to prevent re-entry
        isTearProcessing = true
        lastTearTimestamp = now
        selectedImageId = nil
        tearPathPoints = []
        isTearingSelectedImage = false
        
        // Calculate where the image is rendered
        // The canvas view centers images using ZStack, then applies transform offset
        let imageCenterX = canvasSize.width / 2 + transform.x
        let imageCenterY = canvasSize.height / 2 + transform.y
        
        let scaledWidth = baseSize.width * transform.scale
        let scaledHeight = baseSize.height * transform.scale
        
        // Calculate image bounds (top-left corner)
        let imageLeft = imageCenterX - scaledWidth / 2
        let imageTop = imageCenterY - scaledHeight / 2
        
        // Convert tear path from canvas coordinates to image pixel coordinates
        let imagePath = UIBezierPath()
        var validPoints = 0
        
        print("📍 Converting \(capturedTearPoints.count) tear points to image coordinates")
        print("📍 Image bounds: left=\(imageLeft), top=\(imageTop), scaledWidth=\(scaledWidth), scaledHeight=\(scaledHeight)")
        
        var firstImagePoint: CGPoint?
        var lastImagePoint: CGPoint?
        
        for pathData in capturedTearPoints {
            let canvasPoint = pathData.point
            
            // Convert canvas point to image-relative coordinates (0 to scaledWidth/Height)
            let relativeX = canvasPoint.x - imageLeft
            let relativeY = canvasPoint.y - imageTop
            
            // Normalize to 0-1 range, then scale to actual image pixel coordinates
            let normalizedX = relativeX / scaledWidth
            let normalizedY = relativeY / scaledHeight
            
            let imageX = normalizedX * ui.size.width
            let imageY = normalizedY * ui.size.height
            
            // CLAMP points to image bounds (don't filter them out)
            // This ensures the tear path extends naturally to the edges
            let clampedX = max(0, min(ui.size.width, imageX))
            let clampedY = max(0, min(ui.size.height, imageY))
            let imagePoint = CGPoint(x: clampedX, y: clampedY)
            
            if validPoints == 0 {
                imagePath.move(to: imagePoint)
                firstImagePoint = imagePoint
            } else {
                imagePath.addLine(to: imagePoint)
            }
            lastImagePoint = imagePoint
            validPoints += 1
        }
        
        // Check if this is a closed path (circle/loop)
        if let first = firstImagePoint, let last = lastImagePoint {
            let distance = hypot(last.x - first.x, last.y - first.y)
            let threshold = min(ui.size.width, ui.size.height) * 0.1 // 10% of smallest dimension
            
            if distance < threshold {
                imagePath.close()
                print("✂️ Closed path detected (distance: \(distance), threshold: \(threshold))")
            } else {
                print("✂️ Open path (distance: \(distance), threshold: \(threshold))")
            }
        }
        
        guard validPoints >= 2 else {
            print("❌ Tear failed: path doesn't cross image (valid points: \(validPoints))")
            selectedImageId = nil
            return
        }
        
        print("✂️ Starting tear with \(validPoints) valid points")
        
        // Split on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let (first, second) = ImageSplitter.splitImage(ui, alongPath: imagePath)
            
            guard let piece1 = first, let piece2 = second else {
                print("❌ ImageSplitter returned nil pieces")
                return
            }
            
            let fileName1 = "torn_1_\(UUID().uuidString).png"
            let fileName2 = "torn_2_\(UUID().uuidString).png"
            
            let url1 = self.store.urlForProjectAsset(projectId: self.project.id, fileName: fileName1)
            let url2 = self.store.urlForProjectAsset(projectId: self.project.id, fileName: fileName2)
            
            if let data1 = piece1.pngData(), let data2 = piece2.pngData() {
                do {
                    try data1.write(to: url1)
                    try data2.write(to: url2)
                    
                    print("✂️ Saved split images: \(fileName1), \(fileName2)")
                    
                    DispatchQueue.main.async {
                        self.handleImageSplit(
                            originalLayer: layer,
                            originalIndex: idx,
                            topFileName: fileName1,
                            bottomFileName: fileName2,
                            originalTransform: layer.transform
                        )
                        // Reset processing flag and auto-deselect tool
                        self.isTearProcessing = false
                        
                        // Auto-complete: deselect tool so user can immediately move pieces
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.selectedTool = .pen
                            self.selectedImageId = nil
                            self.showToolbarForSelectedImage = false
                        }
                    }
                } catch {
                    print("❌ Failed to save split images: \(error)")
                    DispatchQueue.main.async {
                        self.isTearProcessing = false
                    }
                }
            }
        }
    }
    
    private func handleTearGesture(layerId: UUID, pathPoints: [CGPoint], canvasSize: CGSize) {
        print("✂️ HANDLER: Tear gesture received for layer \(layerId)")
        
        guard let idx = layerIndexMap[layerId] else {
            print("✂️ HANDLER: ❌ Layer not found")
            return
        }
        
        guard let ui = loadImage(fileName: project.imageLayers[idx].imageFileName) else {
            print("✂️ HANDLER: ❌ Image not loaded")
            return
        }
        
        print("✂️ HANDLER: Image loaded, size: \(ui.size)")
        
        let layer = project.imageLayers[idx]
        let baseSize = baseImageSize(for: ui, canvasSize: canvasSize)
        let transform = layer.transform
        
        // Calculate where the image is actually rendered on canvas
        let yOffset: CGFloat = 250 // Same offset used in bounds calculation
        let imageCenterX = canvasSize.width / 2 + transform.x
        let imageCenterY = canvasSize.height / 2 + transform.y + yOffset
        
        let scaledWidth = baseSize.width * transform.scale
        let scaledHeight = baseSize.height * transform.scale
        
        // Convert canvas path points to image pixel coordinates
        let imagePath = UIBezierPath()
        for (i, canvasPoint) in pathPoints.enumerated() {
            // Convert from canvas coords to image-relative coords
            let relativeX = canvasPoint.x - (imageCenterX - scaledWidth / 2)
            let relativeY = canvasPoint.y - (imageCenterY - scaledHeight / 2)
            
            // Scale to image pixel coordinates
            let imageX = (relativeX / scaledWidth) * ui.size.width
            let imageY = (relativeY / scaledHeight) * ui.size.height
            
            let imagePoint = CGPoint(x: imageX, y: imageY)
            
            if i == 0 {
                imagePath.move(to: imagePoint)
            } else {
                imagePath.addLine(to: imagePoint)
            }
        }
        
        print("✂️ HANDLER: Starting split on background thread...")
        
        // Split on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let (first, second) = ImageSplitter.splitImage(ui, alongPath: imagePath)
            
            guard let topImage = first, let bottomImage = second else {
                print("✂️ HANDLER: ❌ Split failed")
                return
            }
            
            print("✂️ HANDLER: ✅ Split succeeded, saving files...")
            
            let topFileName = "torn_top_\(UUID().uuidString).png"
            let bottomFileName = "torn_bottom_\(UUID().uuidString).png"
            
            let topURL = self.store.urlForProjectAsset(projectId: self.project.id, fileName: topFileName)
            let bottomURL = self.store.urlForProjectAsset(projectId: self.project.id, fileName: bottomFileName)
            
            if let topData = topImage.pngData(),
               let bottomData = bottomImage.pngData() {
                do {
                    try topData.write(to: topURL)
                    try bottomData.write(to: bottomURL)
                    
                    print("✂️ HANDLER: ✅ Files saved, updating UI...")
                    
                    DispatchQueue.main.async {
                        self.handleImageSplit(
                            originalLayer: layer,
                            originalIndex: idx,
                            topFileName: topFileName,
                            bottomFileName: bottomFileName,
                            originalTransform: layer.transform
                        )
                    }
                } catch {
                    print("✂️ HANDLER: ❌ File save failed: \(error)")
                }
            }
        }
    }
    
    private func handleImageSplit(
        originalLayer: ImageLayer,
        originalIndex: Int,
        topFileName: String,
        bottomFileName: String,
        originalTransform: Transform2D
    ) {
        print("✂️ SPLIT: Called! Current layer count: \(project.imageLayers.count), removing index \(originalIndex)")
        
        // Guard against invalid index
        guard originalIndex < project.imageLayers.count else {
            print("❌ SPLIT: Invalid index \(originalIndex), layer count: \(project.imageLayers.count)")
            return
        }
        
        // Remove the original image layer
        project.imageLayers.remove(at: originalIndex)
        print("✂️ SPLIT: Removed layer. New count: \(project.imageLayers.count)")
        
        // Calculate separation: move pieces apart by 7.5% in opposite directions
        let separationDistance: CGFloat = 20 // pixels
        
        // Create two new layers for the split pieces
        // First piece moves up and slightly left
        var topTransform = originalTransform
        topTransform.x -= separationDistance * 0.5
        topTransform.y -= separationDistance
        
        let topLayer = ImageLayer(
            imageFileName: topFileName,
            opacity: originalLayer.opacity,
            transform: topTransform,
            zIndex: originalLayer.zIndex
        )
        
        // Second piece moves down and slightly right
        var bottomTransform = originalTransform
        bottomTransform.x += separationDistance * 0.5
        bottomTransform.y += separationDistance
        
        let bottomLayer = ImageLayer(
            imageFileName: bottomFileName,
            opacity: originalLayer.opacity,
            transform: bottomTransform,
            zIndex: originalLayer.zIndex + 1
        )
        
        print("✂️ SPLIT: Adding two new layers")
        
        // Push undo action BEFORE mutating store further
        recordUndo(.split(original: originalLayer, pieces: [topLayer, bottomLayer]))
        
        // Add both new layers
        project.imageLayers.append(topLayer)
        project.imageLayers.append(bottomLayer)
        store.update(project)
        
        print("✂️ SPLIT: ✅ Complete! Total layers now: \(project.imageLayers.count)")
    }
}

struct TransformableImage<Overlay: View>: View {
    let uiImage: UIImage
    let baseSize: CGSize
    @Binding var transform: Transform2D
    let overlay: Overlay

    init(uiImage: UIImage, baseSize: CGSize, transform: Binding<Transform2D>, @ViewBuilder overlay: () -> Overlay) {
        self.uiImage = uiImage
        self.baseSize = baseSize
        self._transform = transform
        self.overlay = overlay()
    }

    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .frame(width: baseSize.width, height: baseSize.height)
            .overlay(overlay)
            .modifier(TransformModifier(transform: $transform))
    }
}

extension TransformableImage where Overlay == EmptyView {
    init(uiImage: UIImage, baseSize: CGSize, transform: Binding<Transform2D>) {
        self.init(uiImage: uiImage, baseSize: baseSize, transform: transform) {
            EmptyView()
        }
    }
}

// Delightful scale button style for text editor
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct TextEditorOverlay: View {
    @Binding var isShowing: Bool
    @Binding var text: String
    @Binding var textColor: Color
    @Binding var fontSize: Double
    var onDone: () -> Void
    var onCancel: () -> Void
    @FocusState private var isFocused: Bool
    
    @State private var isPresented = false
    @State private var keyboardOverlap: CGFloat = 0
    
    var body: some View {
        ZStack {
            backdropView
            panelView
        }
        // Overlay controls its own visibility via `isShowing`, so it should never get "stuck".
        .allowsHitTesting(true)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isPresented = true
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, UIScreen.main.bounds.height - frame.minY)
            withAnimation(.easeOut(duration: 0.18)) {
                keyboardOverlap = overlap
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.18)) {
                keyboardOverlap = 0
            }
        }
    }
    
    private var backdropView: some View {
        Color.black.opacity(isPresented ? 0.3 : 0)
            .ignoresSafeArea()
            .animation(.easeOut(duration: 0.2), value: isPresented)
            .onTapGesture {
                dismissKeyboard()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
                isShowing = false
                DispatchQueue.main.async { onCancel() }
            }
    }
    
    private var panelView: some View {
        VStack {
            Spacer()
            editorPanel
        }
    }
    
    private var editorPanel: some View {
        HStack(spacing: 10) {
            textFieldView
                .frame(minWidth: 200) // Give text field more room
            colorPickerView
            doneButton
            cancelButton
        }
        .padding(12)
        .background(panelBackground)
        .frame(maxWidth: 420)
        .padding(.horizontal, 20)
        .padding(.bottom, 30 + keyboardOverlap)
        .scaleEffect(isPresented ? 1.0 : 0.8)
        .opacity(isPresented ? 1.0 : 0.0)
        .offset(y: isPresented ? 0 : 20)
    }
    
    private var textFieldView: some View {
        TextField("Type text", text: $text)
            .font(.custom("Courier-Bold", size: 16))
            .foregroundColor(.black) // Always black in editor for visibility
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white)
            .cornerRadius(8)
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit {
                handleSubmit()
            }
            .scaleEffect(isFocused ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isFocused)
    }
    
    private var colorPickerView: some View {
        HStack(spacing: 6) {
            colorButton(color: .black, isSelected: textColor == .black)
            colorButton(color: .white, isSelected: textColor == .white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
    }
    
    private func colorButton(color: Color, isSelected: Bool) -> some View {
        Button {
            SoundEffectPlayer.shared.playClick()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                textColor = color
            }
        } label: {
            Circle()
                .fill(color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(isSelected ? (color == .black ? Color.white : Color.black) : Color.clear, lineWidth: 1.5)
                )
                .scaleEffect(isSelected ? 1.1 : 1.0)
        }
        .buttonStyle(.plain)
    }
    
    private var doneButton: some View {
        Button {
            handleDone()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue)
                .clipShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var cancelButton: some View {
        Button {
            handleCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.7))
                .clipShape(Circle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.95))
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
    
    private func handleSubmit() {
        SoundEffectPlayer.shared.playClick()
        dismissKeyboard()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
        isShowing = false
        DispatchQueue.main.async { onDone() }
    }
    
    private func handleDone() {
        SoundEffectPlayer.shared.playClick()
        dismissKeyboard()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
        isShowing = false
        DispatchQueue.main.async { onDone() }
    }
    
    private func handleCancel() {
        SoundEffectPlayer.shared.playClick()
        dismissKeyboard()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPresented = false }
        isShowing = false
        DispatchQueue.main.async { onCancel() }
    }
    
    private func dismissKeyboard() {
        isFocused = false
    }
}

private struct TransformableText: View {
    let text: String
    let fontName: String
    let fontSize: Double
    let color: Color
    @State var transform: Transform2D
    let isSelected: Bool
    var onChange: (Transform2D) -> Void
    var onTap: () -> Void
    var onDoubleTap: (() -> Void)?
    var onTextChange: (String) -> Void

    var body: some View {
        // IMPORTANT: keep the hit-test area tight to the text chip.
        // A full-screen transparent overlay here will block selecting images.
        Text(text)
            .font(.custom(fontName, size: CGFloat(fontSize)))
            .foregroundStyle(color)
            .padding(8)
            .background(Color.black.opacity(0.3))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: isSelected ? 2 : 0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
            )
            .contentShape(Rectangle())
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
        .modifier(TransformModifier(transform: $transform, isEnabled: true))
        .simultaneousGesture(
            // Long press to delete
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    // Long press to delete
                    onDoubleTap?()
                }
        )
        .simultaneousGesture(
            // Single tap to edit
            TapGesture(count: 1)
                .onEnded {
                    // Single tap to edit
                    onTap()
                }
        )
        .scaleEffect(transform.scale)
        .rotationEffect(.radians(transform.rotation))
        .offset(x: transform.x, y: transform.y)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: transform.scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: transform.rotation)
        .onChange(of: transform) { onChange($0) }
    }
}

private struct TransformModifier: ViewModifier {
    @Binding var transform: Transform2D
    @State private var lastOffset = CGSize.zero
    @State private var lastScale: Double = 1.0
    @State private var lastRotation: Double = 0.0
    @State private var hasInitialized = false
    @State private var isGesturing = false
    var isEnabled: Bool = true // Enable/disable gestures
    var onGestureActivity: (() -> Void)? = nil
    var onGestureEnd: ((Transform2D, Transform2D) -> Void)?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .gesture(dragGesture.simultaneously(with: magnification).simultaneously(with: rotation))
                .onAppear {
                    initializeState()
                }
                .onChange(of: transform.x) { _ in
                    if !hasInitialized {
                        initializeState()
                    }
                }
                .onChange(of: transform) { newValue in
                    // Keep internal gesture baselines synced when transform changes programmatically
                    // (e.g. undo/redo). Rotation is especially sensitive to stale baselines.
                    guard hasInitialized, !isGesturing else { return }
                    lastOffset = CGSize(width: newValue.x, height: newValue.y)
                    lastScale = newValue.scale
                    lastRotation = newValue.rotation
                }
        } else {
            content
        }
    }
    
    private func initializeState() {
        if !hasInitialized {
            lastOffset = CGSize(width: transform.x, height: transform.y)
            lastScale = transform.scale
            lastRotation = transform.rotation
            hasInitialized = true
            print("🔄 TransformModifier initialized: offset=\(lastOffset), scale=\(lastScale), rotation=\(lastRotation)")
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isGesturing = true
                // Only treat as "manipulation" after a small movement threshold.
                // This avoids blocking double-tap delete due to normal tap jitter.
                if hypot(value.translation.width, value.translation.height) > 6 {
                    onGestureActivity?()
                }
                // Rotate the translation vector to account for the current rotation
                // This ensures drag direction matches the visual orientation of the rotated view
                // We rotate by -rotation to convert from screen space to the view's local coordinate space
                let rotation = -transform.rotation
                let cosRotation = cos(rotation)
                let sinRotation = sin(rotation)
                
                // Rotate the translation vector from screen space to view's local space
                // Rotation matrix for angle -θ: [cos(θ)  sin(θ)]  [x]
                //                                [-sin(θ) cos(θ)]  [y]
                let rotatedX = value.translation.width * cosRotation + value.translation.height * sinRotation
                let rotatedY = -value.translation.width * sinRotation + value.translation.height * cosRotation
                
                // Apply the rotated translation
                transform.x = rotatedX + lastOffset.width
                transform.y = rotatedY + lastOffset.height
            }
            .onEnded { value in
                let previous = Transform2D(x: lastOffset.width, y: lastOffset.height, scale: lastScale, rotation: lastRotation)
                let new = transform
                onGestureEnd?(previous, new)
                lastOffset = CGSize(width: transform.x, height: transform.y)
                isGesturing = false
            }
    }

    private var magnification: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0)
            .onChanged { scale in
                isGesturing = true
                // Only treat as manipulation once user actually pinches.
                if abs(scale - 1.0) > 0.01 {
                    onGestureActivity?()
                }
                // Direct assignment for immediate response
                let newScale = lastScale * scale
                transform.scale = max(0.1, min(15.0, newScale))  // Allow 10% to 1500% (15x zoom)
            }
            .onEnded { scale in
                let previous = Transform2D(x: lastOffset.width, y: lastOffset.height, scale: lastScale, rotation: lastRotation)
                let new = transform
                onGestureEnd?(previous, new)
                lastScale = transform.scale
                isGesturing = false
                // Delightful haptic feedback on pinch end
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred(intensity: 0.5)
            }
    }

    private var rotation: some Gesture {
        RotationGesture()
            .onChanged { angle in
                isGesturing = true
                // Only treat as manipulation once user actually rotates.
                if abs(angle.radians) > 0.02 {
                    onGestureActivity?()
                }
                transform.rotation = lastRotation + angle.radians
            }
            .onEnded { angle in
                let previous = Transform2D(x: lastOffset.width, y: lastOffset.height, scale: lastScale, rotation: lastRotation)
                let new = transform
                onGestureEnd?(previous, new)
                lastRotation = transform.rotation
                isGesturing = false
                // Delightful haptic feedback on rotation end
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred(intensity: 0.5)
            }
    }
}

/// Corkboard texture background - UIKit-based for reliable rendering
private struct CorkboardBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> CorkImageView {
        let view = CorkImageView()
        return view
    }
    
    func updateUIView(_ uiView: CorkImageView, context: Context) {
        // No updates needed
    }
}

private class CorkImageView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = UIColor(red: 0.82, green: 0.68, blue: 0.50, alpha: 1.0)
        clipsToBounds = false // Allow overflow beyond bounds
        
        // Try to load and display cork image
        if let corkImage = loadCorkImage(),
           let rotatedImage = rotateImage(corkImage, degrees: 90) {
            let imageView = UIImageView(image: rotatedImage)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = false // Allow overflow
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            
            // Extend the image beyond the view bounds to fill curved edges (more aggressive)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: -50),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 50),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -50),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 50)
            ])
        }
    }
    
    private func rotateImage(_ image: UIImage, degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        var newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians)).size
        newSize.width = floor(newSize.width)
        newSize.height = floor(newSize.height)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                             width: image.size.width, height: image.size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }
    
    private func loadCorkImage() -> UIImage? {
        // Try multiple possible filenames
        let possibleNames = ["cork", "corkboard", "cork-texture", "cork_texture"]
        
        for name in possibleNames {
            // Try loading from Resources folder
            if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        
        // Try loading from asset catalog
        if let image = UIImage(named: "cork") {
            return image
        }
        
        return nil
    }
}

/// Psych background - UIKit-based for reliable rendering
private struct PsychBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> PsychImageView {
        let view = PsychImageView()
        return view
    }
    
    func updateUIView(_ uiView: PsychImageView, context: Context) {
        // No updates needed
    }
}

private class PsychImageView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        print("🎨 PsychImageView setup() called")
        clipsToBounds = false // Allow overflow beyond bounds
        
        // Try to load and display psych image
        if let psychImage = loadPsychImage() {
            print("🎨 Setting up psych image view with image, size: \(psychImage.size)")
            backgroundColor = UIColor.clear
            let imageView = UIImageView(image: psychImage)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = false // Allow overflow
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            
            // Extend the image beyond the view bounds to fill curved edges
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: -50),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 50),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -50),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 50)
            ])
            print("🎨 Psych image view setup complete")
        } else {
            // Fallback: Use a distinctive purple background so user knows it's psych background
            // This indicates the image file isn't being loaded from the bundle
            print("⚠️ Psych image not loaded - showing purple fallback background")
            print("   NOTE: psych.jpg needs to be added to Xcode project to be included in app bundle")
            backgroundColor = UIColor(red: 0.3, green: 0.1, blue: 0.5, alpha: 1.0) // Purple fallback
        }
    }
    
    private func loadPsychImage() -> UIImage? {
        // Try multiple possible names and methods (matching cork approach)
        let possibleNames = ["psych", "psych.jpg", "psych.png"]
        
        // First try UIImage(named:) - this is most reliable if file is in bundle
        for name in possibleNames {
            if let image = UIImage(named: name) {
                print("🎨 Found psych image using UIImage(named: \"\(name)\"), size: \(image.size)")
                return image
            }
        }
        
        // Then try loading from Resources folder path
        if let path = Bundle.main.path(forResource: "psych", ofType: "jpg") {
            print("🎨 Found psych.jpg at path: \(path)")
            if let image = UIImage(contentsOfFile: path) {
                print("🎨 Successfully loaded psych.jpg from path, size: \(image.size)")
                return image
            } else {
                print("⚠️ Failed to create UIImage from psych.jpg at path: \(path)")
            }
        } else {
            print("⚠️ psych.jpg not found in bundle using path(forResource:ofType:)")
        }
        
        // Try PNG version
        if let path = Bundle.main.path(forResource: "psych", ofType: "png") {
            print("🎨 Found psych.png at path: \(path)")
            if let image = UIImage(contentsOfFile: path) {
                print("🎨 Successfully loaded psych.png from path, size: \(image.size)")
                return image
            }
        }
        
        // Try finding in main bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let psychJPGPath = (resourcePath as NSString).appendingPathComponent("psych.jpg")
            if FileManager.default.fileExists(atPath: psychJPGPath) {
                if let image = UIImage(contentsOfFile: psychJPGPath) {
                    print("🎨 Found and loaded psych.jpg from resourcePath, size: \(image.size)")
                    return image
                }
            }
        }
        
        print("❌ Failed to load psych image from any source")
        print("   Make sure psych.jpg is added to Xcode project and included in app bundle")
        return nil
    }
}

/// Reusable image background - UIKit-based for reliable rendering
private struct ImageBackground: UIViewRepresentable {
    let imageName: String
    let imageType: String // "jpg" or "png"
    
    func makeUIView(context: Context) -> BackgroundImageView {
        let view = BackgroundImageView(imageName: imageName, imageType: imageType)
        return view
    }
    
    func updateUIView(_ uiView: BackgroundImageView, context: Context) {
        // No updates needed
    }
}

private class BackgroundImageView: UIView {
    let imageName: String
    let imageType: String
    
    init(imageName: String, imageType: String) {
        self.imageName = imageName
        self.imageType = imageType
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        self.imageName = ""
        self.imageType = "jpg"
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        print("🎨 BackgroundImageView setup() called for: \(imageName).\(imageType)")
        clipsToBounds = false // Allow overflow beyond bounds
        
        // Try to load and display image
        if let bgImage = loadBackgroundImage() {
            print("🎨 Setting up background image view with image, size: \(bgImage.size)")
            backgroundColor = UIColor.clear
            let imageView = UIImageView(image: bgImage)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = false // Allow overflow
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            
            // Extend the image beyond the view bounds to fill curved edges
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: topAnchor, constant: -50),
                imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 50),
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -50),
                imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 50)
            ])
            print("🎨 Background image view setup complete for: \(imageName)")
        } else {
            // Fallback to black background
            print("⚠️ Background image not loaded - showing black fallback for: \(imageName).\(imageType)")
            backgroundColor = UIColor.black
        }
    }
    
    private func loadBackgroundImage() -> UIImage? {
        // Try UIImage(named:) first - most reliable if file is in bundle
        if let image = UIImage(named: imageName) {
            print("🎨 Found \(imageName) image using UIImage(named:), size: \(image.size)")
            return image
        }
        
        // Try with extension in name
        let nameWithExt = "\(imageName).\(imageType)"
        if let image = UIImage(named: nameWithExt) {
            print("🎨 Found \(nameWithExt) image using UIImage(named:), size: \(image.size)")
            return image
        }
        
        // Try loading from Resources folder path
        if let path = Bundle.main.path(forResource: imageName, ofType: imageType) {
            print("🎨 Found \(nameWithExt) at path: \(path)")
            if let image = UIImage(contentsOfFile: path) {
                print("🎨 Successfully loaded \(nameWithExt) from path, size: \(image.size)")
                return image
            } else {
                print("⚠️ Failed to create UIImage from \(nameWithExt) at path: \(path)")
            }
        } else {
            print("⚠️ \(nameWithExt) not found in bundle using path(forResource:ofType:)")
        }
        
        // Try finding in main bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let imagePath = (resourcePath as NSString).appendingPathComponent(nameWithExt)
            if FileManager.default.fileExists(atPath: imagePath) {
                if let image = UIImage(contentsOfFile: imagePath) {
                    print("🎨 Found and loaded \(nameWithExt) from resourcePath, size: \(image.size)")
                    return image
                }
            }
        }
        
        print("❌ Failed to load background image from any source: \(nameWithExt)")
        return nil
    }
}

private extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

/// Video background - UIKit-based with AVPlayerLayer for efficient playback
private struct VideoBackground: UIViewRepresentable {
    let videoName: String
    
    func makeUIView(context: Context) -> VideoBackgroundView {
        let view = VideoBackgroundView(videoName: videoName)
        return view
    }
    
    func updateUIView(_ uiView: VideoBackgroundView, context: Context) {
        // Update if video name changes
        if uiView.videoName != videoName {
            uiView.loadVideo(videoName: videoName)
        }
    }
}

private class VideoBackgroundView: UIView {
    var videoName: String
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    
    init(videoName: String) {
        self.videoName = videoName
        super.init(frame: .zero)
        setup()
        loadVideo(videoName: videoName)
    }
    
    required init?(coder: NSCoder) {
        self.videoName = ""
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = UIColor.black // Fallback background
        clipsToBounds = false // Allow overflow beyond bounds
    }
    
    func loadVideo(videoName: String) {
        self.videoName = videoName
        
        // Remove existing player layer
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper?.disableLooping()
        looper = nil
        player?.pause()
        player = nil
        
        guard let videoURL = loadVideoURL(videoName: videoName) else {
            print("⚠️ Video background not loaded - showing black fallback for: \(videoName)")
            backgroundColor = UIColor.black // Show black fallback
            return
        }
        
        // Create player item
        let playerItem = AVPlayerItem(url: videoURL)
        
        // Create queue player for looping
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        
        // Create looper for seamless looping
        looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        
        player = queuePlayer
        
        // Create player layer
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill // Fill entire view, cropping if needed
        layer.player?.play()
        
        self.playerLayer = layer
        self.layer.addSublayer(layer)
        
        // Frame will be set in layoutSubviews() to handle bounds correctly
        setNeedsLayout()
        
        print("🎬 Video background loaded: \(videoName), URL: \(videoURL)")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update player layer frame to fill view + extend beyond bounds (similar to image backgrounds)
        if let playerLayer = playerLayer {
            playerLayer.frame = CGRect(x: -50, y: -50, width: bounds.width + 100, height: bounds.height + 100)
        }
    }
    
    private func loadVideoURL(videoName: String) -> URL? {
        // Try loading from Resources folder
        if let path = Bundle.main.path(forResource: videoName, ofType: "mp4") {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                print("🎬 Found video at path: \(path)")
                return url
            }
        }
        
        // Try loading from bundle resources
        if let resourcePath = Bundle.main.resourcePath {
            let videoPath = (resourcePath as NSString).appendingPathComponent("\(videoName).mp4")
            if FileManager.default.fileExists(atPath: videoPath) {
                let url = URL(fileURLWithPath: videoPath)
                print("🎬 Found video at resourcePath: \(videoPath)")
                return url
            }
        }
        
        // Try loading from main bundle
        if let url = Bundle.main.url(forResource: videoName, withExtension: "mp4") {
            print("🎬 Found video using Bundle.main.url: \(url)")
            return url
        }
        
        print("❌ Failed to find video file: \(videoName).mp4")
        return nil
    }
    
    deinit {
        // Clean up player resources
        player?.pause()
        looper?.disableLooping()
        playerLayer?.removeFromSuperlayer()
        player = nil
        looper = nil
        playerLayer = nil
    }
}

/// Cork grain overlay with configurable density and size
private struct CorkGrainOverlay: View {
    let dotCount: Int
    let sizeRange: ClosedRange<CGFloat>
    let opacityRange: ClosedRange<Double>
    var isDark: Bool = false
    
    var body: some View {
        Canvas { context, size in
            // Create random grain pattern for cork texture
            for _ in 0..<dotCount {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let opacity = Double.random(in: opacityRange)
                let radius = CGFloat.random(in: sizeRange)
                
                // Vary shapes for more realistic texture
                let useEllipse = Bool.random()
                let width = useEllipse ? radius * CGFloat.random(in: 0.6...1.4) : radius
                let height = useEllipse ? radius * CGFloat.random(in: 0.6...1.4) : radius
                
                let color: Color = isDark ? .black : (Bool.random() ? .black : .brown)
                
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: width, height: height)),
                    with: .color(color.opacity(opacity))
                )
            }
        }
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? { connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow } }
}

extension Color {
    init(hex: String) {
        let r, g, b: Double
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        if hexString.count == 6, let value = UInt64(hexString, radix: 16) {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else { r = 0; g = 0; b = 0 }
        self = Color(red: r, green: g, blue: b)
    }
    
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

