import SwiftUI

struct CollageViewerView: View {
    let project: Project
    let assetURLProvider: (String) -> URL?
    @Environment(\.dismiss) private var dismiss
    
    @State private var renderedImage: UIImage? = nil
    @State private var isRendering: Bool = true
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Rendered collage
            if let image = renderedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else if isRendering {
                ProgressView()
                    .tint(.white)
            } else {
                Text("Failed to render collage")
                    .foregroundColor(.white)
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .task {
            // Render off-main to avoid UI freezes.
            isRendering = true
            let size = UIScreen.main.bounds.size
            let scale = UIScreen.main.scale
            let image = await CollageRenderer.renderAsync(
                project: project,
                assetURLProvider: assetURLProvider,
                canvasSize: size,
                screenScale: scale
            )
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.renderedImage = image
                    self.isRendering = false
                }
            }
        }
    }
}
