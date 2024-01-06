import Foundation

struct KrakenLedgerEntry {
    let id: String
    let refId: String
    let time: Date
    let type: String
    let subtype: String
    let asset: String
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
        case "XBT.M":
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
    var lastDepositWithdrawalDate: Date?
    var balances = [String: Decimal]()
    var sanitizedCount = 0
    var ledgers = [LedgerEntry]()
    // "txid","refid","time","type","subtype","aclass","asset","amount","fee","balance"
    for dict in entries {
        let id = dict.id
        let subtype = dict.subtype
        let date = dict.time
        let type: LedgerEntry.LedgerEntryType = switch dict.type {
        case "deposit": .deposit
        case "withdrawal": .withdrawal
        case "trade": .trade
        case "spend": .trade
        case "receive": .trade
        case "staking": .interest
        case "dividend": .interest
        case "transfer" where subtype == "spottostaking": .withdrawal
        case "transfer" where subtype == "stakingfromspot": .deposit
        case "transfer": .transfer
        case "nfttrade": .transfer
        default:
            fatalError("Unexpected Kraken transaction type: \(dict.type)")
        }

        // Duplicated Deposit/Withdrawal, skip
        if type == .withdrawal || type == .deposit, id == "" {
            lastDepositWithdrawalDate = date
            continue
        }

        let ticker = dict.asset
        let asset = Asset(fromKrakenTicker: ticker)
        let balance = dict.balance
        let amount = dict.amount
        let fee = dict.fee
        let entry = LedgerEntry(
            wallet: "Kraken",
            id: balance < 0 ? "sanitized-\(id)" : id,
            groupId: dict.refId,
            // Use date of entry with no ID that generally precedes the one with ID
            date: type == .withdrawal ? lastDepositWithdrawalDate ?? date : date,
            // Failed withdrwals get reaccredited, we want to track those as deposits
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
        if amount > 0, balances[ticker, default: 0] < 0 {
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

        if balances[ticker] == nil {
            balances[ticker] = balance
        } else {
            balances[ticker, default: 0] += amount - fee
        }
        ledgers.append(entry)

        // Ledger sanity check
        if ticker != "NFT", balances[ticker, default: 0] != balance {
            fatalError("Wrong balance for \(ticker), is \(balances[ticker, default: 0]), expected \(balance)")
        }
    }

    if sanitizedCount > 0 {
        fatalError("Sanitized count should be 0, is \(sanitizedCount)")
    }

    return ledgers
}
