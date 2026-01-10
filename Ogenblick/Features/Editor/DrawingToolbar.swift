import SwiftUI
import PencilKit

enum DrawingTool: String, CaseIterable {
    case pen = "Pen"
    case brush = "Brush"
    case erase = "Erase"
    case tear = "Tear"
    
    var icon: String {
        switch self {
        case .pen: return "pencil"
        case .brush: return "paintbrush.fill"
        case .erase: return "eraser.fill"
        case .tear: return "scissors"
        }
    }
}

// Ultra-simple drawing toolbar - just colors + done
struct DrawingToolbar: View {
    @Binding var isDrawing: Bool
    @Binding var selectedTool: DrawingTool
    @Binding var strokeWidth: CGFloat
    @Binding var strokeColor: Color
    @Binding var drawingData: Data
    let onUndoDrawing: () -> Void // Undo drawing strokes only
    let onClose: () -> Void
    
    // Simple 6-color palette
    private let colors: [Color] = [
        .white, .black, .red, .yellow, .blue, .purple
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // 8x1 grid toolbar (matches main toolbar style exactly)
            HStack(spacing: 6) {
                // 1. Undo (drawing strokes only)
                ToolbarButton(icon: "arrow.uturn.backward", isAccent: false) {
                    onUndoDrawing()
                    SoundEffectPlayer.shared.playClick()
                }
                
                // 2-7. Color buttons (6 colors)
                ForEach(colors, id: \.self) { color in
                    ColorButton(color: color, isSelected: strokeColor == color) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            strokeColor = color
                        }
                        SoundEffectPlayer.shared.playClick()
                    }
                }
                
                // 8. Done
                ToolbarButton(icon: "checkmark", isAccent: true) {
                    onClose()
                    SoundEffectPlayer.shared.playClick()
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
            )
            .padding(.bottom, 30)
            .padding(.horizontal, 16)
        }
    }
}

// Toolbar button matching main toolbar style
private struct ToolbarButton: View {
    let icon: String
    let isAccent: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Bottom shadow layer (3D depth)
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .offset(y: isPressed ? 1 : 2)
                
                // Main button
                RoundedRectangle(cornerRadius: 10)
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
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
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
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: isPressed ? 1 : 2, y: isPressed ? 1 : 2)
                    .offset(y: isPressed ? 1 : 0)
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .offset(y: isPressed ? 1 : 0)
            }
        }
        .buttonStyle(DrawingToolbarButtonStyle(isPressed: $isPressed))
    }
}

// Color button for drawing toolbar
private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Bottom shadow layer
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .offset(y: isPressed ? 1 : 2)
                
                // Main button background
                RoundedRectangle(cornerRadius: 10)
                    .fill(color)
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                    )
                    .shadow(color: isSelected ? color.opacity(0.6) : Color.black.opacity(0.25), radius: isSelected ? 4 : (isPressed ? 1 : 2), y: isPressed ? 1 : 2)
                    .offset(y: isPressed ? 1 : 0)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
            }
        }
        .buttonStyle(DrawingToolbarButtonStyle(isPressed: $isPressed))
    }
}

// Button style for press effect
private struct DrawingToolbarButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    isPressed = newValue
                }
            }
    }
}

