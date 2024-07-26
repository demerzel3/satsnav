import Foundation
import RealmSwift

class LedgerRepository {
    private let realmConfiguration: Realm.Configuration
    private var realm: Realm?

    init(credentials: Credentials) {
        print("SECRET", credentials.localStorageEncryptionKey.toHexString())

        self.realmConfiguration = Realm.Configuration(encryptionKey: credentials.localStorageEncryptionKey)
    }

    @RealmActor
    func getAllLedgerEntries() async -> [LedgerEntry] {
        let realm = try! await getRealm()
        let entries = realm.objects(RealmLedgerEntry.self).sorted { a, b in a.date < b.date }
        return entries.map { self.convertToLedgerEntry($0) }
    }

    @RealmActor
    func getLedgerById(_ id: String) async -> LedgerEntry? {
        let realm = try! await getRealm()
        guard let realmEntry = realm.object(ofType: RealmLedgerEntry.self, forPrimaryKey: id) else {
            return nil
        }
        return convertToLedgerEntry(realmEntry)
    }

    @RealmActor
    func addLedgerEntry(_ entry: LedgerEntry) async throws {
        let realm = try! await getRealm()
        try realm.write {
            let realmEntry = self.convertToRealmLedgerEntry(entry)
            realm.add(realmEntry, update: .modified)
        }
    }

    @RealmActor
    func merge(_ newEntries: [LedgerEntry]) async throws -> Int {
        let realm = try! await getRealm()
        var addedCount = 0
        var updatedCount = 0

        try realm.write {
            for entry in newEntries {
                if let existingEntry = realm.object(ofType: RealmLedgerEntry.self, forPrimaryKey: entry.globalId) {
                    // Update existing entry
                    existingEntry.wallet = entry.wallet
                    existingEntry.id = entry.id
                    existingEntry.groupId = entry.groupId
                    existingEntry.date = entry.date
                    existingEntry.type = convertTypeToRealmType(entry.type)
                    existingEntry.amount = entry.amount
                    existingEntry.assetName = entry.asset.name
                    existingEntry.assetType = convertAssetTypeToRealmAssetType(entry.asset.type)
                    updatedCount += 1
                } else {
                    // Add new entry
                    let realmEntry = convertToRealmLedgerEntry(entry)
                    realm.add(realmEntry)
                    addedCount += 1
                }
            }
        }

        return addedCount + updatedCount
    }

    private func convertTypeToRealmType(_ type: LedgerEntry.LedgerEntryType) -> RealmLedgerEntry.LedgerEntryType {
        return RealmLedgerEntry.LedgerEntryType(rawValue: type.rawValue) ?? .transfer
    }

    private func convertAssetTypeToRealmAssetType(_ assetType: AssetType) -> RealmLedgerEntry.AssetType {
        return RealmLedgerEntry.AssetType(rawValue: assetType.rawValue) ?? .crypto
    }

    private func convertToLedgerEntry(_ realmEntry: RealmLedgerEntry) -> LedgerEntry {
        return LedgerEntry(
            wallet: realmEntry.wallet,
            id: realmEntry.id,
            groupId: realmEntry.groupId,
            date: realmEntry.date,
            type: LedgerEntry.LedgerEntryType(rawValue: realmEntry.type.rawValue) ?? .transfer,
            amount: realmEntry.amount,
            asset: realmEntry.asset
        )
    }

    private func convertToRealmLedgerEntry(_ entry: LedgerEntry) -> RealmLedgerEntry {
        let realmEntry = RealmLedgerEntry()
        realmEntry.id = entry.id
        realmEntry.wallet = entry.wallet
        realmEntry.globalId = entry.globalId
        realmEntry.groupId = entry.groupId
        realmEntry.date = entry.date
        realmEntry.type = convertTypeToRealmType(entry.type)
        realmEntry.amount = entry.amount
        realmEntry.assetName = entry.asset.name
        realmEntry.assetType = convertAssetTypeToRealmAssetType(entry.asset.type)
        return realmEntry
    }

    private func getRealm() async throws -> Realm {
        if realm == nil {
            realm = try await Realm(configuration: realmConfiguration, actor: RealmActor.shared)
        }

        return realm!
    }
}
