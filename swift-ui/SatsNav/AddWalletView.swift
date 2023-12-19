import Foundation
import SwiftUI

class NewWallet: ObservableObject {
    @Published var provider: WalletProvider = walletProviders[0]
    @Published var name: String = "Kraken"
    @Published var apiKey: String?
    @Published var apiSecret: String?
}

struct AddWalletView: View {
    @ObservedObject var newWallet = NewWallet()

    var body: some View {
        NavigationStack {
            WalletProviderView()
        }
        .environmentObject(newWallet)
        .onChange(of: newWallet.name) { _, currentName in
            print(currentName)
        }
    }
}

struct WalletProviderView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            Picker("Provider", selection: $newWallet.provider) {
                ForEach(walletProviders) { provider in
                    Text(provider.name).tag(provider)
                }
            }
        }
        .navigationBarTitle("Provider", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: WalletNameView()) {
                    Text("Next")
                }
            }
        }
    }
}

struct WalletNameView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            TextField("Kraken", text: $newWallet.name)
//                Section {
//                    Button("Choose CSV file") {
//                        // Implement file upload logic
//                    }
//                }
        }
        .navigationBarTitle("Wallet name", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {}) {
                    Text("Next")
                }
            }
        }
    }
}

#Preview {
    AddWalletView()
}
