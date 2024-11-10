import Foundation
import RealmSwift

@RealmActor
class OnchainWalletRepository {
    private let credentials: Credentials

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    private func getRealm() throws -> Realm {
        try RealmActor.getRealm(credentials: credentials)
    }

    func getAllOnchainWallets() throws -> [OnchainWallet] {
        let realm = try getRealm()
        let entries = realm.objects(RealmOnchainWallet.self)
        return entries.map { self.convertToOnchainWallet($0) }
    }

    func convertToOnchainWallet(_ realmObject: RealmOnchainWallet) -> OnchainWallet {
        .init(
            name: realmObject.name, addresses: realmObject.addresses.map { $0.toAddress() }
        )
    }
}
