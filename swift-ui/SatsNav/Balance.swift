import Foundation

let BASE_ASSET = Asset(name: "EUR", type: .fiat)

struct Ref: Identifiable, Equatable, Hashable {
    let id: UUID = .init()

    let refIds: [String]
    let asset: Asset
    let amount: Decimal
    let date: Date
    let rate: Decimal?
    let spends: [Ref]

    init(refIds: [String], asset: Asset, amount: Decimal, date: Date, rate: Decimal?, spends: [Ref]? = nil) {
        self.refIds = refIds
        self.asset = asset
        self.amount = amount
        self.date = date
        self.rate = rate
        self.spends = spends ?? []
    }

    var refId: String {
        refIds.first!
    }

    var count: Int {
        refIds.count
    }

    func withAmount(_ newAmount: Decimal, rate newRate: Decimal? = nil, date newDate: Date? = nil) -> Ref {
        assert(newAmount > 0, "Invalid amount \(newAmount)")
        return Ref(refIds: refIds, asset: asset, amount: newAmount, date: newDate ?? date, rate: newRate ?? rate, spends: spends)
    }
}

typealias RefsArray = [Ref]
typealias Balance = [Asset: RefsArray]

/**
 TODO: consolidate Refs without rate if they come from interests/bonus or other kinds of presents
       or maybe just track interest/bonus separately?

 TODO: alert if dust is significantly bigger than a rounding error, doesn't seem the case by inspecting the logs though
 */

func buildBalances(transactions: [Transaction], debug: Bool = false) -> [String: Balance] {
    //             [Wallet: Balance]
    var balances = [String: Balance]()
    for (index, group) in transactions.enumerated() {
        if debug {
            print(group)
        }

        if index % 500 == 0 {
            let topLevelRefsCount = balances.reduce(0) { $0 + $1.value.reduce(0) { $0 + $1.value.count }}
            print("\(index)/\(transactions.count) - \(topLevelRefsCount)")
        }

        switch group {
        case .single(let entry):
            // Ignore entries with amount 0
            guard entry.amount != 0 else {
                continue
            }

            var refs = balances[entry.wallet, default: Balance()][entry.asset, default: RefsArray()]
            if entry.amount > 0, entry.asset == BASE_ASSET {
                refs.append(Ref(refIds: [entry.globalId], asset: BASE_ASSET, amount: entry.amount, date: entry.date, rate: 1))
            } else if entry.amount > 0 {
                let rate = ledgersMeta[entry.globalId].flatMap { $0.rate }

                if let userProvidedRate = rate {
                    print("🚨🚨🚨 Using user-provided rate for \(entry), rate: \(userProvidedRate)")
                }

                refs.append(Ref(refIds: [entry.globalId], asset: entry.asset, amount: entry.amount, date: entry.date, rate: rate))
            } else {
                _ = subtract(refs: &refs, amount: -entry.amount)
            }
//            let groupedRefs = refs.reduce(into: [[Ref]]()) {
//                if let lastGroup = $0.last, !lastGroup.isEmpty, lastGroup[0].rate == $1.rate {
//                    $0[$0.count - 1].append($1)
//                } else {
//                    $0.append([$1])
//                }
//            }
//            walletBalance[entry.asset] = groupedRefs.map { refsGroup in
//                refsGroup[0].withAmount(refsGroup.sum)
//            }
//            print("balances", balances.count)
//            balances[entry.wallet] = walletBalance
            balances[entry.wallet, default: Balance()][entry.asset] = refs

        case .transfer(let from, let to):
            assert(from.amount != 0 && to.amount != 0, "invalid transfer amount \(from) -> \(to)")

            guard var fromRefs = balances[from.wallet]?[from.asset] else {
                fatalError("Transfer failed, \(from.wallet) balance is empty")
            }

            let subtractedRefs = subtract(refs: &fromRefs, amount: to.amount)
            balances[from.wallet, default: Balance()][from.asset] = fromRefs
            let groupedRefs = subtractedRefs.reduce(into: [[Ref]]()) {
                if let lastGroup = $0.last, !lastGroup.isEmpty, lastGroup[0].rate == $1.rate {
                    $0[$0.count - 1].append($1)
                } else {
                    $0.append([$1])
                }
            }
            balances[to.wallet, default: Balance()][to.asset, default: RefsArray()]
                .append(contentsOf: groupedRefs.map { refsGroup in
                    Ref(refIds: [from.globalId, to.globalId], asset: to.asset, amount: refsGroup.sum, date: refsGroup[0].date, rate: refsGroup[0].rate, spends: refsGroup)
                })

        case .trade(let spend, let receive):
            assert(spend.amount != 0 && receive.amount != 0, "invalid trade amount \(spend) -> \(receive)")

            let wallet = spend.wallet
            let rate = (-spend.amount / receive.amount)

            // Move refs to receive balance
            var refs = balances[wallet, default: Balance()][spend.asset, default: RefsArray()]
            refs.forEach { assert($0.amount > 0, "invalid ref before subtract \($0)") }
            let removedRefs = subtract(refs: &refs, amount: -spend.amount)
            refs.forEach { assert($0.amount > 0, "invalid ref after subtract \($0)") }
            removedRefs.forEach { assert($0.amount > 0, "invalid subtracted ref \($0)") }

            balances[wallet, default: Balance()][spend.asset] = refs

            if receive.asset == BASE_ASSET {
                balances[wallet, default: Balance()][receive.asset, default: RefsArray()].append(
                    Ref(
                        refIds: [spend.globalId, receive.globalId],
                        asset: BASE_ASSET,
                        amount: receive.amount,
                        date: receive.date,
                        rate: 1,
                        spends: removedRefs
                    )
                )
            } else {
                let groupedRefs = removedRefs.reduce(into: [[Ref]]()) {
                    if let lastGroup = $0.last, !lastGroup.isEmpty, lastGroup[0].rate == $1.rate {
                        $0[$0.count - 1].append($1)
                    } else {
                        $0.append([$1])
                    }
                }

                let precision = max(10, receive.amount.significantFractionalDecimalDigits)
                // Propagate rate to receive side, skipping the ones that result in rounding errors
                var receiveRefs = groupedRefs.compactMap { refsGroup -> Ref? in
                    let nextRate = refsGroup[0].rate.map { $0 * rate }.map { round($0, precision: precision) }
                    let nextAmount = round(refsGroup.sum / rate, precision: precision)

                    guard nextAmount > 0 else { return nil }

                    return Ref(
                        refIds: [spend.globalId, receive.globalId],
                        asset: receive.asset,
                        amount: nextAmount,
                        date: receive.date,
                        rate: nextRate,
                        spends: refsGroup
                    )
                }

                let dust = receive.amount - receiveRefs.sum
                // TODO: alert if dust is significantly bigger than a rounding error
                if dust > 0 {
                    guard let first = receiveRefs.first else {
                        fatalError("Cannot fix rounding error, no elements")
                    }

                    receiveRefs[0] = first.withAmount(first.amount + dust)
                } else if dust < 0 {
                    // Drop refs up to the dust amount
                    _ = subtract(refs: &receiveRefs, amount: -dust)
                }
                assert(receiveRefs.sum == receive.amount, "Trade balance update error, should be \(receive.amount), is \(receiveRefs.sum)")

                balances[wallet, default: Balance()][receive.asset, default: RefsArray()] += receiveRefs
            }
        }
    }

    return balances
}
