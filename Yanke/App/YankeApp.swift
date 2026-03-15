import SwiftUI

@main
struct YankeApp: App {
    @State private var incomingURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(incomingURL: $incomingURL)
                .onOpenURL { url in
                    incomingURL = url
                }
        }
    }
}
