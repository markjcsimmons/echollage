import Foundation
import SwiftUI

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = [] {
        didSet { 
            // Save asynchronously to avoid blocking main thread.
            // Avoid writing immediately while we're loading from disk.
            guard !isLoadingFromDisk else { return }
            saveAsync()
        }
    }

    private let rootFolderName = "Projects"
    private let indexFileName = "projects.json"
    private let saveQueue = DispatchQueue(label: "com.ogenblick.projectstore.save", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?
    private let loadQueue = DispatchQueue(label: "com.ogenblick.projectstore.load", qos: .utility)
    private var isLoadingFromDisk: Bool = false

    init() {
        loadAsync()
    }

    // MARK: - Public API

    func createNewProject(name: String = "Untitled Moment") -> Project {
        var project = Project(name: name)
        project.createdAt = Date()
        project.updatedAt = Date()
        projects.insert(project, at: 0)
        return project
    }

    func update(_ project: Project) {
        if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.updatedAt = Date()
            projects[idx] = updated
        }
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        // Optionally delete its folder
        let folder = folderURL(for: project.id)
        try? FileManager.default.removeItem(at: folder)
    }

    func urlForProjectAsset(projectId: UUID, fileName: String) -> URL {
        let folder = folderURL(for: projectId)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    // MARK: - Disk IO

    private func documentsRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ogenblick")
    }

    private func folderURL(for id: UUID) -> URL {
        documentsRoot().appendingPathComponent(rootFolderName).appendingPathComponent(id.uuidString)
    }

    private func indexURL() -> URL {
        documentsRoot().appendingPathComponent(indexFileName)
    }

    private func loadAsync() {
        isLoadingFromDisk = true
        let url = indexURL()
        
        loadQueue.async { [weak self] in
            guard let self else { return }
            
            let decoded: [Project]
            do {
                if FileManager.default.fileExists(atPath: url.path) == false {
                    decoded = []
                } else {
                    let data = try Data(contentsOf: url)
                    decoded = try JSONDecoder().decode([Project].self, from: data)
                }
            } catch {
                decoded = []
            }
            
            DispatchQueue.main.async {
                self.projects = decoded
                self.isLoadingFromDisk = false
            }
        }
    }

    private func save() {
        do {
            let dir = documentsRoot()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(projects)
            try data.write(to: indexURL(), options: .atomic)
        } catch {
            print("Failed to save projects: \(error)")
        }
    }
    
    // Async save with debouncing to avoid multiple saves in quick succession
    private func saveAsync() {
        // Cancel any pending save
        saveWorkItem?.cancel()
        
        // Capture current projects array to avoid race conditions
        let projectsToSave = self.projects
        
        // Create new save work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Save the captured snapshot
            do {
                let dir = self.documentsRoot()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(projectsToSave)
                try data.write(to: self.indexURL(), options: .atomic)
            } catch {
                print("Failed to save projects: \(error)")
            }
        }
        
        saveWorkItem = workItem
        
        // Debounce: wait 0.1 seconds before saving, cancel if another update comes
        saveQueue.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }
}





