import Foundation

let BASE_ASSET = Asset(name: "EUR", type: .fiat)

struct Ref: Identifiable, Equatable, Hashable {
    let id = UUID()
    let asset: Asset
    let amount: Decimal
    let date: Date
    let rate: Decimal?
}

struct BalanceChange: Identifiable {
    let id = UUID()
    let transaction: Transaction
    let changes: [RefChange]

    enum RefChange {
        case create(ref: Ref, wallet: String)
        case remove(ref: Ref, wallet: String)
        case move(ref: Ref, fromWallet: String, toWallet: String)
        case split(originalRef: Ref, resultingRefs: [Ref], wallet: String)
        case convert(fromRefs: [Ref], toRef: Ref, wallet: String)
    }
}

// struct Ref: Identifiable, Equatable, Hashable {
//    let id: UUID = .init()
//
//    let transaction: Transaction
//    let asset: Asset
//    let amount: Decimal
//    let date: Date
//    let rate: Decimal?
//    let spends: [Ref]
//
//    init(transaction: Transaction, asset: Asset, amount: Decimal, date: Date, rate: Decimal?, spends: [Ref]? = nil) {
//        self.transaction = transaction
//        self.asset = asset
//        self.amount = amount
//        self.date = date
//        self.rate = rate
//        self.spends = spends ?? []
//    }
// }

// Constructors
extension Ref {
    func withAmount(_ newAmount: Decimal, rate newRate: Decimal? = nil, date newDate: Date? = nil) -> Ref {
        assert(newAmount > 0, "Invalid amount \(newAmount)")
        return Ref(asset: asset, amount: newAmount, date: newDate ?? date, rate: newRate ?? rate)
    }
}

typealias RefsArray = [Ref]
typealias Balance = [Asset: RefsArray]

