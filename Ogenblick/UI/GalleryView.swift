import SwiftUI

struct GalleryView: View {
    @EnvironmentObject private var store: ProjectStore
    var onSelectProject: ((Project) -> Void)? = nil

    @State private var createPresented: Bool = false
    @State private var editingProject: Project?
    @State private var viewingProject: Project?

    var body: some View {
        List {
            Section {
                Button {
                    let project = store.createNewProject()
                    editingProject = project
                } label: {
                    Label("New Moment", systemImage: "plus.circle.fill")
                }
            }

            Section {
                ForEach(store.projects) { project in
                    HStack {
                        Button {
                            if let onSelect = onSelectProject {
                                onSelect(project)
                            } else {
                                viewingProject = project
                            }
                        } label: {
                            HStack {
                                // Thumbnail with play button overlay
                                ZStack {
                                    if project.hasContent {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.secondary)
                                    } else {
                                Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 40))
                                    .foregroundStyle(.secondary)
                                    }
                                    
                                    // Play icon if has audio
                                    if project.audioFileName != nil {
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(.white)
                                            .background(Circle().fill(.black.opacity(0.6)).frame(width: 24, height: 24))
                                            .offset(x: 10, y: 10)
                                    }
                                }
                                .frame(width: 60, height: 60)
                                
                                VStack(alignment: .leading) {
                                    Text(project.name)
                                        .font(.headline)
                                    HStack {
                                    Text(project.updatedAt, style: .date)
                                        .foregroundStyle(.secondary)
                                        if project.audioFileName != nil {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.caption)
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }
                        
                        if onSelectProject == nil {
                            Button {
                                editingProject = project
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(project) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Echollage")
        .sheet(item: $editingProject) { project in
            CollageEditorContainer(projectId: project.id)
        }
        .fullScreenCover(item: $viewingProject) { project in
            CollageViewerView(project: project, assetURLProvider: { fileName in
                store.urlForProjectAsset(projectId: project.id, fileName: fileName)
            })
        }
    }
}

private struct CollageEditorContainer: View {
    @EnvironmentObject private var store: ProjectStore
    let projectId: UUID

    var body: some View {
        if let index = store.projects.firstIndex(where: { $0.id == projectId }) {
            CollageEditorView(project: $store.projects[index])
        } else {
            Text("Project not found")
        }
    }
}

struct GalleryView_Previews: PreviewProvider {
    static var previews: some View {
        GalleryView().environmentObject(ProjectStore())
    }
}


