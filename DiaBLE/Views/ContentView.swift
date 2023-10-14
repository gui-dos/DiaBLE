import SwiftUI


struct ContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        TabView(selection: $settings.selectedTab) {
            Monitor()
                .tabItem {
                    Label("Monitor", systemImage: "gauge")
                }.tag(Tab.monitor)

            OnlineView()
                .tabItem {
                    Label("Online", systemImage: "globe")
                }.tag(Tab.online)

            ConsoleTab()
                .tabItem {
                    Label("Console", systemImage: "terminal")
                }.tag(Tab.console)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }.tag(Tab.settings)

            DataView()
                .tabItem {
                    Label("Data", systemImage: "tray.full.fill")
                }.tag(Tab.data)

            // Plan()
            //     .tabItem {
            //         Image(systemName: "map")
            //         Text("Plan")
            // }.tag(Tab.plan)

        }
    }
}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {

        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .monitor))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .online))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .data))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .console))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .settings))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())
        }
    }
}
