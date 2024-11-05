import SwiftUI


struct HamburgerMenu: View {

    @Environment(\.colorScheme) var colorScheme

    @State var showingSidebar = false

    @State var showingHelp = false
    @State var showingAbout = false

    let credits = [
        "@bubbledevteam": "https://github.com/bubbledevteam",
        "@captainbeeheart": "https://github.com/captainbeeheart",
        "@cryptax": "https://github.com/cryptax",
        "CryptoSwift": "https://github.com/krzyzanowskim/CryptoSwift",
        "@dabear": "https://github.com/dabear",
        "@DecentWoodpecker67": "https://github.com/DecentWoodpecker67",
        "FLwatch": "https://github.com/poml88/FLwatch",
        "Glucosy": "https://github.com/TopScrech/Glucosy-Libre",
        "@ivalkou": "https://github.com/ivalkou",
        "Jaap Korthals Altes": "https://github.com/j-kaltes",
        "@keencave": "https://github.com/keencave",
        "LibreMonitor": "https://github.com/UPetersen/LibreMonitor/tree/Swift4",
        "Loop": "https://github.com/LoopKit",
        "Marek Macner": "https://github.com/MarekM60",
        "@monder": "https://github.com/monder",
        "Nightguard": "https://github.com/nightscout/nightguard",
        "Nightscout LibreLink Up Uploader": "https://github.com/timoschlueter/nightscout-librelink-up",
        "@travisgoodspeed": "https://github.com/travisgoodspeed",
        "WoofWoof": "https://github.com/gshaviv/ninety-two",
        "xDrip": "https://github.com/Faifly/xDrip",
        "xDrip+": "https://github.com/NightscoutFoundation/xDrip",
        "xDrip4iO5": "https://github.com/JohanDegraeve/xdripswift"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            HStack {
                Spacer()
            }

            Button {
                withAnimation { showingHelp = true }
            } label: {
                Label("Help", systemImage: "questionmark.circle")
            }
            .padding(.leading, 6)
            .padding(.top, 20)
            .sheet(isPresented: $showingHelp) {
                NavigationView {
                    VStack(spacing: 40) {
                        VStack {
                            Text("Wiki").font(.headline)
                            Link("https://github.com/gui-dos/DiaBLE/wiki",
                                 destination: URL(string: "https://github.com/gui-dos/DiaBLE/wiki")!)
                        }
                        .padding(.top, 80)
                        Text("[ TODO ]")
                        Spacer()
                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("Help")
                    .navigationViewStyle(.stack)
                    .toolbar {
                        Button {
                            withAnimation { showingHelp = false }
                        } label: {
                            Text("Close")

                        }
                    }
                    .onAppear {
                        withAnimation { showingSidebar = false }
                    }
                    // TODO: click on any area
                    .onTapGesture {
                        withAnimation { showingHelp = false }
                    }
                }
            }

            Button {
                withAnimation { showingAbout = true }
            } label: {
                Label("About", systemImage: "info.circle")
            }
            .padding(.leading, 6)
            .sheet(isPresented: $showingAbout) {
                NavigationView {
                    VStack(spacing: 40) {
                        VStack {

                            Text("DiaBLE  \(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String)  (\(Bundle.main.infoDictionary!["CFBundleVersion"] as! String))")

                            // TODO: get AppIcon 1024x1024
                            // Image("AppIcon").resizable().frame(width: 100, height: 100)
                            if let uiImage = UIImage(named: "AppIcon60x60") {
                                Image(uiImage: uiImage).resizable().frame(width: 100, height: 100)
                            }
                            Link("https://github.com/gui-dos/DiaBLE",
                                 destination: URL(string: "https://github.com/gui-dos/DiaBLE")!)
                        }

                        VStack {
                            Image(systemName: colorScheme == .dark ? "envelope.fill" : "envelope")
                            Link(Data(base64Encoded: "Z3VpZG8uc29yYW56aW9AZ21haWwuY29t")!.string,
                                 destination: URL(string: "mailto:\(Data(base64Encoded: "Z3VpZG8uc29yYW56aW9AZ21haWwuY29t")!.string)")!)
                        }

                        VStack {
                            Image(systemName: "giftcard")
                            Link("PayPal", destination: URL(string: Data(base64Encoded: "aHR0cHM6Ly9wYXlwYWwubWUvZ3Vpc29y")!.string)!)
                        }

                        VStack {
                            Text("Credits:")
                            ScrollView {
                                ForEach(credits.sorted(by: <), id: \.key) { name, url in
                                    Link(name, destination: URL(string: url)!)
                                        .padding(.horizontal, 32)
                                }
                            }
                            .frame(height: 130)
                        }

                    }
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationTitle("About")
                    .navigationViewStyle(.stack)
                    .toolbar {
                        Button {
                            withAnimation { showingAbout = false }
                        } label: {
                            Text("Close")

                        }
                    }
                }
                .onAppear {
                    withAnimation { showingSidebar = false }
                }
                // TODO: click on any area
                .onTapGesture {
                    withAnimation { showingAbout = false }
                }
            }

            Spacer()

        }
        .frame(width: 180)
        .background(Color(.secondarySystemBackground))
        .offset(x: showingSidebar ? 0 : -180)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showingSidebar.toggle() }
                } label: {
                    Image(systemName: "line.horizontal.3")
                }
            }
        }
        // TODO: swipe gesture
        .onLongPressGesture(minimumDuration: 0) {
            withAnimation(.easeOut(duration: 0.15)) { showingSidebar = false }
        }

    }
}
