import SwiftUI

@main
struct SchieraApp: App {
    // Reading a @StateObject's value in App.init would create a transient
    // AppModel whose shortcut registrations die with it; AppModel.live()
    // starts the model itself so the SwiftUI-owned instance registers them.
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
