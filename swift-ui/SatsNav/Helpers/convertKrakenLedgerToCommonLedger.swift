import Foundation

struct KrakenLedgerEntry {
    let id: String
    let refId: String
    let time: Date
    let type: String
    let subtype: String
    let asset: String
    let wallet: String
    let amount: Decimal
    let fee: Decimal
    let balance: Decimal
}

extension Asset {
    init(fromKrakenTicker ticker: String) {
        switch ticker {
        case "XXBT":
            self.name = "BTC"
            self.type = .crypto
        case "XXDG":
            self.name = "DOGE"
            self.type = .crypto
        // .M is locked staking, .F is flexible staking
        case "XBT.M", "XBT.F":
            self.name = "BTC"
            self.type = .crypto
        case let a where a.hasPrefix("X"):
            self.name = String(a.dropFirst())
            self.type = .crypto
        case let a where a.hasPrefix("Z"):
            let startIndex = a.index(a.startIndex, offsetBy: 1)
            // get rid of .HOLD as it's not really useful
            let endIndex = a.index(a.endIndex, offsetBy: a.hasSuffix(".HOLD") ? -5 : 0)
            if a.hasSuffix(".HOLD") {
                print(a, a.hasSuffix(".HOLD"), endIndex)
            }
            self.name = String(a[startIndex ..< endIndex])
            self.type = .fiat
        case let a where a.hasSuffix(".HOLD"):
            let endIndex = a.index(a.endIndex, offsetBy: a.hasSuffix(".HOLD") ? -5 : 0)
            self.name = String(a[a.startIndex ..< endIndex])
            self.type = .fiat
        default:
            self.name = ticker
            self.type = .crypto
        }
    }
}

func convertKrakenLedgerToCommonLedger(entries: [KrakenLedgerEntry]) -> [LedgerEntry] {
    var balances = [String: Decimal]()
    var lastEarnEntry: KrakenLedgerEntry?
    var sanitizedCount = 0
    var ledgers = [LedgerEntry]()

    for dict in entries {
        let ticker = dict.asset
        let balanceKey = "\(ticker)-\(dict.wallet)"
        let subtype = dict.subtype
        let date = dict.time
        let amount = dict.amount
        let type: LedgerEntry.LedgerEntryType = switch dict.type {
        case "deposit": .deposit
        case "withdrawal": .withdrawal
        case "trade": .trade
        case "spend": .trade
        case "receive": .trade
        case "staking": .interest
        case "dividend": .interest
        case "earn" where amount < 0: .withdrawal
        case "earn" where amount > 0 && lastEarnEntry?.asset == dict.asset && lastEarnEntry?.amount == -amount: .deposit
        case "earn" where amount > 0: .interest
        case "earn": fatalError("Unexpected earn entry \(dict)")
        case "transfer" where subtype == "spottostaking": .withdrawal
        case "transfer" where subtype == "stakingfromspot": .deposit
        case "transfer": .transfer
        case "nfttrade": .transfer
        default:
            fatalError("Unexpected Kraken transaction type: \(dict.type)")
        }

        // Keep the last entry around to match transfers between wallets
        if dict.type == "earn", amount < 0 {
            lastEarnEntry = dict
        }

        let asset = Asset(fromKrakenTicker: ticker)
        let balance = dict.balance
        let id = balance < 0 ? "sanitized-\(dict.id)" : dict.id
        let fee = abs(dict.fee)
        let entry = LedgerEntry(
            wallet: "Kraken",
            id: id,
            groupId: dict.refId == "Unknown" ? id : dict.refId,
            // Use date of entry with no ID that generally precedes the one with ID
            date: date,
            // Failed withdrawals get reaccredited, we want to track those as deposits
            type: type == .withdrawal && amount > 0 ? .deposit : type,
            amount: balance < 0 ? amount - balance : amount,
            asset: asset
        )

        if balance < 0 {
            sanitizedCount += 1
        }

        if fee > 0 {
            ledgers.append(LedgerEntry(
                wallet: entry.wallet,
                id: "fee-\(entry.id)",
                groupId: entry.groupId,
                // Putting the fee 1 second after the trade avoids issues with balance not being present.
                date: entry.date.addingTimeInterval(1),
                type: .fee,
                amount: -fee,
                asset: asset
            ))
        }

        // Compensate amount sanitization with a separate fee entry
        if amount > 0, balances[balanceKey, default: 0] < 0 {
            ledgers.append(LedgerEntry(
                wallet: entry.wallet,
                id: "sanitized-fee-\(entry.id)",
                groupId: entry.groupId,
                // Putting the fee 1 second after the trade avoids issues with balance not being present.
                date: entry.date.addingTimeInterval(1),
                type: .fee,
                amount: balances[ticker, default: 0],
                asset: asset
            ))
            sanitizedCount -= 1
        }

        if balances[balanceKey] == nil {
            balances[balanceKey] = balance
        } else {
            balances[balanceKey, default: 0] += amount - fee
        }
        ledgers.append(entry)

        // Ledger sanity check
        if ticker != "NFT", balances[balanceKey, default: 0] != balance {
            // print("Wrong balance for \(ticker), is \(balances[ticker, default: 0]), expected \(balance)")
            fatalError("Wrong balance for \(ticker), is \(balances[balanceKey, default: 0]), expected \(balance)")
        }
    }

    assert(sanitizedCount > 0, "Sanitized count should be 0, is \(sanitizedCount)")

    return ledgers
}
