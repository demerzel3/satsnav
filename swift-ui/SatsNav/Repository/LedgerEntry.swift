import Foundation
import RealmSwift

enum AssetType: Int, Codable {
    case fiat, crypto
}

struct Asset: Hashable, Codable {
    let name: String
    let type: AssetType
}

final class RealmLedgerEntry: Object {
    enum LedgerEntryType: Int, PersistableEnum {
        case deposit
        case withdrawal
        case trade
        case interest
        case bonus
        case fee
        case transfer // Fallback
    }

    enum AssetType: Int, PersistableEnum, Codable {
        case fiat
        case crypto
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
            assetType = newValue.type == .fiat ? .fiat : .crypto
        }
        get {
            Asset(name: assetName, type: assetType == .fiat ? .fiat : .crypto)
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

struct LedgerEntry: Identifiable, Codable, Equatable, Hashable {
    let wallet: String
    let id: String
    let groupId: String
    let date: Date
    let type: LedgerEntryType
    let amount: Decimal
    let asset: Asset

    enum LedgerEntryType: Int, Codable {
        case deposit, withdrawal, trade, interest, bonus, fee, transfer
    }

    var description: String {
        "\(date) \(wallet) \(type) \(formattedAmount) - \(id)"
    }
}

// Computed props
extension LedgerEntry {
    var globalId: String {
        return "\(wallet)-\(id)"
    }
}

// Formatting methods
extension LedgerEntry {
    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(amount) : formatFiatAmount(amount))"
    }

    var formattedAbsAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(abs(amount)) : formatFiatAmount(abs(amount)))"
    }
}
