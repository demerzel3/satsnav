import Foundation

protocol CSVReader {
    func read(fileUrl: URL) async throws -> [LedgerEntry]
}

func readCSVFiles(config: [(CSVReader, String)]) async throws -> [LedgerEntry] {
    var entries = [LedgerEntry]()
    let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!

    try await withThrowingTaskGroup(of: [LedgerEntry].self) { group in
        for (reader, filePath) in config {
            group.addTask {
                try await reader.read(fileUrl: documentsDirectoryURL.appendingPathComponent(filePath))
            }
        }

        for try await fileEntries in group {
            entries.append(contentsOf: fileEntries)
        }
    }

    return entries
}
