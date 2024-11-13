import Foundation
import RealmSwift

@RealmActor
class OnchainWalletRepository {
    private let credentials: Credentials

    init(credentials: Credentials) {
        self.credentials = credentials
    }

    private func getRealm() throws -> Realm {
        return try RealmActor.getRealm(credentials: credentials)
    }

    func getAllOnchainWallets() throws -> [OnchainWallet] {
        let realm = try getRealm()
        let entries = realm.objects(RealmOnchainWallet.self)
        return entries.map { self.convertToOnchainWallet($0) }
    }

    func add(_ wallet: OnchainWallet) throws {
        let realm = try getRealm()
        try! realm.write {
            realm.add(convertToRealmOnchainWallet(wallet))
        }
    }

    private func convertToOnchainWallet(_ realmObject: RealmOnchainWallet) -> OnchainWallet {
        .init(
            name: realmObject.name, addresses: realmObject.addresses.map { $0.toAddress() }
        )
    }

    private func convertToRealmOnchainWallet(_ object: OnchainWallet) -> RealmOnchainWallet {
        let addresses = List<RealmOnchainWalletAddress>()
        addresses.append(objectsIn: object.addresses.map { RealmOnchainWalletAddress(id: $0.id, scriptHash: $0.scriptHash) })

        return .init(
            name: object.name, addresses: addresses
        )
    }
}
