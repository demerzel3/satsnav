import Foundation

struct PortfolioHistoryItem: Codable {
    let date: Date
    let total: Decimal // Incl. bonus
    let bonus: Decimal
    let spent: Decimal
}

func utcCalendar() -> Calendar {
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone

    return calendar
}

func buildBtcHistory(balances: [String: Balance], getLedgerById: (String) -> LedgerEntry?) -> [PortfolioHistoryItem] {
    var allBtcRefs = balances.values.compactMap { $0[BTC] }.flatMap { $0 }.sorted { a, b in
        a.date < b.date
    }
    var total = allBtcRefs.sum
    var spent = allBtcRefs.compactMap { ref in ref.rate.map { $0 * ref.amount } }.reduce(0) { $0 + $1 }
    // TODO: restore bonus
//    var bonus = allBtcRefs.filter {
//        switch $0.transaction {
//        case let .single(entry) where entry.type == .bonus || entry.type == .interest:
//            return true
//        default:
//            return false
//        }
//    }.sum
    var entries = [PortfolioHistoryItem(date: Date.now, total: total, bonus: 0, spent: spent)]

    let calendar = utcCalendar()
    var date: Date? = calendar.startOfDay(for: Date.now)
    while let d = date, allBtcRefs.count > 0 {
        while let last = allBtcRefs.last, last.date >= d {
            total -= last.amount
            spent -= last.rate.map { $0 * last.amount } ?? 0
//            if case let .single(entry) = last.transaction, entry.type == .bonus || entry.type == .interest {
//                bonus -= last.amount
//            }
            _ = allBtcRefs.popLast()
        }
        entries.append(PortfolioHistoryItem(date: d, total: total, bonus: 0, spent: spent))
        // Go back one day and repeat
        date = calendar.date(byAdding: .init(day: -1), to: d)
    }

    return entries.reversed()
}
