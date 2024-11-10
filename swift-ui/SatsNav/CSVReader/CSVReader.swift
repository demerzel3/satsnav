import Foundation

protocol CSVReader {
    func read(fileUrl: URL) async throws -> [LedgerEntry]
}
