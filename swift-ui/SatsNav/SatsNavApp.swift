import Starscream
import SwiftData
import SwiftUI

let BTC = LedgerEntry.Asset(name: "BTC", type: .crypto)

@main
struct SatsNavApp: App {
    @StateObject private var webSocketManager = WebSocketManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(btcPrice: $webSocketManager.btcPrice).onAppear {
                webSocketManager.connect()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
