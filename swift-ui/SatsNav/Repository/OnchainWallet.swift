import Foundation
import RealmSwift

final class RealmOnchainWalletAddress: EmbeddedObject {
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

final class RealmOnchainWallet: Object {
    @Persisted(primaryKey: true) var name: String
    @Persisted var addresses: List<RealmOnchainWalletAddress>

    convenience init(name: String, addresses: List<RealmOnchainWalletAddress>) {
        self.init()
        self.name = name
        self.addresses = addresses
    }
}

struct OnchainWallet {
    let name: String
    let addresses: [Address]
}
