import SwiftUI

@main
struct SchieraApp: App {
    @StateObject private var model = AppModel.live()

    var body: some Scene {
        MenuBarExtra("Schiera", systemImage: "rectangle.split.3x1") {
            MenuBarContentView(model: model)
        }
        Settings {
            SettingsView(model: model.settingsViewModel)
        }
    }
}
