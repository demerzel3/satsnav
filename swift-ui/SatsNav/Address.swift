import Foundation
import RealmSwift

final class Address: Object {
    @Persisted var id: String
    @Persisted var scriptHash: String

    // Consider two addresses to be the same if the id is the same
//    static func ==(lhs: Address, rhs: Address) -> Bool {
//        return lhs.id == rhs.id
//    }

    // Consider two addresses to be the same if the id is the same
    // func hash(into hasher: inout Hasher) {
    //     id.hash(into: &hasher)
    // }

    convenience init(id: String, scriptHash: String) {
        self.init()
        self.id = id
        self.scriptHash = scriptHash
    }
}
