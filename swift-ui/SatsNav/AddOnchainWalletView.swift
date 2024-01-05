import Foundation
import RealmSwift
import SwiftUI

struct AddOnchainWalletView: View {
    let onDone: (OnchainWallet?) -> Void

    var body: some View {
        NavigationStack {
            WalletAddressesView(onDone: onDone)
        }
    }
}

private struct WalletAddressesView: View {
    let onDone: (OnchainWallet?) -> Void
    @State var name = "❄️"
    @State var addresses: RealmSwift.List<OnchainWalletAddress> = .init()

    var body: some View {
        Form {
            Section("Name") {
                TextField("Wallet name", text: $name)
            }

            Section("Addresses") {
                Text("\(addresses.count) addresses")
                Button(addresses.count == 0 ?
                    "Paste addresses" : "Paste more addresses", action: handlePaste)
                Button("Clear") {
                    addresses.removeAll()
                }.foregroundStyle(.red)
            }

            if addresses.count > 0 {
                Section {
                    List {
                        ForEach(addresses, id: \.self) { item in
                            Text(item.id).lineLimit(1).truncationMode(.middle)
                        }
                        .onDelete(perform: { indexSet in
                            addresses.remove(atOffsets: indexSet)
                        })
                    }
                }
            }
        }
        .navigationBarTitle("Add onchain wallet", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: { onDone(nil) }) {
                    Text("Cancel")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { onDone(OnchainWallet(name: name, addresses: addresses)) }) {
                    Text("Create")
                }
                .disabled(addresses.isEmpty)
            }
        }
    }

    private func handlePaste() {
        guard let pastedString = UIPasteboard.general.string else {
            return
        }

        let newAddresses = pastedString
            .split(separator: "\n")
            .compactMap(parseAddress)
        addresses.append(objectsIn: newAddresses)
    }
}

func parseAddress(row: ArraySlice<Character>) -> OnchainWalletAddress? {
    let chunks = row.split(separator: ",", maxSplits: 2)
    guard
        let address = chunks.first,
        let scriptHash = chunks.dropFirst().first,
        isValidBitcoinAddress(String(address)),
        isValidScriptHash(String(scriptHash))
    else {
        return nil
    }

    return OnchainWalletAddress(id: String(address), scriptHash: String(scriptHash))
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

#Preview {
    AddOnchainWalletView { wallet in print(wallet) }
}
