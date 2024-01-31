//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging
import SignalServiceKit

// MARK: - ContactAboutSheet

class ContactAboutSheet: StackSheetViewController {
    private let thread: TSContactThread
    private let isLocalUser: Bool

    init(thread: TSContactThread) {
        self.thread = thread
        self.isLocalUser = thread.isNoteToSelf
        super.init()
        databaseStorage.appendDatabaseChangeDelegate(self)
    }

    private weak var fromViewController: UIViewController?

    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    // MARK: Layout

    private lazy var avatarViewContainer: UIView = {
        let avatarView = ConversationAvatarView(
            sizeClass: .customDiameter(240),
            localUserDisplayMode: .asUser,
            badged: false
        )
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.dataSource = .thread(thread)
        }

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
            updateProfileBio(tx: tx)
            updateIsConnection(tx: tx)
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

        stackView.addArrangedSubview(ProfileDetailLabel.profile(title: self.contactName))

        if let profileBio {
            stackView.addArrangedSubview(ProfileDetailLabel.profileAbout(bio: profileBio))
        }

        if isConnection {
            stackView.addArrangedSubview(ProfileDetailLabel.signalConnectionLink(shouldDismissOnNavigation: true, presentEducationFrom: fromViewController))
        }

        if isInSystemContacts {
            stackView.addArrangedSubview(ProfileDetailLabel.inSystemContacts(name: self.contactShortName))
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

    private var contactName: String = ""
    private var contactShortName: String = ""
    private func updateContactNames(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            let snapshot = profileManagerImpl.localProfileSnapshot(shouldIncludeAvatar: false)
            contactName = snapshot.fullName ?? ""
            // contactShortName not needed for local user
            return
        }

        contactName = {
            let name = contactsManager.displayName(for: thread, transaction: tx)
            if name == thread.contactAddress.phoneNumber {
                return PhoneNumber
                    .bestEffortFormatPartialUserSpecifiedText(
                        toLookLikeAPhoneNumber: name
                    )
            }
            return name
        }()
        contactShortName = contactsManager.shortDisplayName(
            for: thread.contactAddress,
            transaction: tx
        )
    }

    // MARK: Bio

    private var profileBio: String?
    private func updateProfileBio(tx: SDSAnyReadTransaction) {
        profileBio = profileManagerImpl.profileBioForDisplay(for: thread.contactAddress, transaction: tx)
    }

    // MARK: Connection

    private var isConnection = false
    private func updateIsConnection(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            isConnection = false
            return
        }
        isConnection = profileManager.isThread(inProfileWhitelist: thread, transaction: tx)
    }

    // MARK: System contacts

    private var isInSystemContacts = false
    private func updateIsInSystemContacts(tx: SDSAnyReadTransaction) {
        if isLocalUser {
            isInSystemContacts = false
            return
        }
        isInSystemContacts = contactsManager.isSystemContact(address: thread.contactAddress, transaction: tx)
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
