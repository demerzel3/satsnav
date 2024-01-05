import Starscream
import SwiftData
import SwiftUI

let BTC = Asset(name: "BTC", type: .crypto)

@main
struct SatsNavApp: App {
    @StateObject var credentialsStore = CredentialsStore()

    var body: some Scene {
        WindowGroup {
            ContentView(credentials: credentialsStore.credentials)
        }
    }
}
