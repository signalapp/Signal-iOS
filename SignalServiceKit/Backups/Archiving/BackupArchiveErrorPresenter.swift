//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol BackupArchiveErrorPresenterFactory {

    func build(
        db: any DB,
        tsAccountManager: TSAccountManager,
    ) -> BackupArchiveErrorPresenter
}

public protocol BackupArchiveErrorPresenter {

    /// Persist a set of errors for future display.
    /// We persist because display may be deferred until certain UI actions occur (finishing registration)
    /// during which time the app may be interrupted.
    /// We only care to hold onto the latest set of backup errors.
    func persistErrors(_ errors: [BackupArchive.CollapsedErrorLog], didFail: Bool, tx: DBWriteTransaction)

    /// Persist a validation error for future display.
    /// We persist because display may be deferred until certain UI actions occur (finishing registration)
    /// during which time the app may be interrupted.
    /// We only care to hold onto the latest validation error.
    func persistValidationError(_ error: MessageBackupValidationError) async

    /// Present over the current view controller; calls completion when presentation has finished.
    func presentOverTopmostViewController(completion: @escaping () -> Void)
}

public class NoOpBackupArchiveErrorPresenterFactory: BackupArchiveErrorPresenterFactory {

    public init() {}

    public func build(
        db: any DB,
        tsAccountManager: TSAccountManager,
    ) -> BackupArchiveErrorPresenter {
        return NoOpBackupArchiveErrorPresenter()
    }
}

public class NoOpBackupArchiveErrorPresenter: BackupArchiveErrorPresenter {

    public init() {}

    public func persistErrors(_ errors: [BackupArchive.CollapsedErrorLog], didFail: Bool, tx: DBWriteTransaction) {
        // do nothing
    }

    public func persistValidationError(_ error: MessageBackupValidationError) async {
        // do nothing
    }

    public func presentOverTopmostViewController(completion: @escaping () -> Void) {
        // do nothing
    }
}
