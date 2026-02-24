import SwiftUI
import PhotosUI
import AVFoundation

struct PhotoPicker: UIViewControllerRepresentable {
    var selectionLimit: Int = 0 // 0 = unlimited
    var onImagesPicked: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImagesPicked: onImagesPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onImagesPicked: ([UIImage]) -> Void
        init(onImagesPicked: @escaping ([UIImage]) -> Void) { self.onImagesPicked = onImagesPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            // Always call back (even when user cancels) so the caller can
            // clear its `.sheet(isPresented:)` binding reliably.
            
            // Collecting results via callbacks and mutating a shared array can race.
            // Use a task group to load images concurrently and aggregate safely.
            Task {
                let images: [UIImage] = await withTaskGroup(of: UIImage?.self) { group in
                    for result in results {
                        group.addTask {
                            await Self.loadUIImage(from: result.itemProvider)
                        }
                    }
                    
                    var loaded: [UIImage] = []
                    for await img in group {
                        if let img { loaded.append(img) }
                    }
                    return loaded
                }
                
                await MainActor.run {
                    self.onImagesPicked(images)
                }
            }
        }
        
        private static func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
            
            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            }
        }
    }
}




