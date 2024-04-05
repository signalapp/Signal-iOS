//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit

// MARK: - ContactAboutSheet

class ContactAboutSheet: StackSheetViewController {
    private let thread: TSContactThread
    private let isLocalUser: Bool
    private let spoilerState: SpoilerRenderState

    init(thread: TSContactThread, spoilerState: SpoilerRenderState) {
        self.thread = thread
        self.isLocalUser = thread.isNoteToSelf
        self.spoilerState = spoilerState
        super.init()
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    private weak var fromViewController: UIViewController?

    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    // MARK: Layout

    private lazy var avatarView: ConversationAvatarView = {
        let avatarView = ConversationAvatarView(
            sizeClass: .customDiameter(240),
            localUserDisplayMode: .asUser,
            badged: false
        )
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(thread)
        }
        avatarView.interactionDelegate = self
        return avatarView
    }()

    private lazy var avatarViewContainer: UIView = {
        let container = UIView.container()
        container.addSubview(avatarView)
        avatarView.autoCenterInSuperview()
        avatarView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        avatarView.autoPinHeightToSuperview(relation: .lessThanOrEqual)
        return container
    }()

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        stackView.spacing = 10
        stackView.alignment = .fill
        updateContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        loadContents()
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        loadContents()
    }

    override var stackViewInsets: UIEdgeInsets {
        let hMargin: CGFloat = {
            if UIDevice.current.isNarrowerThanIPhone6 {
                return 20
            } else {
                return 32
            }
        }()

        return .init(
            top: 24,
            leading: hMargin,
            bottom: 20,
            trailing: hMargin
        )
    }

    override var minimumBottomInsetIncludingSafeArea: CGFloat { 32 }

    // MARK: - Content

    /// Updates the contents with a database read and reloads the view.
    private func updateContents() {
        databaseStorage.read { tx in
            updateContactNames(tx: tx)
            updateIsVerified(tx: tx)
            updateProfileBio(tx: tx)
            updateConnectionState(tx: tx)
            updateIsInSystemContacts(tx: tx)
            updateMutualGroupThreadCount(tx: tx)
        }

        loadContents()
    }

    /// Reloads the view content with the existing data.
    @MainActor
    private func loadContents() {
        stackView.removeAllSubviews()

        stackView.addArrangedSubview(avatarViewContainer)
        stackView.setCustomSpacing(16, after: avatarViewContainer)

        let titleLabel = UILabel()
        titleLabel.font = .dynamicTypeTitle2.semibold()
        if isLocalUser {
            titleLabel.text = CommonStrings.you
        } else {
            titleLabel.text = OWSLocalizedString(
                "CONTACT_ABOUT_SHEET_TITLE",
                comment: "The title for a contact 'about' sheet."
            )
        }
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        stackView.addArrangedSubview(ProfileDetailLabel.profile(displayName: self.displayName, secondaryName: self.secondaryName))

        if isVerified {
            stackView.addArrangedSubview(ProfileDetailLabel.verified())
        }

        if let profileBio {
            stackView.addArrangedSubview(ProfileDetailLabel.profileAbout(bio: profileBio))
        }

        switch connectionState {
        case .connection:
            stackView.addArrangedSubview(ProfileDetailLabel.signalConnectionLink(shouldDismissOnNavigation: true, presentEducationFrom: fromViewController))
        case .blocked:
            stackView.addArrangedSubview(ProfileDetailLabel.blocked(name: self.shortDisplayName))
        case .pending:
            stackView.addArrangedSubview(ProfileDetailLabel.pendingRequest(name: self.shortDisplayName))
        case .noConnection:
            stackView.addArrangedSubview(ProfileDetailLabel.noDirectChat(name: self.shortDisplayName))
        case nil:
            break
        }

        if isInSystemContacts {
            stackView.addArrangedSubview(ProfileDetailLabel.inSystemContacts(name: self.shortDisplayName))
        }

        let recipientAddress = thread.contactAddress
        if let phoneNumber = recipientAddress.phoneNumber {
            stackView.addArrangedSubview(ProfileDetailLabel.phoneNumber(phoneNumber, presentSuccessToastFrom: self))
        }

        if let mutualGroupThreads {
            stackView.addArrangedSubview(ProfileDetailLabel.mutualGroups(for: thread, mutualGroups: mutualGroupThreads))
        }
    }

    // MARK: Name

    private var displayName: String = ""
    private var shortDisplayName: String = ""
    /// A secondary name to show after the primary name. Used to show a
    /// contact's profile name when it is overridden by a nickname.
    private var secondaryName: String?
    private func updateContactNames(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
            displayName = snapshot.fullName ?? ""
            // contactShortName not needed for local user
            return
        }

        let displayName = contactsManager.displayName(for: thread.contactAddress, tx: tx)
        self.displayName = displayName.resolvedValue()
        self.shortDisplayName = displayName.resolvedValue(useShortNameIfAvailable: true)

        if case .phoneNumber(let phoneNumber) = displayName {
            self.displayName = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(
                toLookLikeAPhoneNumber: phoneNumber.stringValue
            )
        }

        switch displayName {
        case .nickname:
            guard
                let profile = profileManager.fetchUserProfiles(
                    for: [thread.contactAddress],
                    tx: tx
                ).first,
                let profileName = profile?.nameComponents
                    .map(DisplayName.profileName(_:))?
                    .resolvedValue(),
                profileName != displayName.resolvedValue()
            else {
                fallthrough
            }
            secondaryName = profileName
        case .systemContactName, .profileName, .phoneNumber, .username, .unknown:
            secondaryName = nil
        }
    }

    // MARK: Verified

    private var isVerified = false
    private func updateIsVerified(tx: SDSAnyReadTransaction) {
        let identityManager = DependenciesBridge.shared.identityManager
        isVerified = identityManager.verificationState(for: thread.contactAddress, tx: tx.asV2Read) == .verified
    }

    // MARK: Bio

    private var profileBio: String?
    private func updateProfileBio(tx: SDSAnyReadTransaction) {
        profileBio = profileManagerImpl.profileBioForDisplay(for: thread.contactAddress, transaction: tx)
    }

    // MARK: Connection

    private enum ConnectionState {
        case connection
        case blocked
        case pending
        case noConnection
    }

    private var connectionState: ConnectionState?
    private func updateConnectionState(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            connectionState = nil
        } else if profileManager.isThread(inProfileWhitelist: thread, transaction: tx) {
            connectionState = .connection
        } else if blockingManager.isAddressBlocked(thread.contactAddress, transaction: tx) {
            connectionState = .blocked
        } else if thread.hasPendingMessageRequest(transaction: tx) {
            connectionState = .pending
        } else {
            connectionState = .noConnection
        }
    }

    // MARK: System contacts

    private var isInSystemContacts = false
    private func updateIsInSystemContacts(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            isInSystemContacts = false
            return
        }
        isInSystemContacts = contactsManager.fetchSignalAccount(for: thread.contactAddress, transaction: tx) != nil
    }

    // MARK: Threads

    private var mutualGroupThreads: [TSGroupThread]?
    private func updateMutualGroupThreadCount(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            mutualGroupThreads = nil
            return
        }

        mutualGroupThreads = TSGroupThread.groupThreads(
            with: self.thread.contactAddress,
            transaction: tx
        )
        .filter(\.isLocalUserFullMember)
        .filter(\.shouldThreadBeVisible)
        // We don't want to show "no groups in common",
        // so return nil instead of an empty array.
        .nilIfEmpty
    }
}

