import Foundation
import RealmSwift
import SwiftUI

struct AddServiceAccountView: View {
    @State var apiKey = ""
    @State var apiSecret = ""
    let onDone: (ServiceAccount?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    Text("Kraken")
                }

                Section("Credentials") {
                    TextField("API Key", text: $apiKey)
                    TextField("API Secret", text: $apiSecret)
                }
            }
            .navigationBarTitle("Add exchange account", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { onDone(nil) }) {
                        Text("Cancel")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { onDone(ServiceAccount(provider: "Kraken", apiKey: apiKey, apiSecret: apiSecret)) }) {
                        Text("Create")
                    }
                    .disabled(apiKey.isEmpty || apiSecret.isEmpty)
                }
            }
        }
    }
}

#Preview {
    AddServiceAccountView { wallet in print(wallet) }
}
