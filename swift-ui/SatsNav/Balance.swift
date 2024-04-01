import Foundation

private let BASE_ASSET = Asset(name: "EUR", type: .fiat)

struct Ref: Identifiable, Equatable {
    var id: String {
        refIds.joined()
    }

    let refIds: [String]
    let amount: Decimal
    let date: Date
    let rate: Decimal?
    let spends: [Ref]

    init(refIds: [String], amount: Decimal, date: Date, rate: Decimal?, spends: [Ref]? = nil) {
        self.refIds = refIds
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
        return Ref(refIds: refIds, amount: newAmount, date: newDate ?? date, rate: newRate ?? rate)
    }

    func withAppendedRefs(_ newRefIds: String...) -> Ref {
        return Ref(refIds: refIds + newRefIds, amount: amount, date: date, rate: rate)
    }
}

typealias RefsArray = [Ref]
typealias Balance = [Asset: RefsArray]

/**
 TODO: consolidate Refs without rate if they come from interests/bonus or other kinds of presents
       or maybe just track interest/bonus separately?

 TODO: alert if dust is significantly bigger than a rounding error, doesn't seem the case by inspecting the logs though
 */

func buildBalances(groupedLedgers: [GroupedLedger], debug: Bool = false) -> [String: Balance] {
    //             [Wallet: Balance]
    var balances = [String: Balance]()
    for (index, group) in groupedLedgers.enumerated() {
        if debug {
            print(group)
        }

        if index % 10 == 0 {
            print("\(index)/\(groupedLedgers.count)")
        }

        switch group {
        case .single(let entry):
            // Ignore entries with amount 0
            guard entry.amount != 0 else {
                continue
            }

            var refs = balances[entry.wallet, default: Balance()][entry.asset, default: RefsArray()]
            if entry.amount > 0, entry.asset == BASE_ASSET {
                refs.append(Ref(refIds: [entry.globalId], amount: entry.amount, date: entry.date, rate: 1))
            } else if entry.amount > 0 {
                let rate = ledgersMeta[entry.globalId].flatMap { $0.rate }

                if let userProvidedRate = rate {
                    print("🚨🚨🚨 Using user-provided rate for \(entry), rate: \(userProvidedRate)")
                }

                refs.append(Ref(refIds: [entry.globalId], amount: entry.amount, date: entry.date, rate: rate))
            } else {
                _ = subtract(refs: &refs, amount: -entry.amount)
            }
            balances[entry.wallet, default: Balance()][entry.asset] = refs

        case .transfer(let from, let to):
            assert(from.amount != 0 && to.amount != 0, "invalid transfer amount \(from) -> \(to)")

            guard var fromRefs = balances[from.wallet]?[from.asset] else {
                fatalError("Transfer failed, \(from.wallet) balance is empty")
            }

            let subtractedRefs = subtract(refs: &fromRefs, amount: to.amount)
            balances[from.wallet, default: Balance()][from.asset] = fromRefs
//            balances[to.wallet, default: Balance()][to.asset, default: RefsArray()]
//                .append(contentsOf: subtractedRefs.map { $0.withAppendedRefs(from.globalId, to.globalId) })
            balances[to.wallet, default: Balance()][to.asset, default: RefsArray()]
                .append(contentsOf: subtractedRefs.map {
                    Ref(refIds: [from.globalId, to.globalId], amount: $0.amount, date: $0.date, rate: $0.rate, spends: [$0])
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

            let precision = max(10, receive.amount.significantFractionalDecimalDigits)
            // Propagate rate to receive side, skipping the ones that result in rounding errors
            var receiveRefs = removedRefs.compactMap { ref -> Ref? in
                let nextRate = ref.rate.map { $0 * rate }
                let nextAmount = round(ref.amount / rate, precision: precision)

                guard nextAmount > 0 else { return nil }

//                return ref
//                    .withAmount(nextAmount, rate: nextRate, date: receive.date)
//                    .withAppendedRefs(spend.globalId, receive.globalId)
                return Ref(
                    refIds: [spend.globalId, receive.globalId],
                    amount: nextAmount,
                    date: receive.date,
                    rate: nextRate,
                    spends: [ref]
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

            let allReceiveRefs = balances[wallet, default: Balance()][receive.asset, default: RefsArray()] + receiveRefs
            balances[wallet, default: Balance()][receive.asset] = allReceiveRefs
        }
    }

    return balances
}