func buildBalances(transactions: [Transaction]) -> (balances: [String: Balance], changes: [BalanceChange]) {
    var balanceChanges: [BalanceChange] = []
    var currentBalances: [String: [Asset: RefsArray]] = [:]

    for transaction in transactions {
        var changes: [BalanceChange.RefChange] = []

        switch transaction {
        case .single(let entry):
            // TODO: we have a non-negligible amount of entries with 0 amount, maybe avoid ingesting them in the first place
            guard entry.amount != 0 else {
                continue
            }

            if entry.amount > 0, entry.asset == BASE_ASSET {
                let newRef = Ref(asset: entry.asset, amount: entry.amount, date: entry.date, rate: 1)
                changes.append(.create(ref: newRef, wallet: entry.wallet))
                currentBalances[entry.wallet, default: [:]][entry.asset, default: []].append(newRef)
            } else if entry.amount > 0 {
                let rate = ledgersMeta[entry.globalId].flatMap { $0.rate }

                if let userProvidedRate = rate {
                    print("🚨🚨🚨 Using user-provided rate for \(entry), rate: \(userProvidedRate)")
                }

                let newRef = Ref(asset: entry.asset, amount: entry.amount, date: entry.date, rate: rate)
                changes.append(.create(ref: newRef, wallet: entry.wallet))
                currentBalances[entry.wallet, default: [:]][entry.asset, default: []].append(newRef)
            } else {
                var refs = currentBalances[entry.wallet, default: [:]][entry.asset, default: []]
                let (removedRefs, splitInfo) = subtract(refs: &refs, amount: -entry.amount)
                if let split = splitInfo {
                    changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: entry.wallet))
                }
                changes.append(contentsOf: removedRefs.map { .remove(ref: $0, wallet: entry.wallet) })
                currentBalances[entry.wallet, default: [:]][entry.asset] = refs
            }

        case .transfer(let from, let to):
            assert(from.amount != 0 && to.amount != 0, "invalid transfer amount \(from) -> \(to)")

            guard var fromRefs = currentBalances[from.wallet]?[from.asset] else {
                fatalError("Transfer failed, \(from.wallet) balance is empty")
            }

            let (removedRefs, splitInfo) = subtract(refs: &fromRefs, amount: to.amount)
            if let split = splitInfo {
                changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: from.wallet))
            }
            changes.append(contentsOf: removedRefs.map { .move(ref: $0, fromWallet: from.wallet, toWallet: to.wallet) })
            currentBalances[from.wallet, default: [:]][from.asset] = fromRefs
            currentBalances[to.wallet, default: [:]][to.asset, default: []].append(contentsOf: removedRefs)

        case .trade(let spend, let receive):
            assert(spend.amount != 0 && receive.amount != 0, "invalid trade amount \(spend) -> \(receive)")

            let wallet = spend.wallet
            let rate = (-spend.amount / receive.amount)

            // Move refs to receive balance
            var refs = currentBalances[wallet, default: [:]][spend.asset, default: []]
            refs.forEach { assert($0.amount > 0, "invalid ref before subtract \($0)") }
            let (removedRefs, splitInfo) = subtract(refs: &refs, amount: -spend.amount)
            refs.forEach { assert($0.amount > 0, "invalid ref after subtract \($0)") }
            removedRefs.forEach { assert($0.amount > 0, "invalid subtracted ref \($0)") }

            currentBalances[wallet, default: Balance()][spend.asset] = refs

            if let split = splitInfo {
                changes.append(.split(originalRef: split.original, resultingRefs: [split.left, split.right], wallet: wallet))
            }

            if receive.asset == BASE_ASSET {
                let newRef = Ref(asset: BASE_ASSET, amount: receive.amount, date: receive.date, rate: 1)
                changes.append(.convert(fromRefs: removedRefs, toRef: newRef, wallet: wallet))
                currentBalances[wallet, default: [:]][receive.asset, default: []].append(
                    Ref(asset: BASE_ASSET, amount: receive.amount, date: receive.date, rate: 1)
                )
            } else {
                let precision = max(10, receive.amount.significantFractionalDecimalDigits)
                // Split refs between dust ones (conversion make them a rounding error) and actual ones
                let (nonDustRefs, dustRefs) = removedRefs.partition { ref in
                    let nextAmount = round(ref.amount / rate, precision: precision)

                    return nextAmount > 0
                }

                nonDustRefs.forEach { ref in
                    assert(round(ref.amount / rate, precision: precision) > 0)
                }

                // Register dust refs as removed
                changes.append(contentsOf: dustRefs.map { .remove(ref: $0, wallet: wallet) })

                // Propagate rate to receive side
                var receiveRefs = nonDustRefs.map { ref -> Ref in
                    // TODO: avoid doing amount calculation twice
                    let nextRate = ref.rate.map { $0 * rate }.map { round($0, precision: precision) }
                    let nextAmount = round(ref.amount / rate, precision: precision)

                    assert(nextAmount > 0, "Ok this should definitely never happen")

                    return Ref(asset: receive.asset, amount: nextAmount, date: receive.date, rate: nextRate)
                }

                receiveRefs.forEach {
                    assert($0.amount > 0, "Something went wrong with our friends the receiveRefs")
                }

                // There can still be some dust left
                let dust = receive.amount - receiveRefs.sum
                // TODO: alert if dust is significantly bigger than a rounding error
                if dust > 0 {
                    guard let first = receiveRefs.first else {
                        fatalError("Cannot fix rounding error, no elements")
                    }

                    // TODO: since there is now this dust amount, is the rate changed slightly?
                    receiveRefs[0] = first.withAmount(first.amount + dust)
                } else if dust < 0 {
                    // Drop refs up to the dust amount
                    _ = subtract(refs: &receiveRefs, amount: -dust)

                    receiveRefs.forEach {
                        assert($0.amount > 0, "Something went wrong with our friends the receiveRefs after subtract")
                    }
                }

                assert(receiveRefs.sum == receive.amount, "Trade balance update error, should be \(receive.amount), is \(receiveRefs.sum)")

                // Register conversions
                assert(receiveRefs.count == nonDustRefs.count, "Trade balance update error, removed \(nonDustRefs.count - receiveRefs.count) dust refs")
                changes.append(contentsOf: receiveRefs.enumerated().map { index, ref in
                    .convert(fromRefs: [nonDustRefs[index]], toRef: ref, wallet: wallet)
                })
                currentBalances[wallet, default: [:]][receive.asset, default: []] += receiveRefs
            }
        }

        assert(!changes.isEmpty, "Transaction resulted in no changes \(transaction)")
        balanceChanges.append(BalanceChange(transaction: transaction, changes: changes))
    }

    return (balances: currentBalances, changes: balanceChanges)
}

/**
 TODO: consolidate Refs without rate if they come from interests/bonus or other kinds of presents
       or maybe just track interest/bonus separately?

 TODO: alert if dust is significantly bigger than a rounding error, doesn't seem the case by inspecting the logs though
 */

