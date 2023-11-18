import Foundation

enum GroupedLedger {
    // Single transaction within a wallet (e.g. Fee, Interest, Bonus) or ungrouped ledger entry
    case single(entry: LedgerEntry)
    // Trade within a single wallet
    case trade(spend: LedgerEntry, receive: LedgerEntry)
    // Transfer between wallets
    case transfer(from: LedgerEntry, to: LedgerEntry)
}

func groupLedgers(ledgers: [LedgerEntry]) -> [GroupedLedger] {
    return ledgers.reduce(into: [String: [LedgerEntry]]()) { groupIdToLedgers, entry in
        switch entry.type {
        // Group trades by ledger-provided groupId
        case .trade:
            groupIdToLedgers["\(entry.wallet)-\(entry.groupId)", default: [LedgerEntry]()].append(entry)
        // Group deposit and withdrawals by amount (may lead to false positives)
        case .deposit where entry.asset.type == .crypto,
             .withdrawal where entry.asset.type == .crypto:
            var id = "\(entry.asset.name)-\(btcFormatter.string(from: abs(entry.amount) as NSNumber)!)"

            // Skip until we find a suitable group, greedy strategy
            while groupIdToLedgers[id]?.count == 2 ||
                groupIdToLedgers[id]?[0].type == entry.type
            {
                id += "-"
            }

            groupIdToLedgers[id, default: [LedgerEntry]()].append(entry)
        default:
            // Avoid grouping other ledger entries
            groupIdToLedgers[UUID().uuidString] = [entry]
        }

        // let groupId = "\(entry.wallet)-\(entry.groupId)\(entry.type == .Fee ? "-fee" : "")"
        // groupIdToLedgers[groupId, default: [LedgerEntry]()].append(entry)
    }.values.sorted { a, b in
        a[0].date < b[0].date
    }.flatMap { group -> [GroupedLedger] in
        switch group.count {
        case 1: return [.single(entry: group[0])]
        case 2 where group[0].type == .trade && group[0].amount > 0 && group[1].amount < 0:
            return [.trade(spend: group[1], receive: group[0])]
        case 2 where group[0].type == .trade && group[0].amount < 0 && group[1].amount > 0:
            return [.trade(spend: group[0], receive: group[1])]
        case 2 where group[0].type == .trade:
            // Trade with 0 spend or receive, ungroup
            return [.single(entry: group[0]), .single(entry: group[1])]
        case 2 where group[0].type == .withdrawal && group[1].type == .deposit && group[0].wallet != group[1].wallet:
            return [.transfer(from: group[0], to: group[1])]
        case 2 where group[0].type == .deposit && group[1].type == .withdrawal && group[0].wallet != group[1].wallet:
            return [.transfer(from: group[1], to: group[0])]
        case 2 where group[0].type == group[1].type || group[0].wallet == group[1].wallet:
            // Wrongly matched by amount, ungroup!
            return [.single(entry: group[0]), .single(entry: group[1])]
        default:
            print(group)
            fatalError("Group has more than 2 elements")
        }
    }
}
