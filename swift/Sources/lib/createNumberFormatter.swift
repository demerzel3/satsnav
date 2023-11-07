import Foundation

func createNumberFormatter(minimumFractionDigits: Int, maximumFranctionDigits: Int) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = minimumFractionDigits
    formatter.maximumFractionDigits = maximumFranctionDigits

    return formatter
}