// func buildBalances(transactions: [Transaction], debug: Bool = false) -> [String: Balance] {
//    //             [Wallet: Balance]
//    var balances = [String: Balance]()
//    for (index, transaction) in transactions.enumerated() {
//        if debug {
//            print(transaction)
//        }
//
//        if index % 500 == 0 {
//            let topLevelRefsCount = balances.reduce(0) { $0 + $1.value.reduce(0) { $0 + $1.value.count }}
//            print("\(index)/\(transactions.count) - \(topLevelRefsCount)")
//        }
//
//        switch transaction {
//        case .single(let entry):
//            // TODO: we have a non-negligible amount of entries with 0 amount, maybe avoid injesting them in the first place
//            guard entry.amount != 0 else {
//                continue
//            }
//
//            var refs = balances[entry.wallet, default: Balance()][entry.asset, default: RefsArray()]
//            if entry.amount > 0, entry.asset == BASE_ASSET {
//                refs.append(Ref(transaction: transaction, asset: BASE_ASSET, amount: entry.amount, date: entry.date, rate: 1))
//            } else if entry.amount > 0 {
//                let rate = ledgersMeta[entry.globalId].flatMap { $0.rate }
//
//                if let userProvidedRate = rate {
//                    print("🚨🚨🚨 Using user-provided rate for \(entry), rate: \(userProvidedRate)")
//                }
//
//                refs.append(Ref(transaction: transaction, asset: entry.asset, amount: entry.amount, date: entry.date, rate: rate))
//            } else {
//                _ = subtract(refs: &refs, amount: -entry.amount)
//            }
//            balances[entry.wallet, default: Balance()][entry.asset] = refs
//
//        case .transfer(let from, let to):
//            assert(from.amount != 0 && to.amount != 0, "invalid transfer amount \(from) -> \(to)")
//
//            guard var fromRefs = balances[from.wallet]?[from.asset] else {
//                fatalError("Transfer failed, \(from.wallet) balance is empty")
//            }
//
//            let subtractedRefs = subtract(refs: &fromRefs, amount: to.amount)
//            balances[from.wallet, default: Balance()][from.asset] = fromRefs
//            let groupedRefs = subtractedRefs.reduce(into: [[Ref]]()) {
//                if let lastGroup = $0.last, !lastGroup.isEmpty, lastGroup[0].rate == $1.rate {
//                    $0[$0.count - 1].append($1)
//                } else {
//                    $0.append([$1])
//                }
//            }
//            balances[to.wallet, default: Balance()][to.asset, default: RefsArray()]
//                .append(contentsOf: groupedRefs.map { refsGroup in
//                    Ref(transaction: transaction, asset: to.asset, amount: refsGroup.sum, date: refsGroup[0].date, rate: refsGroup[0].rate, spends: refsGroup)
//                })
//
//        case .trade(let spend, let receive):
//            assert(spend.amount != 0 && receive.amount != 0, "invalid trade amount \(spend) -> \(receive)")
//
//            let wallet = spend.wallet
//            let rate = (-spend.amount / receive.amount)
//
//            // Move refs to receive balance
//            var refs = balances[wallet, default: Balance()][spend.asset, default: RefsArray()]
//            refs.forEach { assert($0.amount > 0, "invalid ref before subtract \($0)") }
//            let removedRefs = subtract(refs: &refs, amount: -spend.amount)
//            refs.forEach { assert($0.amount > 0, "invalid ref after subtract \($0)") }
//            removedRefs.forEach { assert($0.amount > 0, "invalid subtracted ref \($0)") }
//
//            balances[wallet, default: Balance()][spend.asset] = refs
//
//            if receive.asset == BASE_ASSET {
//                balances[wallet, default: Balance()][receive.asset, default: RefsArray()].append(
//                    Ref(
//                        transaction: transaction,
//                        asset: BASE_ASSET,
//                        amount: receive.amount,
//                        date: receive.date,
//                        rate: 1,
//                        spends: removedRefs
//                    )
//                )
//            } else {
//                let groupedRefs = removedRefs.reduce(into: [[Ref]]()) {
//                    if let lastGroup = $0.last, !lastGroup.isEmpty, lastGroup[0].rate == $1.rate {
//                        $0[$0.count - 1].append($1)
//                    } else {
//                        $0.append([$1])
//                    }
//                }
//
//                let precision = max(10, receive.amount.significantFractionalDecimalDigits)
//                // Propagate rate to receive side, skipping the ones that result in rounding errors
//                var receiveRefs = groupedRefs.compactMap { refsGroup -> Ref? in
//                    let nextRate = refsGroup[0].rate.map { $0 * rate }.map { round($0, precision: precision) }
//                    let nextAmount = round(refsGroup.sum / rate, precision: precision)
//
//                    guard nextAmount > 0 else { return nil }
//
//                    return Ref(
//                        transaction: transaction,
//                        asset: receive.asset,
//                        amount: nextAmount,
//                        date: receive.date,
//                        rate: nextRate,
//                        spends: refsGroup
//                    )
//                }
//
//                let dust = receive.amount - receiveRefs.sum
//                // TODO: alert if dust is significantly bigger than a rounding error
//                if dust > 0 {
//                    guard let first = receiveRefs.first else {
//                        fatalError("Cannot fix rounding error, no elements")
//                    }
//
//                    receiveRefs[0] = first.withAmount(first.amount + dust)
//                } else if dust < 0 {
//                    // Drop refs up to the dust amount
//                    _ = subtract(refs: &receiveRefs, amount: -dust)
//                }
//                assert(receiveRefs.sum == receive.amount, "Trade balance update error, should be \(receive.amount), is \(receiveRefs.sum)")
//
//                balances[wallet, default: Balance()][receive.asset, default: RefsArray()] += receiveRefs
//            }
//        }
//    }
//
//    return balances
// }
