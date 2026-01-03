import SwiftUI

struct LayerPanel: View {
    @Binding var project: Project
    var onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("Image Layers") {
                    ForEach(Array(project.imageLayers.enumerated()), id: \.element.id) { index, layer in
                        HStack {
                            Text("Image \(index + 1)")
                            Spacer()
                            Button {
                                bringToFront(imageLayer: layer.id)
                            } label: {
                                Image(systemName: "arrow.up.to.line")
                            }
                            Button {
                                sendToBack(imageLayer: layer.id)
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                            }
                            Button(role: .destructive) {
                                deleteImageLayer(layer.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
                
                Section("Text Layers") {
                    ForEach(Array(project.textLayers.enumerated()), id: \.element.id) { index, layer in
                        HStack {
                            Text(layer.text)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                bringToFront(textLayer: layer.id)
                            } label: {
                                Image(systemName: "arrow.up.to.line")
                            }
                            Button {
                                sendToBack(textLayer: layer.id)
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                            }
                            Button(role: .destructive) {
                                deleteTextLayer(layer.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func bringToFront(imageLayer id: UUID) {
        if let idx = project.imageLayers.firstIndex(where: { $0.id == id }) {
            let maxZ = project.imageLayers.map(\.zIndex).max() ?? 0
            project.imageLayers[idx].zIndex = maxZ + 1
            onUpdate()
        }
    }
    
    private func sendToBack(imageLayer id: UUID) {
        if let idx = project.imageLayers.firstIndex(where: { $0.id == id }) {
            let minZ = project.imageLayers.map(\.zIndex).min() ?? 0
            project.imageLayers[idx].zIndex = minZ - 1
            onUpdate()
        }
    }
    
    private func bringToFront(textLayer id: UUID) {
        if let idx = project.textLayers.firstIndex(where: { $0.id == id }) {
            let maxZ = project.textLayers.map(\.zIndex).max() ?? 0
            project.textLayers[idx].zIndex = maxZ + 1
            onUpdate()
        }
    }
    
    private func sendToBack(textLayer id: UUID) {
        if let idx = project.textLayers.firstIndex(where: { $0.id == id }) {
            let minZ = project.textLayers.map(\.zIndex).min() ?? 0
            project.textLayers[idx].zIndex = minZ - 1
            onUpdate()
        }
    }
    
    private func deleteImageLayer(_ id: UUID) {
        project.imageLayers.removeAll { $0.id == id }
        onUpdate()
    }
    
    private func deleteTextLayer(_ id: UUID) {
        project.textLayers.removeAll { $0.id == id }
        onUpdate()
    }
}




