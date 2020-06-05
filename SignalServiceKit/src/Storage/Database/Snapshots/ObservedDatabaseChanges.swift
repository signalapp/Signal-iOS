//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

// Our observers collect "pending" and "committed" database state.
// This struct DRYs up a bunch of that handling, especially around
// thread safety.
//
// NOTE: Different observers collect different kinds of state.
// Not all observers will update all of the properties below.
//
// ModelId: Some observers use RowIds, some use uniqueIds.
struct ObservedDatabaseChanges<ModelId: Hashable> {
    enum ConcurrencyMode {
        case mainThread
        case uiDatabaseObserverSerialQueue
    }
    private let concurrencyMode: ConcurrencyMode
    private func checkConcurrency() {
        switch concurrencyMode {
        case .mainThread:
            AssertIsOnMainThread()
        case .uiDatabaseObserverSerialQueue:
            AssertIsOnUIDatabaseObserverSerialQueue()
        }
    }

    init(concurrencyMode: ConcurrencyMode) {
        self.concurrencyMode = concurrencyMode
    }

    // MARK: - Collections

    private var _collections: Set<String> = Set()

    mutating func append(collection: String) {
        append(collections: [collection])
    }

    mutating func append(collections: Set<String>) {
        checkConcurrency()
        _collections.formUnion(collections)
    }

    var collections: Set<String> {
        get {
            checkConcurrency()
            return _collections
        }
    }

    // MARK: - Table Names

    private var _tableNames: Set<String> = Set()

    mutating func append(tableName: String) {
        append(tableNames: [tableName])
    }

    mutating func append(tableNames: Set<String>) {
        checkConcurrency()
        _tableNames.formUnion(tableNames)
    }

    var tableNames: Set<String> {
        get {
            checkConcurrency()
            return _tableNames
        }
    }

    // MARK: - Threads

    private var _threadChanges = Set<ModelId>()

    mutating func append(threadChange: ModelId) {
        append(threadChanges: [threadChange])
    }

    mutating func append(threadChanges: Set<ModelId>) {
        checkConcurrency()
        _threadChanges.formUnion(threadChanges)
    }

    var threadChanges: Set<ModelId> {
        get {
            checkConcurrency()
            return _threadChanges
        }
    }

    // MARK: - Interactions

    private var _interactionChanges = Set<ModelId>()

    mutating func append(interactionChange: ModelId) {
        append(interactionChanges: [interactionChange])
    }

    mutating func append(interactionChanges: Set<ModelId>) {
        checkConcurrency()
        _interactionChanges.formUnion(interactionChanges)
    }

    var interactionChanges: Set<ModelId> {
        get {
            checkConcurrency()
            return _interactionChanges
        }
    }

    // MARK: - Attachments

    private var _attachmentChanges = Set<ModelId>()

    mutating func append(attachmentChange: ModelId) {
        append(attachmentChanges: [attachmentChange])
    }

    mutating func append(attachmentChanges: Set<ModelId>) {
        checkConcurrency()
        _attachmentChanges.formUnion(attachmentChanges)
    }

    var attachmentChanges: Set<ModelId> {
        get {
            checkConcurrency()
            return _attachmentChanges
        }
    }

    // MARK: - Errors

    mutating func setLastError(_ error: Error) {
        checkConcurrency()
        _lastError = error
    }

    private var _lastError: Error?
    var lastError: Error? {
        get {
            checkConcurrency()
            return _lastError
        }
    }

    // MARK: -

    mutating func reset() {
        checkConcurrency()

        _collections.removeAll()
        _tableNames.removeAll()
        _threadChanges.removeAll()
        _interactionChanges.removeAll()
        _attachmentChanges.removeAll()
        _lastError = nil
    }
}
