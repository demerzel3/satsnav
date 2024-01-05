import RealmSwift

final class ServiceAccount: Object {
    @Persisted(primaryKey: true) var provider: String
    @Persisted var apiKey: String
    @Persisted var apiSecret: String

    convenience init(provider: String, apiKey: String, apiSecret: String) {
        self.init()
        self.provider = provider
        self.apiKey = apiKey
        self.apiSecret = apiSecret
    }
}
