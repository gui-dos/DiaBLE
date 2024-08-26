import SwiftUI


struct ContentView: View {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        TabView(selection: $settings.selectedTab) {

            Tab("Monitor", systemImage: "gauge", value: .monitor) {
                Monitor()
            }

            Tab("Online", systemImage: "globe", value: .online) {
                OnlineView()
            }

            Tab("Console", systemImage: "terminal", value: .console) {
                ConsoleTab()
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }

            Tab("Data", systemImage: "tray.full.fill", value: .data) {
                DataView()
            }

            Tab("Plan", systemImage: "map", value: .plan) {
                Plan()
            }

        }
        .toolbarRole(.navigationStack)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .online))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .data))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .console))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .settings))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
