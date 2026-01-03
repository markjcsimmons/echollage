import SwiftUI

struct CollageViewerView: View {
    let project: Project
    let assetURLProvider: (String) -> URL?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            
            // Rendered collage
            if let image = CollageRenderer.render(project: project, assetURLProvider: assetURLProvider) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
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
    }
}
