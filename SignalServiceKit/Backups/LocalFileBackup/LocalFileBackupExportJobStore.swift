//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct LocalFileBackupExportJobStore {

    private enum Keys {
        static let resumptionPoint = "resumptionPoint"
        static let currentBackupDirectoryName = "currentBackupDirectoryName"
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "LocalFileBackupExportJobStore")
    }

    // MARK: -

    public func wipe(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: Keys.resumptionPoint, tx: tx)
        kvStore.removeValue(forKey: Keys.currentBackupDirectoryName, tx: tx)
    }

    // MARK: -

    /// Represents a point at which an interrupted `LocalFileBackupExportJob` can be
    /// resumed. If nil, the job should be resumed from the beginning.
    public enum ResumptionPoint {
        /// The job should be resumed after backup file was copied to disk.
        case postBackupFileCopy(directoryName: String)
    }

    public func lastReachedResumptionPoint(tx: DBReadTransaction) -> ResumptionPoint? {
        guard let raw = kvStore.fetchValue(Int64.self, forKey: Keys.resumptionPoint, tx: tx) else {
            return nil
        }
        switch raw {
        case 0:
            guard let name = kvStore.fetchValue(String.self, forKey: Keys.currentBackupDirectoryName, tx: tx) else {
                owsFailDebug("postBackupFileCopy checkpoint missing directory name")
                return nil
            }
            return .postBackupFileCopy(directoryName: name)
        default:
            owsFailDebug("Unexpected resumption point raw value: \(raw)")
            return nil
        }
    }

    public func setReachedResumptionPoint(_ point: ResumptionPoint?, tx: DBWriteTransaction) {
        switch point {
        case nil:
            kvStore.removeValue(forKey: Keys.resumptionPoint, tx: tx)
            kvStore.removeValue(forKey: Keys.currentBackupDirectoryName, tx: tx)
        case .postBackupFileCopy(let name):
            kvStore.writeValue(Int64(0), forKey: Keys.resumptionPoint, tx: tx)
            kvStore.writeValue(name, forKey: Keys.currentBackupDirectoryName, tx: tx)
        }
    }

}
