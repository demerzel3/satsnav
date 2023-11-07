import Foundation

struct Address: Hashable {
    let id: String
    let scriptHash: String

    // Consider two addresses to be the same if the id is the same
    static func ==(lhs: Address, rhs: Address) -> Bool {
        return lhs.id == rhs.id
    }

    // Consider two addresses to be the same if the id is the same
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}
