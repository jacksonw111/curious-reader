import SwiftUI

@main
struct CuriousReaderApp: App {
    @StateObject private var workspaceModel = ReaderWorkspaceModel()

    var body: some Scene {
        WindowGroup("Curious Reader") {
            ReaderWorkspaceView(model: workspaceModel)
        }
        .windowStyle(.automatic)

        Settings {
            ReaderSettingsSheet(model: workspaceModel)
        }
    }
}
