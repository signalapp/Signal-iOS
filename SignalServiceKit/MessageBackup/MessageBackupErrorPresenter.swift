//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol MessageBackupErrorPresenterFactory {

    func build(
        db: any DB,
        tsAccountManager: TSAccountManager
    ) -> MessageBackupErrorPresenter
}

public protocol MessageBackupErrorPresenter {

    /// Persist a set of errors for future display.
    /// We persist because display may be deferred until certain UI actions occur (finishing registration)
    /// during which time the app may be interrupted.
    /// We only care to hold onto the latest set of backup errors.
    func persistErrors(_ errors: [MessageBackup.CollapsedErrorLog], tx: DBWriteTransaction)

    /// Persist a validation error for future display.
    /// We persist because display may be deferred until certain UI actions occur (finishing registration)
    /// during which time the app may be interrupted.
    /// We only care to hold onto the latest validation error.
    func persistValidationError(_ error: MessageBackupValidationError) async

    /// Present over the current view controller; calls completion when presentation has finished.
    func presentOverTopmostViewController(completion: @escaping () -> Void)
}

public class NoOpMessageBackupErrorPresenterFactory: MessageBackupErrorPresenterFactory {

    public init() {}

    public func build(
        db: any DB,
        tsAccountManager: TSAccountManager
    ) -> MessageBackupErrorPresenter {
        return NoOpMessageBackupErrorPresenter()
    }
}

public class NoOpMessageBackupErrorPresenter: MessageBackupErrorPresenter {

    public init() {}

    public func persistErrors(_ errors: [MessageBackup.CollapsedErrorLog], tx: any DBWriteTransaction) {
        // do nothing
    }

    public func persistValidationError(_ error: MessageBackupValidationError) async {
        // do nothing
    }

    public func presentOverTopmostViewController(completion: @escaping () -> Void) {
        // do nothing
    }
}
