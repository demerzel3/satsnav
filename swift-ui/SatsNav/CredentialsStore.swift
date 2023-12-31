import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case unableToCreateAccessControl
    case unableToEncodeCredentials
    case unableToDecodeCredentials
    case unableToCreateLocalStorageEncryptionKey
}

struct ApiKey: Codable {
    let key: String
    let secret: String
}

struct Credentials: Codable {
    // local storage encryption key
    let localStorageEncryptionKey: Data

    init() throws {
        // Generate local storage encryption key
        var key = Data(count: 64)
        let status = try key.withUnsafeMutableBytes { (pointer: UnsafeMutableRawBufferPointer) throws in
            guard let address = pointer.baseAddress else {
                throw KeychainError.unableToCreateLocalStorageEncryptionKey
            }
            return SecRandomCopyBytes(kSecRandomDefault, 64, address)
        }
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        localStorageEncryptionKey = key
    }
}

class CredentialsStore: ObservableObject {
    @Published var credentials: Credentials

    init() {
        credentials = try! loadOrCreate()
    }
}

private func save(_ credentials: Credentials) throws {
    guard let data = try? JSONEncoder().encode(credentials) else {
        throw KeychainError.unableToEncodeCredentials
    }

    let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .userPresence,
        nil
    )
    guard let access = accessControl else {
        throw KeychainError.unableToCreateAccessControl
    }

    let query = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: "credentials",
        kSecValueData: data,
        kSecAttrAccessControl: access,
    ] as CFDictionary

    SecItemDelete(query)
    let status = SecItemAdd(query, nil)
    guard status == errSecSuccess else {
        throw KeychainError.unexpectedStatus(status)
    }
}

private func loadOrCreate() throws -> Credentials {
    let query = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: "credentials",
        kSecReturnData: kCFBooleanTrue!,
        kSecMatchLimit: kSecMatchLimitOne,
    ] as CFDictionary

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query, &item)

    // Create when not found!!
    if status == errSecItemNotFound {
        let credentials = try Credentials()
        try save(credentials)

        return credentials
    }

    guard status == errSecSuccess else {
        throw KeychainError.unexpectedStatus(status)
    }

    guard let data = item as? Data,
          let credentials = try? JSONDecoder().decode(Credentials.self, from: data)
    else {
        throw KeychainError.unableToDecodeCredentials
    }

    return credentials
}
