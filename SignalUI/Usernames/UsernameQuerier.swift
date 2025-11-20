//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public struct UsernameQuerier {
    private let contactsManager: any ContactManager
    private let db: DB
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
            db: DependenciesBridge.shared.db,
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
        db: DB,
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
        self.db = db
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

    // MARK: -

    /// Query for the username via the given link, internally handling
    /// displaying errors as appropriate. Callers should do nothing if this
    /// method returns `nil`.
    @MainActor
    public func queryForUsernameLink(
        link: Usernames.UsernameLink,
        fromViewController: UIViewController,
        failureSheetDismissalDelegate: SheetDismissalDelegate? = nil,
    ) async -> (username: String, Aci)? {
        do throws(ActionSheetDisplayableError) {
            return try await _queryForUsernameLink(link: link, fromViewController: fromViewController)
        } catch {
            error.showActionSheet(from: fromViewController, dismissalDelegate: failureSheetDismissalDelegate)
            return nil
        }
    }

    private func _queryForUsernameLink(
        link: Usernames.UsernameLink,
        fromViewController: UIViewController,
    ) async throws(ActionSheetDisplayableError) -> (username: String, Aci) {
        let (localAci, localLink, localUsername): (
            Aci?,
            Usernames.UsernameLink?,
            String?,
        ) = db.read { tx in
            let usernameState = localUsernameManager.usernameState(tx: tx)
            return (
                tsAccountManager.localIdentifiers(tx: tx)?.aci,
                usernameState.usernameLink,
                usernameState.username,
            )
        }

        if
            let localAci,
            let localLink,
            let localUsername,
            localLink == link
        {
            return (localUsername, localAci)
        }

        return try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController,
            canCancel: true,
        ) { () throws(ActionSheetDisplayableError) -> (username: String, Aci) in
            let username: String?
            do {
                username = try await usernameLinkManager.decryptEncryptedLink(link: link)
            } catch is CancellationError {
                throw .userCancelled
            } catch where error.isNetworkFailureOrTimeout {
                throw .networkError
            } catch {
                Logger.warn("Failed to decrypt username link with generic error! \(error)")
                throw .usernameLookupGenericError()
            }

            guard let username else {
                throw .usernameLinkNoLongerValidError()
            }

            guard let hashedUsername = try? Usernames.HashedUsername(
                forUsername: username
            ) else {
                throw .usernameInvalidError(username)
            }

            do {
                let usernameAci = try await queryServiceForUsername(hashedUsername: hashedUsername)
                return (username, usernameAci)
            } catch is CancellationError {
                throw .userCancelled
            } catch is UsernameNotFoundError {
                throw .usernameNotFoundError(username)
            } catch where error.isNetworkFailureOrTimeout {
                throw .networkError
            } catch {
                Logger.warn("Failed to look up username for link with generic error! \(error)")
                throw .usernameLookupGenericError()
            }
        }
    }

    // MARK: -

    /// Query for the given username, internally handling displaying errors as
    /// appropriate. Callers should do nothing if this method returns `nil`.
    @MainActor
    public func queryForUsername(
        username: String,
        fromViewController: UIViewController,
        failureSheetDismissalDelegate: SheetDismissalDelegate? = nil,
    ) async -> Aci? {
        do throws(ActionSheetDisplayableError) {
            return try await _queryForUsername(username: username, fromViewController: fromViewController)
        } catch {
            error.showActionSheet(from: fromViewController, dismissalDelegate: failureSheetDismissalDelegate)
            return nil
        }
    }

    private func _queryForUsername(
        username: String,
        fromViewController: UIViewController,
    ) async throws(ActionSheetDisplayableError) -> Aci {
        let (localAci, localUsername): (Aci?, String?) = db.read { tx in
            return (
                tsAccountManager.localIdentifiers(tx: tx)?.aci,
                localUsernameManager.usernameState(tx: tx).username,
            )
        }

        if
            let localAci,
            let localUsername,
            localUsername.caseInsensitiveCompare(username) == .orderedSame
        {
            return localAci
        }

        return try await ModalActivityIndicatorViewController.presentAndPropagateResult(
            from: fromViewController,
            canCancel: true,
        ) { () throws(ActionSheetDisplayableError) -> Aci in
            guard let hashedUsername = try? Usernames.HashedUsername(
                forUsername: username
            ) else {
                throw .usernameInvalidError(username)
            }

            do {
                return try await queryServiceForUsername(hashedUsername: hashedUsername)
            } catch is CancellationError {
                throw .userCancelled
            } catch is UsernameNotFoundError {
                throw .usernameNotFoundError(username)
            } catch where error.isNetworkFailureOrTimeout {
                throw .networkError
            } catch {
                Logger.warn("Failed to query username with generic error! \(error)")
                throw .usernameLookupGenericError()
            }
        }
    }

    // MARK: -

    private struct UsernameNotFoundError: Error {}

    /// Query the service for the ACI of the given username.
    private func queryServiceForUsername(hashedUsername: Usernames.HashedUsername) async throws -> Aci {
        let aci = try await self.usernameApiClient.lookupAci(forHashedUsername: hashedUsername)
        guard let aci else {
            throw UsernameNotFoundError()
        }

        await db.awaitableWrite { tx in
            handleUsernameLookupCompleted(
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
        var recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        recipientManager.markAsRegisteredAndSave(&recipient, shouldUpdateStorageService: true, tx: tx)

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
}

// MARK: -

private extension ActionSheetDisplayableError {
    static func usernameInvalidError(_ username: String) -> ActionSheetDisplayableError {
        return .custom(
            localizedTitle: OWSLocalizedString(
                "USERNAME_LOOKUP_INVALID_USERNAME_TITLE",
                comment: "Title for an action sheet indicating that a user-entered username value is not a valid username."
            ),
            localizedMessage: String(
                format: OWSLocalizedString(
                    "USERNAME_LOOKUP_INVALID_USERNAME_MESSAGE_FORMAT",
                    comment: "A message indicating that a user-entered username value is not a valid username. Embeds {{ a username }}."
                ),
                username,
            )
        )
    }

    static func usernameNotFoundError(_ username: String) -> ActionSheetDisplayableError {
        return .custom(
            localizedTitle: OWSLocalizedString(
                "USERNAME_LOOKUP_NOT_FOUND_TITLE",
                comment: "Title for an action sheet indicating that the given username is not associated with a registered Signal account."
            ),
            localizedMessage: String(
                format: OWSLocalizedString(
                    "USERNAME_LOOKUP_NOT_FOUND_MESSAGE_FORMAT",
                    comment: "A message indicating that the given username is not associated with a registered Signal account. Embeds {{ a username }}."
                ),
                username,
            ),
        )
    }

    static func usernameLinkNoLongerValidError() -> ActionSheetDisplayableError {
        return .custom(
            localizedTitle: CommonStrings.errorAlertTitle,
            localizedMessage: OWSLocalizedString(
                "USERNAME_LOOKUP_LINK_NO_LONGER_VALID_MESSAGE",
                comment: "A message indicating that a username link the user attempted to query is no longer valid."
            ),
        )
    }

    static func usernameLookupGenericError() -> ActionSheetDisplayableError {
        return .custom(localizedMessage: OWSLocalizedString(
            "USERNAME_LOOKUP_ERROR_MESSAGE",
            comment: "A message indicating that username lookup failed."
        ))
    }
}
