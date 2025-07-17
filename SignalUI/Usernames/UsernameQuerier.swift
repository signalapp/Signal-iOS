//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public struct UsernameQuerier {
    private let contactsManager: any ContactManager
    private let databaseStorage: SDSDatabaseStorage
    private let localUsernameManager: LocalUsernameManager
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let recipientManager: any SignalRecipientManager
    private let recipientFetcher: RecipientFetcher
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let usernameApiClient: UsernameApiClient
    private let usernameLinkManager: UsernameLinkManager
    private let usernameLookupManager: UsernameLookupManager

    public init() {
        self.init(
            contactsManager: SSKEnvironment.shared.contactManagerRef,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            localUsernameManager: DependenciesBridge.shared.localUsernameManager,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            profileManager: SSKEnvironment.shared.profileManagerRef,
            recipientManager: DependenciesBridge.shared.recipientManager,
            recipientFetcher: DependenciesBridge.shared.recipientFetcher,
            storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            usernameApiClient: DependenciesBridge.shared.usernameApiClient,
            usernameLinkManager: DependenciesBridge.shared.usernameLinkManager,
            usernameLookupManager: DependenciesBridge.shared.usernameLookupManager
        )
    }

    public init(
        contactsManager: any ContactManager,
        databaseStorage: SDSDatabaseStorage,
        localUsernameManager: LocalUsernameManager,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        recipientManager: any SignalRecipientManager,
        recipientFetcher: RecipientFetcher,
        storageServiceManager: StorageServiceManager,
        tsAccountManager: TSAccountManager,
        usernameApiClient: UsernameApiClient,
        usernameLinkManager: UsernameLinkManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.contactsManager = contactsManager
        self.databaseStorage = databaseStorage
        self.localUsernameManager = localUsernameManager
        self.networkManager = networkManager
        self.profileManager = profileManager
        self.recipientManager = recipientManager
        self.recipientFetcher = recipientFetcher
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.usernameApiClient = usernameApiClient
        self.usernameLinkManager = usernameLinkManager
        self.usernameLookupManager = usernameLookupManager
    }

    @MainActor
    public func queryForUsernameLink(
        link: Usernames.UsernameLink,
        fromViewController: UIViewController,
        tx: DBReadTransaction,
        failureSheetDismissalDelegate: (any SheetDismissalDelegate)? = nil,
        onSuccess: @escaping (_ username: String, _ aci: Aci) -> Void
    ) {
        let usernameState = localUsernameManager.usernameState(tx: tx)
        if
            let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci,
            let localLink = usernameState.usernameLink,
            let localUsername = usernameState.username,
            localLink == link
        {
            queryMatchedLocalUser(
                onSuccess: { onSuccess(localUsername, $0) },
                localAci: localAci,
                tx: tx
            )
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: true,
            asyncBlock: { modal in
                do {
                    let username = try await usernameLinkManager.decryptEncryptedLink(link: link)
                    guard let username else {
                        modal.dismissIfNotCanceled {
                            showUsernameLinkOutdatedError(dismissalDelegate: failureSheetDismissalDelegate)
                        }
                        return
                    }

                    guard let hashedUsername = try? Usernames.HashedUsername(
                        forUsername: username
                    ) else {
                        modal.dismissIfNotCanceled {
                            showInvalidUsernameError(username: username, dismissalDelegate: failureSheetDismissalDelegate)
                        }
                        return
                    }

                    let usernameAci = try await queryServiceForUsername(hashedUsername: hashedUsername)
                    modal.dismissIfNotCanceled {
                        onSuccess(hashedUsername.usernameString, usernameAci)
                    }
                } catch {
                    modal.dismissIfNotCanceled {
                        handleError(error, dismissalDelegate: failureSheetDismissalDelegate)
                    }
                }
            }
        )
    }

    /// Query the service for the given username, invoking a callback if the
    /// username is successfully resolved to an ACI.
    ///
    /// - Parameter onSuccess
    /// A callback invoked if the queried username resolves to an ACI.
    /// Guaranteed to be called on the main thread.
    @MainActor
    public func queryForUsername(
        username: String,
        fromViewController: UIViewController,
        tx: DBReadTransaction,
        failureSheetDismissalDelegate: (any SheetDismissalDelegate)? = nil,
        onSuccess: @escaping (Aci) -> Void
    ) {
        if
            let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci,
            let localUsername = localUsernameManager.usernameState(tx: tx).username,
            localUsername.caseInsensitiveCompare(username) == .orderedSame
        {
            queryMatchedLocalUser(onSuccess: onSuccess, localAci: localAci, tx: tx)
            return
        }

        guard let hashedUsername = try? Usernames.HashedUsername(
            forUsername: username
        ) else {
            showInvalidUsernameError(
                username: username,
                dismissalDelegate: failureSheetDismissalDelegate
            )
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: true,
            asyncBlock: { modal in
                do {
                    let aci = try await queryServiceForUsername(hashedUsername: hashedUsername)
                    modal.dismissIfNotCanceled {
                        onSuccess(aci)
                    }
                } catch {
                    modal.dismissIfNotCanceled {
                        handleError(error, dismissalDelegate: failureSheetDismissalDelegate)
                    }
                }
            }
        )
    }

    /// Handle a query that we know will match the local user.
    ///
    /// - Parameter tx
    /// An unused database transaction. Forced as a parameter here to draw
    /// attention to the fact that this workaround is required because the query
    /// methods are within the context of a transaction.
    private func queryMatchedLocalUser(
        onSuccess: @escaping (Aci) -> Void,
        localAci: Aci,
        tx _: DBReadTransaction
    ) {
        // Dispatch asynchronously, since we are inside a transaction.
        DispatchQueue.main.async {
            onSuccess(localAci)
        }
    }

    private struct UsernameNotFoundError: Error {
        var usernameString: String
    }

    /// Query the service for the ACI of the given username.
    private func queryServiceForUsername(hashedUsername: Usernames.HashedUsername) async throws -> Aci {
        let aci = try await self.usernameApiClient.lookupAci(forHashedUsername: hashedUsername)
        guard let aci else {
            throw UsernameNotFoundError(usernameString: hashedUsername.usernameString)
        }
        await self.databaseStorage.awaitableWrite { tx in
            self.handleUsernameLookupCompleted(
                aci: aci,
                username: hashedUsername.usernameString,
                tx: tx
            )
        }
        return aci
    }

    private func handleUsernameLookupCompleted(
        aci: Aci,
        username: String,
        tx: DBWriteTransaction
    ) {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: true, tx: tx)

        let isUsernameBestIdentifier = Usernames.BetterIdentifierChecker.assembleByQuerying(
            forRecipient: recipient,
            profileManager: profileManager,
            contactManager: contactsManager,
            transaction: tx
        ).usernameIsBestIdentifier()

        if isUsernameBestIdentifier {
            // If this username is the best identifier we have for this
            // address, we should save it locally and in StorageService.

            usernameLookupManager.saveUsername(
                username,
                forAci: aci,
                transaction: tx
            )

            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipient.uniqueId])
        } else {
            // If we have a better identifier for this address, we can
            // throw away any stored username info for it.

            usernameLookupManager.saveUsername(
                nil,
                forAci: aci,
                transaction: tx
            )
        }
    }

    // MARK: - Errors

    private func showInvalidUsernameError(
        username: String,
        dismissalDelegate: (any SheetDismissalDelegate)?
    ) {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "USERNAME_LOOKUP_INVALID_USERNAME_TITLE",
                comment: "Title for an action sheet indicating that a user-entered username value is not a valid username."
            ),
            message: String(
                format: OWSLocalizedString(
                    "USERNAME_LOOKUP_INVALID_USERNAME_MESSAGE_FORMAT",
                    comment: "A message indicating that a user-entered username value is not a valid username. Embeds {{ a username }}."
                ),
                username
            ),
            dismissalDelegate: dismissalDelegate
        )
    }

    private func showUsernameNotFoundError(
        username: String,
        dismissalDelegate: (any SheetDismissalDelegate)?
    ) {
        OWSActionSheets.showActionSheet(
            title: OWSLocalizedString(
                "USERNAME_LOOKUP_NOT_FOUND_TITLE",
                comment: "Title for an action sheet indicating that the given username is not associated with a registered Signal account."
            ),
            message: String(
                format: OWSLocalizedString(
                    "USERNAME_LOOKUP_NOT_FOUND_MESSAGE_FORMAT",
                    comment: "A message indicating that the given username is not associated with a registered Signal account. Embeds {{ a username }}."
                ),
                username
            ),
            dismissalDelegate: dismissalDelegate
        )
    }

    private func showUsernameLinkOutdatedError(
        dismissalDelegate: (any SheetDismissalDelegate)?
    ) {
        OWSActionSheets.showActionSheet(
            title: CommonStrings.errorAlertTitle,
            message: OWSLocalizedString(
                "USERNAME_LOOKUP_LINK_NO_LONGER_VALID_MESSAGE",
                comment: "A message indicating that a username link the user attempted to query is no longer valid."
            ),
            dismissalDelegate: dismissalDelegate
        )
    }

    private func handleError(
        _ error: any Error,
        dismissalDelegate: (any SheetDismissalDelegate)?,
    ) {
        if let notFoundError = error as? UsernameNotFoundError {
            showUsernameNotFoundError(username: notFoundError.usernameString, dismissalDelegate: dismissalDelegate)
        } else {
            showGenericError(dismissalDelegate: dismissalDelegate)
        }
    }

    private func showGenericError(
        dismissalDelegate: (any SheetDismissalDelegate)?
    ) {
        Logger.error("Error while querying for username!")

        OWSActionSheets.showErrorAlert(
            message: OWSLocalizedString(
                "USERNAME_LOOKUP_ERROR_MESSAGE",
                comment: "A message indicating that username lookup failed."
            ),
            dismissalDelegate: dismissalDelegate
        )
    }
}
