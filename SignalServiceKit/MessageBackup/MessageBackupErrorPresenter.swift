//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol MessageBackupErrorPresenterFactory {

    func build(
        appReadiness: AppReadiness,
        db: any DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        tsAccountManager: TSAccountManager
    ) -> MessageBackupErrorPresenter
}

public protocol MessageBackupErrorPresenter {

    /// Persist a set of errors for future display.
    /// We persist because display may be deferred until certain UI actions occur (finishing registration)
    /// during which time the app may be interrupted.
    /// We only care to hold onto the latest set of backup errors.
    func persistErrors(_ errors: [MessageBackup.CollapsedErrorLog], tx: DBWriteTransaction)

    /// Force presentation during registration; calls completion when presentation has finished.
    func forcePresentDuringRegistration(completion: @escaping () -> Void)
}

public class NoOpMessageBackupErrorPresenterFactory: MessageBackupErrorPresenterFactory {

    public init() {}

    public func build(
        appReadiness: AppReadiness,
        db: any DB,
        keyValueStoreFactory: KeyValueStoreFactory,
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

    public func forcePresentDuringRegistration(completion: @escaping () -> Void) {
        // do nothing
    }
}
