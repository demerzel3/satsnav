import Foundation
import SwiftUI

private struct WalletProvider: Identifiable, Hashable {
    let name: String
    let createCSVReader: () -> CSVReader

    var id: String {
        return name
    }

    static func == (lhs: WalletProvider, rhs: WalletProvider) -> Bool {
        return lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

private let walletProviders = [
    WalletProvider(name: "Coinbase", createCSVReader: CoinbaseCSVReader.init),
    WalletProvider(name: "Kraken", createCSVReader: KrakenCSVReader.init),
    WalletProvider(name: "Ledn", createCSVReader: LednCSVReader.init),
    WalletProvider(name: "BlockFi", createCSVReader: BlockFiCSVReader.init),
    WalletProvider(name: "Celsius", createCSVReader: CelsiusCSVReader.init),
    // TODO: this definitely does not belong here, handle my personal case as Custom Data and delete the provider.
    WalletProvider(name: "Etherscan", createCSVReader: EtherscanCSVReader.init),
]

private let customWalletProvider = WalletProvider(name: "Custom Data", createCSVReader: CustomCSVReader.init)

typealias OnDone = ([LedgerEntry]?) -> Void

private class NewWallet: ObservableObject {
    let onDone: OnDone

    @Published var provider: WalletProvider
    @Published var csvFiles = [URL]()

    init(onDone: @escaping OnDone) {
        self.onDone = onDone
        self.provider = walletProviders[0]
    }
}

struct CSVImportView: View {
    @StateObject fileprivate var newWallet: NewWallet

    init(onDone: @escaping OnDone) {
        _newWallet = StateObject(wrappedValue: NewWallet(onDone: onDone))
    }

    var body: some View {
        NavigationStack {
            WalletProviderView()
        }
        .environmentObject(newWallet)
    }
}

private struct WalletProviderView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            List {
                ForEach(walletProviders) { provider in
                    NavigationLink(destination: { WalletCSVView(provider: provider) }) {
                        Text(provider.name)
                    }
                }
            }
            Section {
                NavigationLink(destination: { WalletCSVView(provider: customWalletProvider) }) {
                    Text(customWalletProvider.name)
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
        }
    }
}

private struct WalletCSVView: View {
    @State private var pickingFile = false
    @EnvironmentObject private var newWallet: NewWallet

    let provider: WalletProvider
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
                    Text("Import")
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
        .onAppear {
            newWallet.provider = self.provider
        }
    }
}

private struct AddWalletLoadingView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        VStack {
            Text("Importing data")
            ProgressView()
        }
        .navigationBarBackButtonHidden()
        .task {
            await importFromCSV()
        }
    }

    private func importFromCSV() async {
        var allLedgers = [LedgerEntry]()
        for url in newWallet.csvFiles {
            guard url.startAccessingSecurityScopedResource() else {
                print("Unable to access \(url) securely")
                break
            }

            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let ledgers = try await newWallet.provider.createCSVReader().read(fileUrl: url)
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
