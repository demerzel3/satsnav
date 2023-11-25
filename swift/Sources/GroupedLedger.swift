import Foundation

enum GroupedLedger: CustomStringConvertible {
    // Single transaction within a wallet (e.g. Fee, Interest, Bonus) or ungrouped ledger entry
    case single(entry: LedgerEntry)
    // Trade within a single wallet
    case trade(spend: LedgerEntry, receive: LedgerEntry)
    // Transfer between wallets
    case transfer(from: LedgerEntry, to: LedgerEntry)

    var date: Date {
        switch self {
        case .single(let entry):
            return entry.date
        case .trade(let spend, let receive):
            return spend.date < receive.date ? spend.date : receive.date
        case .transfer(let from, let to):
            return from.date < to.date ? from.date : to.date
        }
    }

    var description: String {
        switch self {
        case .single(let entry):
            return entry.description
        case .trade(let spend, let receive):
            return "trade \(spend) for \(receive)"
        case .transfer(let from, let to):
            return "transfer from \(from) to \(to)"
        }
    }
}

func groupLedgers(ledgers: [LedgerEntry]) -> [GroupedLedger] {
    var transferByAmount = [String: LedgerEntry]()
    var tradesByGroupId = [String: LedgerEntry]()
    var groups = [GroupedLedger]()

    for entry in ledgers {
        switch entry.type {
        case .deposit where entry.asset.type == .crypto,
             .withdrawal where entry.asset.type == .crypto:
            let key = entry.abs().formattedAmount

            // pair with existing transfer
            if let transfer = transferByAmount[key], transfer.type != entry.type {
                if entry.amount > 0 {
                    groups.append(.transfer(from: transfer, to: entry))
                } else {
                    groups.append(.transfer(from: entry, to: transfer))
                }
                transferByAmount.removeValue(forKey: key)
                continue
            }

            // A transfer with same amount already exists, move that to single entry and replace.
            if let transferWithSameAmount = transferByAmount[key] {
                // print("⚠️ Found another non-matching transfer with the same amount", transferWithSameAmount)
                groups.append(.single(entry: transferWithSameAmount))
            }

            // save for later pairing with another transfer
            transferByAmount[key] = entry
        case .trade where entry.amount != 0:
            let key = "\(entry.wallet)-\(entry.groupId)"
            if let match = tradesByGroupId[key] {
                if entry.amount > 0 {
                    groups.append(.trade(spend: match, receive: entry))
                } else {
                    groups.append(.trade(spend: entry, receive: match))
                }
                tradesByGroupId.removeValue(forKey: key)
                continue
            }

            if tradesByGroupId[key] != nil {
                fatalError("Found invalid entry in tradesByGroupId for key \(key)")
            }

            // save for later pairing with another trade
            tradesByGroupId[key] = entry
        default:
            groups.append(.single(entry: entry))
        }
    }

    // TODO: try some more fuzzy matching with these bois
    print("Leftover trasfers: \(transferByAmount.count)")
    print("Leftover trades: \(tradesByGroupId.count)")

    groups.append(contentsOf: transferByAmount.values.map { .single(entry: $0) })
    groups.append(contentsOf: tradesByGroupId.values.map { .single(entry: $0) })

    return groups.sorted { $0.date < $1.date }
}
