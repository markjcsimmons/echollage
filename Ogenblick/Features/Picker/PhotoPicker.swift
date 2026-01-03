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
            
            guard !results.isEmpty else { return }
            var images: [UIImage] = []
            let group = DispatchGroup()
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                        if let image = object as? UIImage { images.append(image) }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                self.onImagesPicked(images)
            }
        }
    }
}




