import Foundation
import SwiftUI

typealias OnDone = ([LedgerEntry]?) -> Void

class NewWallet: ObservableObject {
    let onDone: OnDone

    @Published var provider: WalletProvider
    @Published var name: String
    @Published var csvFiles = [URL]()
    @Published var apiKey: String?
    @Published var apiSecret: String?

    init(onDone: @escaping OnDone) {
        self.onDone = onDone
        self.provider = walletProviders[0]
        self.name = walletProviders[0].defaultWalletName
    }
}

struct AddWalletView: View {
    @StateObject var newWallet: NewWallet

    init(onDone: @escaping OnDone) {
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
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { newWallet.onDone(nil) }) {
                    Text("Cancel")
                }
            }

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
                .disabled(newWallet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

struct WalletCSVView: View {
    @State private var pickingFile = false
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            List {
                ForEach(newWallet.csvFiles, id: \.self) { item in
                    Text(item.lastPathComponent)
                }
                .onDelete(perform: { indexSet in
                    newWallet.csvFiles.remove(atOffsets: indexSet)
                })
            }
            Button(newWallet.csvFiles.isEmpty ? "Choose CSV file" : "Choose additional CSV file") {
                pickingFile = true
            }
        }
        .navigationBarTitle("Import data", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AddWalletLoadingView()) {
                    Text("Create")
                }
                .disabled(newWallet.csvFiles.isEmpty)
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.commaSeparatedText]) { result in
            guard let url = try? result.get() else {
                return
            }

            newWallet.csvFiles.append(url)
        }
    }
}

struct AddWalletLoadingView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        VStack {
            Text("Creating wallet")
            ProgressView()
        }
        .navigationBarBackButtonHidden()
        .task {
            await createWallet()
        }
    }

    private func createWallet() async {
        guard let createReader = newWallet.provider.createCSVReader else {
            print("No CSV reader constructor, skipping...")
            newWallet.onDone(nil)
            return
        }

        var allLedgers = [LedgerEntry]()
        for url in newWallet.csvFiles {
            do {
                let ledgers = try await createReader().read(fileUrl: url)
                print("Ledgers for \(url): \(ledgers.count)")
                allLedgers.append(contentsOf: ledgers)
            } catch {
                print("Error while reading \(url): \(error)")
            }
        }

        newWallet.onDone(allLedgers)
    }
}

#Preview {
    AddWalletLoadingView()
}
