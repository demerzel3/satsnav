import CryptoKit
import Foundation

private func hexToData(_ input: String) -> Data? {
    var data = Data(capacity: input.count / 2)
    var index = input.startIndex
    while index < input.endIndex {
        let nextIndex = input.index(index, offsetBy: 2)
        if let byte = UInt8(input[index ..< nextIndex], radix: 16) {
            data.append(byte)
        } else {
            return nil
        }
        index = nextIndex
    }
    return data
}

private func sha256(_ data: Data) -> String {
    let hash = SHA256.hash(data: data).reversed()
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

func getScriptHashForElectrum(_ scriptPubKey: ElectrumTransaction.ScriptPubKey) -> String? {
    guard let data = hexToData(scriptPubKey.hex) else { return nil }

    return sha256(data)
}
