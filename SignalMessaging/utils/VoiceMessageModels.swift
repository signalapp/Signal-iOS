//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class VoiceMessageModels: NSObject {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private override init() {}

    @objc
    public static let draftVoiceMessageDirectory = URL(
        fileURLWithPath: "draft-voice-messages",
        isDirectory: true,
        relativeTo: URL(
            fileURLWithPath: CurrentAppContext().appSharedDataDirectoryPath(),
            isDirectory: true
        )
    )

    // MARK: -

    public static func directory(for threadUniqueId: String) -> URL {
        return URL(
            fileURLWithPath: threadUniqueId.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!,
            isDirectory: true,
            relativeTo: Self.draftVoiceMessageDirectory
        )
    }

    // MARK: -

    public static var keyValueStore: SDSKeyValueStore { .init(collection: "DraftVoiceMessage") }

    @objc(hasDraftForThread:transaction:)
    public static func hasDraft(for thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        hasDraft(for: thread.uniqueId, transaction: transaction)
    }
    @objc(hasDraftForThreadUniqueId:transaction:)
    public static func hasDraft(for threadUniqueId: String, transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(threadUniqueId, defaultValue: false, transaction: transaction)
    }

    @objc
    public static func allDraftFilePaths(transaction: SDSAnyReadTransaction) -> Set<String> {
        return Set(keyValueStore.allKeys(transaction: transaction).compactMap { threadUniqueId in
            try? OWSFileSystem.recursiveFilesInDirectory(directory(for: threadUniqueId).path)
        }.reduce([], +))
    }

    @objc(clearDraftForThread:transaction:)
    public static func clearDraft(for thread: TSThread, transaction: SDSAnyWriteTransaction) {
        clearDraft(for: thread.uniqueId, transaction: transaction)
    }
    @objc(clearDraftForThreadUniqueId:transaction:)
    public static func clearDraft(for threadUniqueId: String, transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: threadUniqueId, transaction: transaction)
        transaction.addAsyncCompletionOffMain {
            do {
                try OWSFileSystem.deleteFileIfExists(url: Self.directory(for: threadUniqueId))
            } catch {
                owsFailDebug("Failed to delete voice memo draft")
            }
        }
    }

    @objc
    public static func saveDraft(threadUniqueId: String, transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setBool(true, key: threadUniqueId, transaction: transaction)
    }
}
