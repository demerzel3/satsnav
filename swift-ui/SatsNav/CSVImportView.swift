import Foundation
import SwiftUI

struct WalletProvider: Identifiable, Hashable {
    let name: String
    let defaultWalletName: String?
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
    WalletProvider(name: "Coinbase", defaultWalletName: "Coinbase", createCSVReader: CoinbaseCSVReader.init),
    WalletProvider(name: "Kraken", defaultWalletName: "Kraken", createCSVReader: KrakenCSVReader.init),
    WalletProvider(name: "Ledn", defaultWalletName: "Ledn", createCSVReader: LednCSVReader.init),
    WalletProvider(name: "BlockFi", defaultWalletName: "BlockFi", createCSVReader: BlockFiCSVReader.init),
    WalletProvider(name: "Celsius", defaultWalletName: "Celsius", createCSVReader: CelsiusCSVReader.init),
    WalletProvider(name: "Etherscan", defaultWalletName: "Etherscan", createCSVReader: EtherscanCSVReader.init),
//     WalletProvider(name: "Custom Data", defaultWalletName: nil, createCSVReader: CustomCSVReader.init),
//     WalletProvider(name: "BTC (on-chain)", defaultWalletName: "❄️", createCSVReader: nil),
]

private let customWalletProvider = WalletProvider(name: "Custom Data", defaultWalletName: nil, createCSVReader: CustomCSVReader.init)

// TODO: allow to return OnchainWallet from here? or best just to move on chain to a different flow
typealias OnDone = ([LedgerEntry]?) -> Void

class NewWallet: ObservableObject {
    let onDone: OnDone

    @Published var provider: WalletProvider
    @Published var name: String
    @Published var csvFiles = [URL]()
    @Published var addresses = [Address]()
    @Published var apiKey: String?
    @Published var apiSecret: String?

    init(onDone: @escaping OnDone) {
        self.onDone = onDone
        self.provider = walletProviders[0]
        self.name = walletProviders[0].defaultWalletName ?? "-"
    }
}

struct CSVImportView: View {
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
            List {
                ForEach(walletProviders.filter { $0.defaultWalletName != nil }) { provider in
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

//            ToolbarItem(placement: .topBarTrailing) {
//                NavigationLink(destination: WalletNameView()) {
//                    Text("Next")
//                }
//            }
        }
        .onChange(of: newWallet.provider) { _, newValue in
            newWallet.name = newValue.defaultWalletName ?? "-"
        }
    }
}

// struct WalletNameView: View {
//    @EnvironmentObject private var newWallet: NewWallet
//
//    var body: some View {
//        Form {
//            TextField(newWallet.provider.defaultWalletName ?? "-", text: $newWallet.name)
//        }
//        .navigationBarTitle("Wallet name", displayMode: .inline)
//        .toolbar {
////            if newWallet.provider.createCSVReader == nil {
////                ToolbarItem(placement: .topBarTrailing) {
////                    NavigationLink(destination: WalletAddressesView()) { Text("Next") }
////                        .disabled(newWallet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
////                }
////            }
//
//            ToolbarItem(placement: .topBarTrailing) {
//                NavigationLink(destination: WalletCSVView()) { Text("Next") }
//                    .disabled(newWallet.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
//            }
//        }
//    }
// }

struct WalletCSVView: View {
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

struct WalletAddressesView: View {
    @EnvironmentObject private var newWallet: NewWallet

    var body: some View {
        Form {
            Section {
                Text("\(newWallet.addresses.count) addresses")
                Button(newWallet.addresses.count == 0 ?
                    "Paste addresses" : "Paste more addresses", action: handlePaste)
                Button("Clear") {
                    newWallet.addresses.removeAll()
                }.foregroundStyle(.red)
            }

            if newWallet.addresses.count > 0 {
                Section {
                    List {
                        ForEach(newWallet.addresses, id: \.self) { item in
                            Text(item.id).lineLimit(1).truncationMode(.middle)
                        }
                        .onDelete(perform: { indexSet in
                            newWallet.addresses.remove(atOffsets: indexSet)
                        })
                    }
                }
            }
        }
        .navigationBarTitle("Import data", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: AddWalletLoadingView()) {
                    Text("Create")
                }
                .disabled(newWallet.addresses.isEmpty)
            }
        }
    }

    private func handlePaste() {
        guard let pastedString = UIPasteboard.general.string else {
            return
        }

        let newAddresses = pastedString
            .split(separator: "\n")
            .compactMap(parseAddressAndScriptHash)
        newWallet.addresses.append(contentsOf: newAddresses)
    }
}

func parseAddressAndScriptHash(row: ArraySlice<Character>) -> Address? {
    let chunks = row.split(separator: ",", maxSplits: 2)
    guard
        let address = chunks.first,
        let scriptHash = chunks.dropFirst().first,
        isValidBitcoinAddress(String(address)),
        isValidScriptHash(String(scriptHash))
    else {
        return nil
    }

    return Address(id: String(address), scriptHash: String(scriptHash))
}

// TODO: used only to filter input, but to be replaced with proper validation
func isValidBitcoinAddress(_ address: String) -> Bool {
    let regex = "^(1|3|bc1)[a-zA-Z0-9]{25,59}$"
    return address.range(of: regex, options: .regularExpression) != nil
}

// TODO: eventually generate this from the address instead of relying on user input
func isValidScriptHash(_ scriptHash: String) -> Bool {
    let regex = "^[a-f0-9]{64}$"
    return scriptHash.range(of: regex, options: .regularExpression) != nil
}

struct AddWalletLoadingView: View {
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

    private func importFromBlockchain() async {
        let fetcher = OnchainTransactionsFetcher()
        newWallet.onDone(await fetcher.fetchOnchainTransactions(addresses: newWallet.addresses))
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
