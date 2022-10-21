// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB

// MARK: - Migration Safe Functions

public extension MutablePersistableRecord where Self: TableRecord & EncodableRecord & Codable {
    func migrationSafeInsert(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil
    ) throws {
        var record = try MigrationSafeMutableRecord(db, originalRecord: self)
        try record.insert(db, onConflict: conflictResolution)
    }
    
    func migrationSafeInserted(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil
    ) throws -> Self {
        let record = try MigrationSafeMutableRecord(db, originalRecord: self)
        let updatedRecord = try record.inserted(db, onConflict: conflictResolution)
        return updatedRecord.originalRecord
    }
    
    func migrationSafeSave(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil
    ) throws {
        var record = try MigrationSafeMutableRecord(db, originalRecord: self)
        try record.save(db, onConflict: conflictResolution)
    }
    
    func migrationSafeSaved(
        _ db: Database,
        onConflict conflictResolution: Database.ConflictResolution? = nil
    ) throws -> Self {
        let record = try MigrationSafeMutableRecord(db, originalRecord: self)
        let updatedRecord = try record.saved(db, onConflict: conflictResolution)
        return updatedRecord.originalRecord
    }
    
    func migrationSafeUpsert(_ db: Database) throws {
        var record = try MigrationSafeMutableRecord(db, originalRecord: self)
        try record.upsert(db)
    }
}

// MARK: - MigrationSafeMutableRecord

private class MigrationSafeRecord<T: PersistableRecord & Encodable>: MigrationSafeMutableRecord<T> {}

private class MigrationSafeMutableRecord<T: MutablePersistableRecord & Encodable>: MutablePersistableRecord & Encodable {
    public static var databaseTableName: String { T.databaseTableName }
    
    fileprivate var originalRecord: T
    private let availableColumnNames: [String]
    
    init(_ db: Database, originalRecord: T) throws {
        // Check the current columns in the database and filter out any properties on the object which
        // don't exist in the dictionary
        self.originalRecord = originalRecord
        self.availableColumnNames = try db.columns(in: Self.databaseTableName).map(\.name)
    }
    
    func encode(to encoder: Encoder) throws {
        let filteredEncoder: FilteredEncoder = FilteredEncoder(
            originalEncoder: encoder,
            availableKeys: availableColumnNames
        )
        try originalRecord.encode(to: filteredEncoder)
    }
    
    // MARK: - Persistence Callbacks
    
    func willInsert(_ db: Database) throws {
        try originalRecord.willInsert(db)
    }
    
    func aroundInsert(_ db: Database, insert: () throws -> InsertionSuccess) throws {
        try originalRecord.aroundInsert(db, insert: insert)
    }
    
    func didInsert(_ inserted: InsertionSuccess) {
        originalRecord.didInsert(inserted)
    }
    
    func willUpdate(_ db: Database, columns: Set<String>) throws {
        try originalRecord.willUpdate(db, columns: columns)
    }
    
    func aroundUpdate(_ db: Database, columns: Set<String>, update: () throws -> PersistenceSuccess) throws {
        try originalRecord.aroundUpdate(db, columns: columns, update: update)
    }
    
    func didUpdate(_ updated: PersistenceSuccess) {
        originalRecord.didUpdate(updated)
    }
    
    func willSave(_ db: Database) throws {
        try originalRecord.willSave(db)
    }
    
    func aroundSave(_ db: Database, save: () throws -> PersistenceSuccess) throws {
        try originalRecord.aroundSave(db, save: save)
    }
    
    func didSave(_ saved: PersistenceSuccess) {
        originalRecord.didSave(saved)
    }
    
    func willDelete(_ db: Database) throws {
        try originalRecord.willDelete(db)
    }
    
    func aroundDelete(_ db: Database, delete: () throws -> Bool) throws {
        try originalRecord.aroundDelete(db, delete: delete)
    }
    
    func didDelete(deleted: Bool) {
        originalRecord.didDelete(deleted: deleted)
    }
}

// MARK: - FilteredEncoder

private class FilteredEncoder: Encoder {
    let originalEncoder: Encoder
    let availableKeys: [String]
    
    init(originalEncoder: Encoder, availableKeys: [String]) {
        self.originalEncoder = originalEncoder
        self.availableKeys = availableKeys
    }
    
    var codingPath: [CodingKey] { originalEncoder.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { originalEncoder.userInfo }
    
    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = originalEncoder.container(keyedBy: type)
        let filteredContainer = FilteredKeyedEncodingContainer(
            availableKeys: availableKeys,
            originalContainer: container
        )
        
        return KeyedEncodingContainer(filteredContainer)
    }
    
    func unkeyedContainer() -> UnkeyedEncodingContainer { originalEncoder.unkeyedContainer() }
    func singleValueContainer() -> SingleValueEncodingContainer { originalEncoder.singleValueContainer() }
}

// MARK: - FilteredKeyedEncodingContainer

private class FilteredKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let codingPath: [CodingKey]
    let availableKeys: [String]
    var originalContainer: KeyedEncodingContainer<Key>
    
    init(availableKeys: [String], originalContainer: KeyedEncodingContainer<Key>) {
        self.availableKeys = availableKeys
        self.codingPath = originalContainer.codingPath
        self.originalContainer = originalContainer
    }
    
    func encodeNil(forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encodeNil(forKey: key)
    }
    
    func encode(_ value: Bool, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: String, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Double, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Float, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Int, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Int8, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Int16, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Int32, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: Int64, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: UInt, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: UInt8, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: UInt16, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: UInt32, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode(_ value: UInt64, forKey key: Key) throws {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        guard availableKeys.contains(key.stringValue) else { return }
        
        try originalContainer.encode(value, forKey: key)
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        return originalContainer.nestedContainer(keyedBy: keyType, forKey: key)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        return originalContainer.nestedUnkeyedContainer(forKey: key)
    }
    
    func superEncoder() -> Encoder {
        return originalContainer.superEncoder()
    }
    
    func superEncoder(forKey key: Key) -> Encoder {
        return originalContainer.superEncoder(forKey: key)
    }
}
