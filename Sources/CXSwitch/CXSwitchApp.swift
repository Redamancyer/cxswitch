import SwiftUI

@main
struct CXSwitchApp: App {
    @StateObject private var store = AccountStore()

    var body: some Scene {
        MenuBarExtra {
            AccountMenuView()
                .environmentObject(store)
        } label: {
            Label(store.activeAccount?.displayName ?? "CXSwitch", systemImage: "person.2.circle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
