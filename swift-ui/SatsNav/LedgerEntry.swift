import Foundation
import RealmSwift

enum AssetType: Int, PersistableEnum {
    case fiat
    case crypto
}

struct Asset: Hashable {
    let name: String
    let type: AssetType
}

final class LedgerEntry: Object {
    enum LedgerEntryType: Int, PersistableEnum {
        case deposit
        case withdrawal
        case trade
        case interest
        case bonus
        case fee
        case transfer // Fallback
    }

    @Persisted var wallet: String
    @Persisted var id: String
    @Persisted(primaryKey: true) var globalId: String
    @Persisted var groupId: String // Useful to group together ledgers from the same provider, usually part of the same transaction
    @Persisted var date: Date
    @Persisted var type: LedgerEntryType
    @Persisted var amount: Decimal
    @Persisted var assetName: String
    @Persisted var assetType: AssetType

    convenience init(wallet: String, id: String, groupId: String, date: Date, type: LedgerEntryType, amount: Decimal, asset: Asset) {
        self.init()
        self.wallet = wallet
        self.id = id
        self.globalId = "\(wallet)-\(id)"
        self.groupId = groupId
        self.date = date
        self.type = type
        self.amount = amount
        self.asset = asset
    }

    var asset: Asset {
        set {
            assetName = newValue.name
            assetType = newValue.type
        }
        get {
            Asset(name: assetName, type: assetType)
        }
    }

    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(amount) : formatFiatAmount(amount))"
    }

    var formattedAbsAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(abs(amount)) : formatFiatAmount(abs(amount)))"
    }

    override var description: String {
        "\(date) \(wallet) \(type) \(formattedAmount) - \(id)"
    }
}

extension Decimal: CustomPersistable {
    public typealias PersistedType = String

    public init(persistedValue: String) {
        self = Decimal(string: persistedValue) ?? 0
    }

    public var persistableValue: PersistedType {
        "\(self)"
    }
}
