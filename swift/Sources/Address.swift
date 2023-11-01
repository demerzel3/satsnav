import Foundation

struct Address: Hashable {
    let id: String
    let scriptHash: String
    // Path explains how this address was added to the internal addresses, going backwards
    // It's a mix of txids and addresses ids... not sure if it makes sense but we'll see
    let path: [String]

    init(id: String, scriptHash: String, path: [String] = []) {
        self.id = id
        self.scriptHash = scriptHash
        self.path = path
    }

    // Consider two addresses to be the same if the id is the same
    static func ==(lhs: Address, rhs: Address) -> Bool {
        return lhs.id == rhs.id
    }

    // Consider two addresses to be the same if the id is the same
    func hash(into hasher: inout Hasher) {
        id.hash(into: &hasher)
    }
}
