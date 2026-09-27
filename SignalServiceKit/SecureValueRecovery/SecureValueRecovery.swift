//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import LibSignalClient

public enum SVR {

    static let maximumKeyAttempts: UInt32 = 10

    public enum KeysError: Error {
        case missingAep
        case missingMrbk
    }

    /// An auth credential is needed to talk to the SVR server.
    /// This defines how we should get that auth credential
    public indirect enum AuthMethod {
        /// Explicitly provide an auth credential to use directly with SVR.
        /// note: if it fails, will fall back to the backup or implicit if unset.
        case svrAuth(SVRAuthCredential, backup: AuthMethod?)
        /// Get an SVR auth credential from the chat server first with the
        /// provided credentials, then use it to talk to the SVR server.
        case chatServerAuth(AuthedAccount)
        /// Use whatever SVR auth credential we have cached; if unavailable or
        /// if invalid, falls back to getting a SVR auth credential from the chat server
        /// with the chat server auth credentials we have cached.
        case implicit
    }

    public enum RestoreKeysResult {
        case success(MasterKey)
        case invalidPin(remainingAttempts: UInt32)
        // This could mean there was never a backup, or it's been
        // deleted due to using up all pin attempts.
        case backupMissing
        case networkError(Error)
        // Some other issue.
        case genericError(Error)
    }
}

public protocol SecureValueRecovery {

    /// Performs pending backups, migrations, and deletions.
    func refreshBackupIfNecessary() async throws

    /// Performs periodic credential refresh to help with re-registration.
    func refreshCredentialsIfNecessary() async throws

    /// Loads the users key, if any, from the SVR into the database.
    func restoreKeys(pin: String, authMethod: SVR.AuthMethod) async -> SVR.RestoreKeysResult

    /// Backs up the user's master key to SVR.
    func backUpMasterKey(pin: String, masterKey: MasterKey, authMethod: SVR.AuthMethod) async throws

    /// Invalidates the status of all enclaves, thus ensuring that we'll
    /// reconcile what's stored in every enclave.
    func invalidateBackupAttemptForEveryEnclave(tx: DBWriteTransaction)

    func storeKeys(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) throws(SVR.KeysError)

    func storeKeys(
        fromProvisioningMessage provisioningMessage: LinkingProvisioningMessage,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    )
}
