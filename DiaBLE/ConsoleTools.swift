import Foundation
import SwiftUI


struct ShellView: View {

    @EnvironmentObject var app: AppState
    @EnvironmentObject var log: Log
    @EnvironmentObject var settings: Settings

    @State private var showingStack = false

    @State private var showingFileImporter = false
    @State private var tridentContainer = ""

    var body: some View {

        VStack(spacing: 0) {

            if showingStack {
                HStack {

                    Spacer()

                    TextField("Trident Container", text: $tridentContainer)

                    Button {
                        showingFileImporter = true
                    } label: {
                        Image(systemName: "folder.circle")
                            .font(.system(size: 32))
                    }
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [.folder]  // .directory doesn't work
                    ) { result in
                        switch result {
                        case .success(let directory):
                            if !directory.startAccessingSecurityScopedResource() { return }
                            tridentContainer = directory.path
                            let fileManager = FileManager.default
                            let containerDirs = try! fileManager.contentsOfDirectory(atPath: tridentContainer)
                            app.main.log("ls \(tridentContainer)\n\(containerDirs)")
                            for dir in containerDirs {
                                if dir == "Documents" {
                                    let documentsFiles = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Documents")
                                    app.main.log("ls Documents\n\(documentsFiles)")
                                    for file in documentsFiles {
                                        if file == "trident.realm" {
                                            // TODO
                                        }
                                    }
                                }
                                if dir == "Library" {
                                    let libraryDirs = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Library")
                                    app.main.log("ls Library\n\(libraryDirs)")
                                    for dir in libraryDirs {
                                        if dir == "Preferences" {
                                            let preferencesContents = try! fileManager.contentsOfDirectory(atPath: "\(tridentContainer)/Library/Preferences")
                                            app.main.log("ls Preferences\n\(preferencesContents)")
                                            for plist in preferencesContents {
                                                if plist.hasPrefix("com.abbott.libre3") {
                                                    if let plistData = fileManager.contents(atPath:"\(tridentContainer)/Library/Preferences/\(plist)") {
                                                        if let libre3Plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
                                                            app.main.log("cat \(plist)\n\(libre3Plist)")
                                                            let realmEncryptionKey = libre3Plist["RealmEncryptionKey"] as! [UInt8]
                                                            let realmEncryptionKeyInt8 = realmEncryptionKey.map { Int8(bitPattern: $0) }
                                                            app.main.log("realmEncryptionKey:\n\(realmEncryptionKey)\nas Int8 array:\n\(realmEncryptionKeyInt8)")

                                                            // https://frdmtoplay.com/freeing-glucose-data-from-the-freestyle-libre-3/
                                                            //
                                                            // adb root
                                                            // sudo waydroid shell
                                                            // # /data/local/tmp/frida-server &
                                                            //
                                                            // $ frida -U "Libre 3"
                                                            // Frida-> Java.perform(function(){}); // Seems necessary to use Java.use
                                                            // Frida-> var crypto_lib_def = Java.use("com.adc.trident.app.frameworks.mobileservices.libre3.security.Libre3SKBCryptoLib");
                                                            // Frida-> var crypto_lib = crypto_lib_def.$new()
                                                            // Frida-> unwrapped = crypto_lib.unWrapDBEncryptionKey([<realmEncryptionKeyInt8>])
                                                            //
                                                            //
                                                            // let unwrappedInt8: [Int8] = [<unwrapped>]
                                                            // let unwrappedUInt8: [UInt8] = unwrappedInt8.map { UInt8(bitPattern: $0) }
                                                            // log(Data(unwrappedUInt8).reduce("", { $0 + String(format: "%02x", $1)}))

                                                            // TODO: parse rest of libre3Plist
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            directory.stopAccessingSecurityScopedResource()
                        case .failure(let error):
                            app.main.log("\(error)")
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
        }
        .toolbar {
            Button {
                withAnimation {
                    showingStack.toggle()
                }
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: showingStack ? "fossil.shell.fill" : "fossil.shell")
                    Text("Shell").font(.footnote)
                }
            }
        }
    }
}
