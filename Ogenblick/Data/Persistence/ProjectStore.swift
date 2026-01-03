import Foundation
import SwiftUI

final class ProjectStore: ObservableObject {
    @Published var projects: [Project] = [] {
        didSet { save() }
    }

    private let rootFolderName = "Projects"
    private let indexFileName = "projects.json"

    init() {
        load()
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

    private func load() {
        do {
            let url = indexURL()
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([Project].self, from: data)
            self.projects = decoded
        } catch {
            self.projects = []
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
}





