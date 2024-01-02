import Foundation
import RealmSwift

final class OnchainWallet: Object {
    @Persisted(primaryKey: true) var name: String
    @Persisted var addresses: List<Address>

    convenience init(name: String, addresses: List<Address>) {
        self.init()
        self.name = name
        self.addresses = addresses
    }
}
