import SwiftUI


struct ContentView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    var body: some View {

        TabView(selection: $app.selectedTab) {
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
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .online))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .data))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .console))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())

            ContentView()
                .preferredColorScheme(.dark)
                .environmentObject(AppState.test(tab: .settings))
                .environmentObject(Log())
                .environmentObject(History.test)
                .environmentObject(Settings())
        }
    }
}
