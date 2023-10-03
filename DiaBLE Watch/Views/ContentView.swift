import SwiftUI


struct ContentView: View {

    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var history: History
    @EnvironmentObject var settings: Settings

    var body: some View {

        NavigationStack {

            TabView(selection: $app.selectedTab) {

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }.tag(Tab.settings)

                Monitor()
                    .tabItem {
                        Label("Monitor", systemImage: "gauge")
                    }.tag(Tab.monitor)

                OnlineView()
                    .tabItem {
                        Label("Online", systemImage: "globe")
                    }.tag(Tab.online)

                Console()
                    .tabItem {
                        Label("Console", systemImage: "terminal")
                    }.tag(Tab.console)

                DataView()
                    .tabItem {
                        Label("Data", systemImage: "tray.full.fill")
                    }.tag(Tab.data)

                //  Plan()
                //      .tabItem {
                //          Image(systemName: "map")
                //          Text("Plan")
                //  }.tag(Tab.plan)

            }

            // FIXME: often hangs
            // .tabViewStyle(.verticalPage)

        }

    }
}


#Preview {
    ContentView()
        .environmentObject(AppState.test(tab: .monitor))
        .environmentObject(Log())
        .environmentObject(History.test)
        .environmentObject(Settings())
}
