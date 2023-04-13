//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

#if TESTABLE_BUILD

struct InMemoryDatabase {
    private let inMemoryDatabase: DatabaseQueue = {
        let result = DatabaseQueue()
        let schemaUrl = Bundle(for: GRDBSchemaMigrator.self).url(forResource: "schema", withExtension: "sql")!
        try! result.write { try $0.execute(sql: try String(contentsOf: schemaUrl)) }
        return result
    }()

    // MARK: - Read

    func read<T>(block: (Database) -> T) -> T {
        return try! inMemoryDatabase.read(block)
    }

    func fetchExactlyOne<T: SDSCodableModel>(modelType: T.Type) -> T? {
        let all = try! inMemoryDatabase.read { try modelType.fetchAll($0) }
        guard all.count == 1 else { return nil }
        return all.first!
    }

    // MARK: - Write

    func insert<T: SDSCodableModel>(record: T) {
        try! inMemoryDatabase.write { try record.insert($0) }
    }

    func update<T: SDSCodableModel>(record: T) {
        try! inMemoryDatabase.write { try record.update($0) }
    }

    // MARK: - Delete

    func remove<T: SDSCodableModel>(model: T) {
        _ = try! inMemoryDatabase.write { try model.delete($0) }
    }
}

#endif
