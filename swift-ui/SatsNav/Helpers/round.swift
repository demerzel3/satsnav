import Foundation

func round(_ value: Decimal, precision: Int, mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
    var decimalValue = value
    var roundedValue = Decimal()
    NSDecimalRound(&roundedValue, &decimalValue, precision, mode)

    return roundedValue
}
