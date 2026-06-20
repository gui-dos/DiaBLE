import SwiftUI


struct ContentView: View {

    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    var body: some View {

        @Bindable var settings = settings

        NavigationStack {

            TabView(selection: $settings.selectedTab) {

                Tab("Settings", systemImage: "gear", value: .settings) {
                    SettingsView()
                }

                Tab("Monitor", systemImage: "gauge", value: .monitor) {
                    Monitor()
                }

                Tab("Online", systemImage: "globe", value: .online) {
                    OnlineView()
                }

                Tab("Console", systemImage: "terminal", value: .console) {
                    Console()
                }

                Tab("Data", systemImage: "tray.full.fill", value: .data) {
                    DataView()
                }

                // Tab("Plan", systemImage: "map", value: .plan) {
                //     Plan()
                // }

            }
            .toolbarBackground(.hidden, for: .navigationBar)

            // FIXME: often hangs
            // .tabViewStyle(.verticalPage)

        }

    }
}


#Preview {
    ContentView()
        .environment(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
