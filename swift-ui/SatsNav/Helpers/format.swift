import Foundation

private func createNumberFormatter(minimumFractionDigits: Int, maximumFranctionDigits: Int) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFranctionDigits
    formatter.usesGroupingSeparator = true
    formatter.groupingSeparator = ","
    formatter.groupingSize = 3

    return formatter
}

let btcFormatter = createNumberFormatter(minimumFractionDigits: 8, maximumFranctionDigits: 8)
private let fiatFormatter = createNumberFormatter(minimumFractionDigits: 2, maximumFranctionDigits: 2)
private let cryptoRateFormatter = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 6)
private let fiatRateFormatter = createNumberFormatter(minimumFractionDigits: 0, maximumFranctionDigits: 2)

func formatRate(_ optionalRate: Decimal?, spendType: LedgerEntry.AssetType = .crypto) -> String {
    guard let rate = optionalRate else {
        return "unknown"
    }

    switch spendType {
    case .crypto: return cryptoRateFormatter.string(from: rate as NSNumber)!
    case .fiat: return fiatRateFormatter.string(from: rate as NSNumber)!
    }
}

func formatBtcAmount(_ amount: Decimal) -> String {
    return btcFormatter.string(from: amount as NSNumber)!
}

func formatFiatAmount(_ amount: Decimal) -> String {
    return fiatFormatter.string(from: amount as NSNumber)!
}

/**
 Convert Double to Decimal, truncating at the 8th decimal
 */
func readBtcAmount(_ amount: Double) -> Decimal {
    var decimalValue = Decimal(amount)
    var roundedValue = Decimal()
    NSDecimalRound(&roundedValue, &decimalValue, 8, .plain)

    return roundedValue
}
