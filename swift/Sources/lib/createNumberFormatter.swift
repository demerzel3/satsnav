import Foundation

func createNumberFormatter(minimumFractionDigits: Int, maximumFranctionDigits: Int) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFranctionDigits
    formatter.usesGroupingSeparator = true
    formatter.groupingSeparator = ","
    formatter.groupingSize = 3

    return formatter
}
