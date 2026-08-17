import SwiftUI

@main
struct SchieraApp: App {
    @StateObject private var model = AppModel.live()

    init() {
        // Register the shortcut during app construction, before the menu is opened.
        model.start()
    }

    var body: some Scene {
        MenuBarExtra("Schiera", systemImage: "rectangle.split.3x1") {
            MenuBarContentView(model: model)
        }
        Settings {
            SettingsView(model: model.settingsViewModel)
        }
    }
}