// MARK: - DatabaseChangeDelegate

extension ContactAboutSheet: DatabaseChangeDelegate {
    func databaseChangesDidUpdate(databaseChanges: SignalServiceKit.DatabaseChanges) {
        guard databaseChanges.didUpdate(thread: thread) else { return }
        updateContents()
    }

    func databaseChangesDidUpdateExternally() {
        updateContents()
    }

    func databaseChangesDidReset() {
        updateContents()
    }
}

// MARK: - ConversationAvatarViewDelegate

extension ContactAboutSheet: ConversationAvatarViewDelegate {
    func didTapBadge() {
        // Badges are not shown on contact about sheet
    }

    func presentStoryViewController() {
        let vc = StoryPageViewController(
            context: self.thread.storyContext,
            spoilerState: self.spoilerState
        )
        present(vc, animated: true)
    }

    func presentAvatarViewController() {
        guard
            avatarView.primaryImage != nil,
            let vc = databaseStorage.read(block: { tx in
                AvatarViewController(
                    thread: self.thread,
                    renderLocalUserAsNoteToSelf: false,
                    readTx: tx
                )
            })
        else {
            return
        }

        present(vc, animated: true)
    }
}

// MARK: - AvatarViewPresentationContextProvider

extension ContactAboutSheet: AvatarViewPresentationContextProvider {
    var conversationAvatarView: ConversationAvatarView? { avatarView }
}
