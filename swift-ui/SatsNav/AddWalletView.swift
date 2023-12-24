import Foundation
import SwiftUI

class NewWallet: ObservableObject {
    let onDone: () -> Void

    @Published var provider: WalletProvider
    @Published var name: String
    @Published var apiKey: String?
    @Published var apiSecret: String?

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        self.provider = walletProviders[0]
        self.name = walletProviders[0].defaultWalletName
    }
}

struct AddWalletView: View {
    @StateObject var newWallet: NewWallet

    init(onDone: @escaping () -> Void) {
        _newWallet = StateObject(wrappedValue: NewWallet(onDone: onDone))
    }

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
        .onChange(of: newWallet.provider) { _, newValue in
            newWallet.name = newValue.defaultWalletName
        }
    }
}

struct WalletNameView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            TextField(newWallet.provider.defaultWalletName, text: $newWallet.name)
        }
        .navigationBarTitle("Wallet name", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: WalletCSVView()) {
                    Text("Next")
                }
            }
        }
    }
}

struct WalletCSVView: View {
    @State private var pickingFile = false
    @State private var selectedFiles = [URL]()
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            List {
                ForEach(selectedFiles, id: \.self) { item in
                    Text(item.lastPathComponent)
                }
                .onDelete(perform: { indexSet in
                    selectedFiles.remove(atOffsets: indexSet)
                })
            }
            Button(selectedFiles.isEmpty ? "Choose CSV file" : "Choose additional CSV file") {
                pickingFile = true
            }
        }
        .navigationBarTitle("Import data", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { newWallet.onDone() }) {
                    Text(selectedFiles.isEmpty ? "Skip" : "Next")
                }
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.commaSeparatedText]) { result in
            guard let url = try? result.get() else {
                return
            }

            selectedFiles.append(url)
        }
    }
}

#Preview {
    AddWalletView {}
}
