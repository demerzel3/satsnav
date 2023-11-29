import Foundation

extension Decimal {
    var significantFractionalDecimalDigits: Int {
        return max(-exponent, 0)
    }
}
