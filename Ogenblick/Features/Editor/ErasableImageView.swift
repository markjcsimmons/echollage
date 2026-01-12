import SwiftUI
import UIKit

struct ErasableImageView: View {
    let image: UIImage
    @Binding var erasedImageFileName: String?
    let brushSize: CGFloat
    let projectId: UUID
    let store: ProjectStore
    let isEraseMode: Bool
    let onImageErased: (String) -> Void
    
    @State private var displayedImage: UIImage?
    
    var body: some View {
        ZStack {
            if let displayed = displayedImage {
                Image(uiImage: displayed)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .onAppear {
            loadDisplayedImage()
        }
        .onChange(of: erasedImageFileName) { _ in
            loadDisplayedImage()
        }
        .onChange(of: image) { _ in
            loadDisplayedImage()
        }
        .allowsHitTesting(isEraseMode)
    }
    
    private func loadDisplayedImage() {
        if let fileName = erasedImageFileName {
            let url = store.urlForProjectAsset(projectId: projectId, fileName: fileName)
            if let erasedImage = UIImage(contentsOfFile: url.path) {
                displayedImage = erasedImage
                return
            }
        }
        displayedImage = image
    }
}
