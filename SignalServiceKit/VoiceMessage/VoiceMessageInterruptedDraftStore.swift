//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class VoiceMessageInterruptedDraftStore {

    private init() { }

    public static let draftVoiceMessageDirectory = URL(
        fileURLWithPath: "draft-voice-messages",
        isDirectory: true,
        relativeTo: URL(
            fileURLWithPath: CurrentAppContext().appSharedDataDirectoryPath(),
            isDirectory: true,
        ),
    )

    public enum Constants {
        public static let audioFilename = "voice-memo.\(VoiceMessageConstants.fileExtension)"
        public static let waveformFilename = "waveform.dat"
    }

    // MARK: -

    private static func directoryUrl(relativePath: String) -> URL {
        return URL(fileURLWithPath: relativePath, isDirectory: true, relativeTo: Self.draftVoiceMessageDirectory)
    }

    private static func directoryPath(threadUniqueId: String, transaction: DBReadTransaction) -> String? {
        keyValueStore.getString(threadUniqueId, transaction: transaction)
    }

    public static func directoryUrl(threadUniqueId: String, transaction: DBReadTransaction) -> URL? {
        guard let relativePath = directoryPath(threadUniqueId: threadUniqueId, transaction: transaction) else {
            return nil
        }
        return directoryUrl(relativePath: relativePath)
    }

    // MARK: -

    private static var keyValueStore: KeyValueStore { .init(collection: "DraftVoiceMessage") }

    public static func hasDraft(for thread: TSThread, transaction: DBReadTransaction) -> Bool {
        hasDraft(for: thread.uniqueId, transaction: transaction)
    }

    public static func hasDraft(for threadUniqueId: String, transaction: DBReadTransaction) -> Bool {
        keyValueStore.getString(threadUniqueId, transaction: transaction) != nil
    }

    public static func allDraftFilePaths(transaction: DBReadTransaction) -> Set<String> {
        return Set(keyValueStore.allKeys(transaction: transaction).compactMap { threadUniqueId -> [String]? in
            guard let directoryPath = self.directoryPath(threadUniqueId: threadUniqueId, transaction: transaction) else {
                return nil
            }
            return [
                directoryPath.appendingPathComponent(Constants.audioFilename),
                directoryPath.appendingPathComponent(Constants.waveformFilename),
            ]
        }.reduce([], +))
    }

    public static func clearDraft(for thread: TSThread, transaction: DBWriteTransaction) {
        clearDraft(for: thread.uniqueId, transaction: transaction)
    }

    public static func clearDraft(for threadUniqueId: String, transaction: DBWriteTransaction) {
        if let directoryUrl = self.directoryUrl(threadUniqueId: threadUniqueId, transaction: transaction) {
            do {
                try OWSFileSystem.deleteFileIfExists(url: directoryUrl)
            } catch {
                owsFailDebug("Failed to delete voice memo draft")
            }
        }
        keyValueStore.removeValue(forKey: threadUniqueId, transaction: transaction)
    }

    public static func saveDraft(audioFileUrl: URL, threadUniqueId: String, transaction: DBWriteTransaction) -> URL {
        let relativeDirectoryPath = UUID().uuidString
        keyValueStore.setString(relativeDirectoryPath, key: threadUniqueId, transaction: transaction)
        let directoryUrl = directoryUrl(relativePath: relativeDirectoryPath)
        do {
            OWSFileSystem.ensureDirectoryExists(directoryUrl.path)
            try OWSFileSystem.moveFile(from: audioFileUrl, to: directoryUrl.appendingPathComponent(Constants.audioFilename))
        } catch {
            owsFailDebug("Failed to move voice memo draft")
        }
        return directoryUrl
    }
}
