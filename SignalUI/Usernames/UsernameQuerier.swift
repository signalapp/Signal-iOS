//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalMessaging
import SignalServiceKit

public struct UsernameQuerier {
    private let contactsManager: ContactsManagerProtocol
    private let databaseStorage: SDSDatabaseStorage
    private let localUsernameManager: LocalUsernameManager
    private let networkManager: NetworkManager
    private let profileManager: ProfileManager
    private let recipientManager: any SignalRecipientManager
    private let recipientFetcher: RecipientFetcher
    private let schedulers: Schedulers
    private let storageServiceManager: StorageServiceManager
    private let tsAccountManager: TSAccountManager
    private let usernameApiClient: UsernameApiClient
    private let usernameLinkManager: UsernameLinkManager
    private let usernameLookupManager: UsernameLookupManager

    public init() {
        struct Deps: Dependencies {}
        let deps = Deps()

        self.init(
            contactsManager: deps.contactsManager,
            databaseStorage: deps.databaseStorage,
            localUsernameManager: DependenciesBridge.shared.localUsernameManager,
            networkManager: deps.networkManager,
            profileManager: deps.profileManager,
            recipientManager: DependenciesBridge.shared.recipientManager,
            recipientFetcher: DependenciesBridge.shared.recipientFetcher,
            schedulers: DependenciesBridge.shared.schedulers,
            storageServiceManager: deps.storageServiceManager,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            usernameApiClient: DependenciesBridge.shared.usernameApiClient,
            usernameLinkManager: DependenciesBridge.shared.usernameLinkManager,
            usernameLookupManager: DependenciesBridge.shared.usernameLookupManager
        )
    }

    public init(
        contactsManager: ContactsManagerProtocol,
        databaseStorage: SDSDatabaseStorage,
        localUsernameManager: LocalUsernameManager,
        networkManager: NetworkManager,
        profileManager: ProfileManager,
        recipientManager: any SignalRecipientManager,
        recipientFetcher: RecipientFetcher,
        schedulers: Schedulers,
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
        self.schedulers = schedulers
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.usernameApiClient = usernameApiClient
        self.usernameLinkManager = usernameLinkManager
        self.usernameLookupManager = usernameLookupManager
    }

    public func queryForUsernameLink(
        link: Usernames.UsernameLink,
        fromViewController: UIViewController,
        tx: SDSAnyReadTransaction,
        onSuccess: @escaping (Aci) -> Void
    ) {
        if
            let localAci = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci,
            let localLink = localUsernameManager.usernameState(tx: tx.asV2Read).usernameLink,
            localLink == link
        {
            queryMatchedLocalUser(onSuccess: onSuccess, localAci: localAci, tx: tx)
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: true
        ) { modal in
            firstly(on: schedulers.sync) { () -> Promise<String?> in
                usernameLinkManager.decryptEncryptedLink(link: link)
            }.done(on: schedulers.main) { username in
                guard let username else {
                    modal.dismissIfNotCanceled {
                        showUsernameLinkOutdatedError()
                    }

                    return
                }

                guard let hashedUsername = try? Usernames.HashedUsername(
                    forUsername: username
                ) else {
                    modal.dismissIfNotCanceled {
                        showInvalidUsernameError(username: username)
                    }
                    return
                }

                queryServiceForUsernameBehindSpinner(
                    presentedModalActivityIndicator: modal,
                    hashedUsername: hashedUsername,
                    onSuccess: onSuccess
                )
            }.catch(on: schedulers.main) { _ in
                showGenericError(presentedModal: modal)
            }
        }
    }

    /// Query the service for the given username, invoking a callback if the
    /// username is successfully resolved to an ACI.
    ///
    /// - Parameter onSuccess
    /// A callback invoked if the queried username resolves to an ACI.
    /// Guaranteed to be called on the main thread.
    public func queryForUsername(
        username: String,
        fromViewController: UIViewController,
        tx: SDSAnyReadTransaction,
        onSuccess: @escaping (Aci) -> Void
    ) {
        if
            let localAci = tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci,
            let localUsername = localUsernameManager.usernameState(tx: tx.asV2Read).username,
            localUsername.caseInsensitiveCompare(username) == .orderedSame
        {
            queryMatchedLocalUser(onSuccess: onSuccess, localAci: localAci, tx: tx)
            return
        }

        guard let hashedUsername = try? Usernames.HashedUsername(
            forUsername: username
        ) else {
            showInvalidUsernameError(username: username)
            return
        }

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            canCancel: true
        ) { modal in
            queryServiceForUsernameBehindSpinner(
                presentedModalActivityIndicator: modal,
                hashedUsername: hashedUsername,
                onSuccess: onSuccess
            )
        }
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
        tx _: SDSAnyReadTransaction
    ) {
        // Dispatch asynchronously, since we are inside a transaction.
        schedulers.main.async {
            onSuccess(localAci)
        }
    }

    /// Query the service for the ACI of the given username.
    ///
    /// - Parameter presentedModalActivityIndicator
    /// The currently-presented modal activity indicator.
    /// - Parameter onSuccess
    /// Called if the username resolves successfully to an ACI. Guaranteed to be
    /// called on the main thread.
    private func queryServiceForUsernameBehindSpinner(
        presentedModalActivityIndicator modal: ModalActivityIndicatorViewController,
        hashedUsername: Usernames.HashedUsername,
        onSuccess: @escaping (Aci) -> Void
    ) {
        firstly(on: schedulers.sync) { () -> Promise<Aci?> in
            return self.usernameApiClient.lookupAci(
                forHashedUsername: hashedUsername
            )
        }.done(on: schedulers.main) { maybeAci in
            modal.dismissIfNotCanceled {
                if let aci = maybeAci {
                    self.databaseStorage.write { tx in
                        self.handleUsernameLookupCompleted(
                            aci: aci,
                            username: hashedUsername.usernameString,
                            tx: tx
                        )
                    }

                    schedulers.main.async {
                        onSuccess(aci)
                    }
                } else {
                    self.showUsernameNotFoundError(
                        username: hashedUsername.usernameString
                    )
                }
            }
        }.catch(on: schedulers.main) { _ in
            showGenericError(presentedModal: modal)
        }
    }

    private func handleUsernameLookupCompleted(
        aci: Aci,
        username: String,
        tx: SDSAnyWriteTransaction
    ) {
        let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx.asV2Write)
        recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: true, tx: tx.asV2Write)

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
                transaction: tx.asV2Write
            )

            storageServiceManager.recordPendingUpdates(updatedAccountIds: [recipient.accountId])
        } else {
            // If we have a better identifier for this address, we can
            // throw away any stored username info for it.

            usernameLookupManager.saveUsername(
                nil,
                forAci: aci,
                transaction: tx.asV2Write
            )
        }
    }

    // MARK: - Errors

    private func showInvalidUsernameError(username: String) {
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
            )
        )
    }

    private func showUsernameNotFoundError(username: String) {
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
            )
        )
    }

    private func showUsernameLinkOutdatedError() {
        OWSActionSheets.showActionSheet(
            title: CommonStrings.errorAlertTitle,
            message: OWSLocalizedString(
                "USERNAME_LOOKUP_LINK_NO_LONGER_VALID_MESSAGE",
                comment: "A message indicating that a username link the user attempted to query is no longer valid."
            )
        )
    }

    private func showGenericError(
        presentedModal modal: ModalActivityIndicatorViewController
    ) {
        Logger.error("Error while querying for username!")

        modal.dismissIfNotCanceled {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "USERNAME_LOOKUP_ERROR_MESSAGE",
                comment: "A message indicating that username lookup failed."
            ))
        }
    }
}
