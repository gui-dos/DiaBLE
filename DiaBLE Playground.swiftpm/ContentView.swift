import SwiftUI


struct ContentView: View {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        TabView(selection: $settings.selectedTab) {

            // TODO: iOS 18 new Tabs

            Monitor()
                .tabItem {
                    Label("Monitor", systemImage: "gauge")
                }
                .tag(TabTitle.monitor)

            OnlineView()
                .tabItem {
                    Label("Online", systemImage: "globe")
                }
                .tag(TabTitle.online)

            ConsoleTab()
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }
                .tag(TabTitle.console)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(TabTitle.settings)

            DataView()
                .tabItem {
                    Label("Data", systemImage: "tray.full.fill")
                }
                .tag(TabTitle.data)

            Plan()
                .tabItem {
                    Label("Plan", systemImage: "map")
                }
                .tag(TabTitle.plan)

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
