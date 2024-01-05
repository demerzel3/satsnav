import Foundation
import RealmSwift

final class OnchainWallet: Object {
    @Persisted(primaryKey: true) var name: String
    @Persisted var addresses: List<OnchainWalletAddress>

    convenience init(name: String, addresses: List<OnchainWalletAddress>) {
        self.init()
        self.name = name
        self.addresses = addresses
    }
}

final class OnchainWalletAddress: EmbeddedObject {
    @Persisted var id: String
    @Persisted var scriptHash: String

    convenience init(id: String, scriptHash: String) {
        self.init()
        self.id = id
        self.scriptHash = scriptHash
    }

    func toAddress() -> Address {
        Address(id: id, scriptHash: scriptHash)
    }
}
