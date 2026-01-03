import SwiftUI

/// Helper view for editing images with mask when erase tool is active
struct MaskedImageEditor: View {
    let image: UIImage
    let baseSize: CGSize
    let maskFileName: String?
    @Binding var layerBinding: ImageLayer
    let transform: Transform2D
    let zIndex: Int
    let brushSize: CGFloat
    let projectId: UUID
    let store: ProjectStore
    let refreshTrigger: UUID
    let onSaved: (String) -> Void
    
    @State private var maskImage: UIImage?
    
    var body: some View {
        ZStack {
            // Base image with mask applied (non-interactive when erasing)
            Group {
                if let mask = maskImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: baseSize.width, height: baseSize.height)
                        .mask(
                            Image(uiImage: mask)
                                .resizable()
                                .scaledToFit()
                                .frame(width: baseSize.width, height: baseSize.height)
                        )
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: baseSize.width, height: baseSize.height)
                }
            }
            .allowsHitTesting(false) // Prevent image from receiving touches
            
            // Mask editor overlay (interactive) - this captures all touches
            MaskEditorView(
                baseImageSize: image.size,
                maskFileName: $layerBinding.maskFileName,
                brushSize: brushSize,
                projectId: projectId,
                store: store,
                onSaved: onSaved
            )
            .frame(width: baseSize.width, height: baseSize.height)
            .contentShape(Rectangle()) // Ensure entire frame is tappable
        }
        .scaleEffect(transform.scale)
        .rotationEffect(.radians(transform.rotation))
        .offset(x: transform.x, y: transform.y)
        .zIndex(Double(zIndex) + 0.5)
        .id("mask-editor-\(layerBinding.id)-\(maskFileName ?? "none")-\(refreshTrigger)")
        .onAppear {
            loadMask()
        }
        .onChange(of: maskFileName) { _ in
            loadMask()
        }
    }
    
    private func loadMask() {
        if let name = maskFileName {
            let url = store.urlForProjectAsset(projectId: projectId, fileName: name)
            maskImage = UIImage(contentsOfFile: url.path)
            print("🎨 Loaded mask: \(name), size: \(maskImage?.size ?? .zero)")
        } else {
            maskImage = nil
            print("🎨 No mask to load")
        }
    }
}

/// Helper view for displaying images with optional mask
struct MaskedImageDisplay: View {
    let image: UIImage
    let baseSize: CGSize
    let maskFileName: String?
    @Binding var transform: Transform2D
    let zIndex: Int
    let projectId: UUID
    let store: ProjectStore
    let onDoubleTap: () -> Void
    
    @State private var maskImage: UIImage?
    
    var body: some View {
        Group {
            if let mask = maskImage {
                TransformableImage(
                    uiImage: image,
                    baseSize: baseSize,
                    transform: $transform,
                    overlay: { EmptyView() }
                )
                .mask(
                    Image(uiImage: mask)
                        .resizable()
                        .scaledToFit()
                        .frame(width: baseSize.width, height: baseSize.height)
                )
            } else {
                TransformableImage(
                    uiImage: image,
                    baseSize: baseSize,
                    transform: $transform,
                    overlay: { EmptyView() }
                )
            }
        }
        .onAppear {
            loadMask()
        }
        .onChange(of: maskFileName) { _ in
            loadMask()
        }
        .onTapGesture(count: 2) {
            onDoubleTap()
        }
        .zIndex(Double(zIndex))
    }
    
    private func loadMask() {
        if let name = maskFileName {
            let url = store.urlForProjectAsset(projectId: projectId, fileName: name)
            maskImage = UIImage(contentsOfFile: url.path)
            print("🎨 Loaded mask: \(name), size: \(maskImage?.size ?? .zero)")
        } else {
            maskImage = nil
            print("🎨 No mask to load")
        }
    }
}

