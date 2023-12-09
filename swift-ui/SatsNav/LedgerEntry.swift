import Foundation

final class LedgerEntry: CustomStringConvertible {
    enum LedgerEntryType: Int, Codable {
        case deposit
        case withdrawal
        case trade
        case interest
        case bonus
        case fee
        case transfer // Fallback
    }

    enum AssetType: Int, Codable {
        case fiat
        case crypto
    }

    struct Asset: Hashable, Codable {
        let name: String
        let type: AssetType
    }

    let wallet: String
    let id: String
    let globalId: String
    let groupId: String // Useful to group together ledgers from the same provider, usually part of the same transaction
    let date: Date
    let type: LedgerEntryType
    let amount: Decimal
    let asset: Asset

    init(wallet: String, id: String, groupId: String, date: Date, type: LedgerEntryType, amount: Decimal, asset: Asset) {
        self.wallet = wallet
        self.id = id
        self.globalId = "\(wallet)-\(id)"
        self.groupId = groupId
        self.date = date
        self.type = type
        self.amount = amount
        self.asset = asset
    }

    var formattedAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(amount) : formatFiatAmount(amount))"
    }

    var formattedAbsAmount: String {
        "\(asset.name) \(asset.type == .crypto ? formatBtcAmount(abs(amount)) : formatFiatAmount(abs(amount)))"
    }

    var description: String {
        "\(date) \(wallet) \(type) \(formattedAmount) - \(id)"
    }
}
