//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import Contacts
import LibSignalClient
import SignalServiceKit
import UIKit

@MainActor
final class ContactSharingPickerViewModel {

    typealias CNContactID = String

    // MARK: - Dependencies

    private let avatarBuilder: AvatarBuilder
    private let blockedRecipientIdentifiersProvider: (DBReadTransaction) -> Set<SignalRecipient.RowId>
    private let comparableValueConfigProvider: () -> DisplayName.ComparableValue.Config
    private let contactManager: any ContactManager
    private let contactsSharingAuthorizationProvider: () -> ContactAuthorizationForSharing
    private let db: any DB
    private let displayNamesForRecipientsProvider: ([SignalRecipient], DBReadTransaction) -> [DisplayName]
    private let nicknameRecordStore: any NicknameRecordStore
    private let phoneNumberUtil: PhoneNumberUtil
    private let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    private let profileManager: any ProfileManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientHidingManager: any RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let searchDebounceInterval: DispatchQueue.SchedulerTimeType.Stride
    private let systemContactsProvider: (ContactAuthorizationForSharing) -> [SystemContact]
    private let tsAccountManager: any TSAccountManager
    private let userProfileProvider: (SignalRecipient, DBReadTransaction) -> OWSUserProfile?

    // MARK: - State

    enum State {
        case initial
        case loaded([Row])

        var isInitial: Bool {
            switch self {
            case .initial: return true
            default: return false
            }
        }
    }

    private let stateSubject = CurrentValueSubject<State, Never>(.initial)
    private let searchTextSubject = CurrentValueSubject<String, Never>("")

    var state: State { stateSubject.value }

    private(set) lazy var displayedRowsPublisher: AnyPublisher<DisplayedRows, Never> = {
        Publishers.CombineLatest(
            stateSubject,
            searchTextSubject.debounce(
                for: searchDebounceInterval,
                scheduler: DispatchQueue.main,
                immediatelyWhen: \.isEmpty,
            ),
        )
        .map(Self.displayedRows(for:searchText:))
        .eraseToAnyPublisher()
    }()

    private nonisolated static func displayedRows(for state: State, searchText: String) -> DisplayedRows {
        let searchText = searchText.strippedOrNil

        guard case .loaded(let rows) = state else {
            return DisplayedRows(isSearching: searchText != nil, rows: [])
        }
        guard let searchText else {
            return DisplayedRows(isSearching: false, rows: rows)
        }
        return DisplayedRows(
            isSearching: true,
            rows: rows.filter { $0.matches(searchText: searchText) },
        )
    }

    // MARK: - Lifecycle

    init(
        avatarBuilder: AvatarBuilder = SSKEnvironment.shared.avatarBuilderRef,
        blockedRecipientIdentifiersProvider: ((DBReadTransaction) -> Set<SignalRecipient.RowId>)? = nil,
        comparableValueConfigProvider: (() -> DisplayName.ComparableValue.Config)? = nil,
        contactManager: any ContactManager = SSKEnvironment.shared.contactManagerRef,
        contactsSharingAuthorizationProvider: (() -> ContactAuthorizationForSharing)? = nil,
        db: any DB = SSKEnvironment.shared.databaseStorageRef,
        displayNamesForRecipientsProvider: (([SignalRecipient], DBReadTransaction) -> [DisplayName])? = nil,
        nicknameRecordStore: any NicknameRecordStore = NicknameRecordStoreImpl(),
        phoneNumberUtil: PhoneNumberUtil = SSKEnvironment.shared.phoneNumberUtilRef,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher = DependenciesBridge.shared.phoneNumberVisibilityFetcher,
        profileManager: any ProfileManager = SSKEnvironment.shared.profileManagerRef,
        recipientDatabaseTable: RecipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable,
        recipientHidingManager: any RecipientHidingManager = DependenciesBridge.shared.recipientHidingManager,
        recipientManager: any SignalRecipientManager = DependenciesBridge.shared.recipientManager,
        searchDebounceInterval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(300),
        systemContactsProvider: ((ContactAuthorizationForSharing) -> [SystemContact])? = nil,
        tsAccountManager: any TSAccountManager = DependenciesBridge.shared.tsAccountManager,
        userProfileProvider: ((SignalRecipient, DBReadTransaction) -> OWSUserProfile?)? = nil,
    ) {
        self.avatarBuilder = avatarBuilder
        self.blockedRecipientIdentifiersProvider = blockedRecipientIdentifiersProvider ?? { tx in
            SSKEnvironment.shared.blockingManagerRef.blockedRecipientIds(tx: tx)
        }
        self.comparableValueConfigProvider = comparableValueConfigProvider ?? { .current() }
        self.contactManager = contactManager
        self.contactsSharingAuthorizationProvider = contactsSharingAuthorizationProvider ?? {
            SSKEnvironment.shared.contactManagerImplRef.sharingAuthorization
        }
        self.db = db
        self.displayNamesForRecipientsProvider = displayNamesForRecipientsProvider ?? { recipients, tx in
            contactManager.displayNames(for: recipients.map(\.address), tx: tx)
        }
        self.nicknameRecordStore = nicknameRecordStore
        self.phoneNumberUtil = phoneNumberUtil
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.searchDebounceInterval = searchDebounceInterval
        self.systemContactsProvider = systemContactsProvider ?? Self.fetchSystemContacts
        self.tsAccountManager = tsAccountManager
        self.userProfileProvider = userProfileProvider ?? { recipient, tx in
            profileManager.userProfile(for: recipient.address, tx: tx)
        }
    }

    // MARK: - Searching

    func setSearchText(_ searchText: String) {
        searchTextSubject.value = searchText
    }

    // MARK: - Loading

    func loadData() {
        let comparableValueConfig = comparableValueConfigProvider()

        stateSubject.value = .loaded(
            mergeRows(
                comparableValueConfig: comparableValueConfig,
                signalContactsData: loadSignalContactsData(comparableValueConfig: comparableValueConfig),
                systemContacts: systemContactsProvider(contactsSharingAuthorizationProvider()),
            ),
        )
    }

    private func loadSignalContactsData(
        comparableValueConfig: DisplayName.ComparableValue.Config,
    ) -> SignalContactsData {
        db.read { tx in
            let excludedRecipients = blockedRecipients(tx: tx) + recipientHidingManager.hiddenRecipients(tx: tx)
            let localIdentifiers = try? tsAccountManager.registeredState(tx: tx).localIdentifiers

            var recipientsById = [SignalRecipient.RowId: SignalRecipient]()
            for recipient in recipientDatabaseTable.fetchWhitelistedRecipients(tx: tx) where recipient.isRegistered {
                recipientsById[recipient.id] = recipient
            }

            if
                let localIdentifiers,
                let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx),
                localRecipient.isRegistered
            {
                recipientsById[localRecipient.id] = localRecipient
            }

            for excludedRecipient in excludedRecipients {
                recipientsById.removeValue(forKey: excludedRecipient.id)
            }

            let recipients = Array(recipientsById.values)
            let displayNames = displayNamesForRecipientsProvider(recipients, tx)

            return SignalContactsData(
                excludedPhoneNumbers: Set(excludedRecipients.lazy.compactMap(Self.canonicalPhoneNumber(of:))),
                localPhoneNumber: localIdentifiers?.phoneNumberAsOptional
                    .flatMap { E164($0) }
                    .map { CanonicalPhoneNumber(nonCanonicalPhoneNumber: $0) },
                recipients: zip(recipients, displayNames).map { recipient, displayName in
                    SignalContact(
                        recipient: recipient,
                        displayName: displayName,
                        comparableValueConfig: comparableValueConfig,
                    )
                },
            )
        }
    }

    private func blockedRecipients(tx: DBReadTransaction) -> [SignalRecipient] {
        blockedRecipientIdentifiersProvider(tx).compactMap {
            recipientDatabaseTable.fetchRecipient(rowId: $0, tx: tx)
        }
    }

    private static func fetchSystemContacts(
        contactAuthorizationForSharing: ContactAuthorizationForSharing,
    ) -> [SystemContact] {
        guard contactAuthorizationForSharing == .authorized else {
            return []
        }

        var systemContacts = [SystemContact]()
        let contactStore = CNContactStore()
        let fetchRequest = CNContactFetchRequest(keysToFetch: SystemContact.contactKeys)
        fetchRequest.sortOrder = .userDefault
        do {
            try contactStore.enumerateContacts(with: fetchRequest) { cnContact, _ in
                systemContacts.append(SystemContact(cnContact: cnContact))
            }
        } catch {
            Logger.error("Failed to fetch system contacts: \(error)")
        }

        return systemContacts
    }

    // MARK: - Merging

    private func mergeRows(
        comparableValueConfig: DisplayName.ComparableValue.Config,
        signalContactsData: SignalContactsData,
        systemContacts: [SystemContact],
    ) -> [Row] {
        let localPhoneNumber = signalContactsData.localPhoneNumber

        var systemContactWrappers = [SystemContactWrapper]()
        var systemContactsByPhoneNumber = [CanonicalPhoneNumber: SystemContactWrapper]()

        for systemContact in systemContacts {
            guard
                let wrapper = SystemContactWrapper(
                    systemContact: systemContact,
                    comparableValueConfig: comparableValueConfig,
                )
            else {
                continue
            }

            let phoneNumbers = wrapper.canonicalPhoneNumbers(
                localPhoneNumber: localPhoneNumber,
                phoneNumberUtil: phoneNumberUtil,
            )

            guard phoneNumbers.isDisjoint(with: signalContactsData.excludedPhoneNumbers) else {
                continue
            }

            systemContactWrappers.append(wrapper)

            for phoneNumber in phoneNumbers where systemContactsByPhoneNumber[phoneNumber] == nil {
                systemContactsByPhoneNumber[phoneNumber] = wrapper
            }
        }

        var matchedContactIds = Set<String>()
        var rows = [Row]()

        for signalContact in signalContactsData.recipients {
            let systemContact = Self.canonicalPhoneNumber(of: signalContact.recipient)
                .flatMap { systemContactsByPhoneNumber[$0] }

            if let systemContact {
                matchedContactIds.insert(systemContact.systemContact.cnContactId)
            }

            rows.append(.signalContact(signalContact, systemContact: systemContact))
        }

        for wrapper in systemContactWrappers where wrapper.hasName {
            if !matchedContactIds.contains(wrapper.systemContact.cnContactId) {
                rows.append(.systemContact(wrapper))
            }
        }

        return rows
            .map { (sortKey: $0.sortKey, row: $0) }
            .sorted { Row.SortKey.isOrderedBefore($0.sortKey, $1.sortKey) }
            .map { $0.row }
    }

    private static func canonicalPhoneNumber(of recipient: SignalRecipient) -> CanonicalPhoneNumber? {
        recipient.phoneNumber
            .flatMap { E164($0.stringValue) }
            .map { CanonicalPhoneNumber(nonCanonicalPhoneNumber: $0) }
    }

    // MARK: - Avatars

    private func addressBookAvatarImage(cnContactId: CNContactID) -> UIImage? {
        contactManager.avatarImage(for: cnContactId)
    }

    func avatarImage(for row: Row, diameterPoints: UInt) -> UIImage? {
        switch row {
        case .signalContact(let signalContact, _):
            return db.read { tx in
                avatarBuilder.avatarImage(
                    forAddress: signalContact.recipient.address,
                    diameterPoints: diameterPoints,
                    localUserDisplayMode: .asUser,
                    transaction: tx,
                )
            }
        case .systemContact(let systemContact):
            if let addressBookAvatarImage = addressBookAvatarImage(cnContactId: systemContact.systemContact.cnContactId) {
                return addressBookAvatarImage
            }
            return db.read { tx in
                avatarBuilder.defaultAvatarImage(
                    personNameComponents: systemContact.avatarNameComponents,
                    diameterPoints: diameterPoints,
                    transaction: tx,
                )
            }
        }
    }

    // MARK: - Sharing

    func contactShareDraft(for row: Row) -> ContactShareDraft {
        db.read { tx in
            let draft: ContactShareDraft
            switch row {
            case .signalContact(let signalContact, let systemContact):
                if let systemContact {
                    draft = contactShareDraft(for: systemContact, tx: tx)
                    if row.namingSystemContact == nil {
                        draft.name = contactName(for: signalContact, tx: tx)
                    }
                } else {
                    draft = contactShareDraft(for: signalContact, tx: tx)
                }
            case .systemContact(let systemContact):
                draft = contactShareDraft(for: systemContact, tx: tx)
            }
            draft.aci = row.shareableAci(recipientDatabaseTable: recipientDatabaseTable, transaction: tx)
            if draft.aci != nil, let recipientRowId = row.signalContact?.recipient.id {
                draft.signalNote = nicknameRecordStore.fetch(recipientRowID: recipientRowId, tx: tx)?.note?.strippedOrNil
            }
            return draft
        }
    }

    private func contactShareDraft(for systemContact: SystemContactWrapper, tx: DBReadTransaction) -> ContactShareDraft {
        guard let cnContact = contactManager.cnContact(withId: systemContact.systemContact.cnContactId) else {
            Logger.warn("The address book card went away; sharing what was loaded from it.")
            return systemContact.contactShareDraft(phoneNumberUtil: phoneNumberUtil)
        }

        return ContactShareDraft.load(
            cnContact: cnContact,
            signalContact: systemContact.systemContact,
            contactManager: contactManager,
            phoneNumberUtil: phoneNumberUtil,
            profileManager: profileManager,
            recipientManager: recipientManager,
            tsAccountManager: tsAccountManager,
            tx: tx,
        )
    }

    private func contactShareDraft(for signalContact: SignalContact, tx: DBReadTransaction) -> ContactShareDraft {
        let recipient = signalContact.recipient
        let userProfile = userProfileProvider(recipient, tx)

        var phoneNumbers = [OWSContactPhoneNumber]()
        if
            let phoneNumber = recipient.phoneNumber?.stringValue,
            phoneNumberVisibilityFetcher.isPhoneNumberVisible(for: recipient, tx: tx)
        {
            phoneNumbers.append(OWSContactPhoneNumber(type: .mobile, phoneNumber: phoneNumber))
        }

        return ContactShareDraft(
            name: signalContact.contactName(profileNameComponents: { userProfile?.nameComponents }),
            addresses: [],
            emails: [],
            phoneNumbers: phoneNumbers,
            aci: nil,
            signalNote: nil,
            existingAvatarAttachment: nil,
            avatarImageData: userProfile?.loadAvatarData(),
        )
    }

    private func contactName(for signalContact: SignalContact, tx: DBReadTransaction) -> OWSContactName {
        signalContact.contactName(profileNameComponents: {
            userProfileProvider(signalContact.recipient, tx)?.nameComponents
        })
    }

    // MARK: - Supporting Types

    struct DisplayedRows {
        let isSearching: Bool
        let rows: [Row]
    }

    struct SignalContactsData {
        var excludedPhoneNumbers: Set<CanonicalPhoneNumber>
        var localPhoneNumber: CanonicalPhoneNumber?
        var recipients: [SignalContact]
    }

    /// A Signal recipient ready to display. Every field it needs is pre-fetched from the database.
    struct SignalContact {
        let recipient: SignalRecipient

        let comparableValue: DisplayName.ComparableValue

        /// The name to show on the Contact Sharing Picker row.
        let resolvedDisplayName: String

        private let displayName: DisplayName

        init(
            recipient: SignalRecipient,
            displayName: DisplayName,
            comparableValueConfig: DisplayName.ComparableValue.Config,
        ) {
            self.comparableValue = displayName.comparableValue(config: comparableValueConfig)
            self.resolvedDisplayName = displayName.resolvedValue(config: comparableValueConfig.displayNameConfig)
            self.displayName = displayName
            self.recipient = recipient
        }

        /// The name to put on a contact share. This is deliberately not derived
        /// from `resolvedDisplayName`, which may be the Signal nickname.
        func contactName(profileNameComponents: () -> PersonNameComponents?) -> OWSContactName {
            switch displayName {
            case .nickname:
                guard let profileNameComponents = profileNameComponents() else {
                    return OWSContactName(givenName: CommonStrings.unknownUser)
                }
                return OWSContactName(components: profileNameComponents)
            case .systemContactName(let systemContactName):
                return OWSContactName(components: systemContactName.nameComponents)
            case .profileName(let nameComponents):
                return OWSContactName(components: nameComponents)
            case .sharedName(let sharedName):
                return OWSContactName(components: sharedName.nameComponents)
            case .phoneNumber, .username, .deletedAccount, .unknown:
                return OWSContactName(givenName: resolvedDisplayName)
            }
        }
    }

    // MARK: - Row

    enum Row {
        case signalContact(SignalContact, systemContact: SystemContactWrapper?)
        case systemContact(SystemContactWrapper)

        var signalContact: SignalContact? {
            switch self {
            case .signalContact(let signalContact, _): signalContact
            case .systemContact: nil
            }
        }

        var systemContact: SystemContactWrapper? {
            switch self {
            case .signalContact(_, let systemContact): systemContact
            case .systemContact(let systemContact): systemContact
            }
        }

        var recipient: SignalRecipient? {
            signalContact?.recipient
        }

        var shouldShowContactIcon: Bool {
            guard let recipient = signalContact?.recipient, recipient.isRegistered else {
                return false
            }
            return recipient.aci != nil
        }

        var identity: Identity {
            switch self {
            case .signalContact(let signalContact, _): .recipient(signalContact.recipient.id)
            case .systemContact(let systemContact): .systemContact(systemContact.systemContact.cnContactId)
            }
        }

        enum Identity: Hashable {
            case recipient(SignalRecipient.RowId)
            case systemContact(String)
        }

        /// The system contact this row is named and sorted by, which is the attached
        /// one unless a Signal contact would name it better.
        var namingSystemContact: SystemContactWrapper? {
            switch self {
            case .systemContact(let systemContact):
                return systemContact
            case .signalContact(_, let systemContact):
                guard let systemContact else { return nil }
                return systemContact.hasName ? systemContact : nil
            }
        }

        var displayName: String {
            if let namingSystemContact {
                return namingSystemContact.displayName
            }
            switch self {
            case .signalContact(let signalContact, _):
                return signalContact.resolvedDisplayName
            case .systemContact(let systemContact):
                return systemContact.displayName
            }
        }

        private var comparableValue: DisplayName.ComparableValue {
            if let namingSystemContact {
                return namingSystemContact.comparableValue
            }
            switch self {
            case .signalContact(let signalContact, _):
                return signalContact.comparableValue
            case .systemContact(let systemContact):
                return systemContact.comparableValue
            }
        }

        /// Whether this row is listed under "#" rather than under a letter.
        var isGroupedAtEnd: Bool {
            if let namingSystemContact {
                return namingSystemContact.isGroupedAtEnd
            }
            switch comparableValue {
            case .nameValue:
                return false
            case .phoneNumber:
                return true
            case .other:
                return true
            }
        }

        fileprivate var collationString: String {
            switch comparableValue {
            case .nameValue(let value), .phoneNumber(let value):
                return value
            case .other:
                return ""
            }
        }

        func shareableAci(
            recipientDatabaseTable: RecipientDatabaseTable,
            transaction: DBReadTransaction,
        ) -> Aci? {
            guard let rowId = signalContact?.recipient.id else {
                return nil
            }
            guard
                let recipient = recipientDatabaseTable.fetchRecipient(rowId: rowId, tx: transaction),
                recipient.isRegistered
            else {
                return nil
            }
            return recipient.aci
        }

        // MARK: Searching

        private var phoneNumbers: [String] {
            var result = [String]()
            if let phoneNumber = signalContact?.recipient.phoneNumber?.stringValue {
                result.append(phoneNumber)
            }
            if let systemContact {
                result.append(contentsOf: systemContact.systemContact.phoneNumbers.map(\.value))
            }
            return result
        }

        private var emailAddresses: [String] {
            systemContact?.systemContact.emailAddresses ?? []
        }

        func matches(searchText: String) -> Bool {
            if displayName.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            if emailAddresses.contains(where: { $0.localizedCaseInsensitiveContains(searchText) }) {
                return true
            }
            let searchDigits = searchText.filteredAsE164
            guard !searchDigits.isEmpty else {
                return false
            }
            return phoneNumbers.contains { $0.filteredAsE164.contains(searchDigits) }
        }

        // MARK: Collating

        @MainActor
        func collationSection(in collation: UILocalizedIndexedCollation) -> Int {
            if isGroupedAtEnd {
                return collation.sectionTitles.firstIndex(of: "#") ?? (collation.sectionTitles.count - 1)
            }
            return collation.section(
                for: CollatableContactSharingRow(self),
                collationStringSelector: #selector(CollatableContactSharingRow.collationString),
            )
        }

        // MARK: Sorting

        struct SortKey {
            let isGroupedAtEnd: Bool
            let comparableValue: DisplayName.ComparableValue
            let comparableIdentifier: String

            static func isOrderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
                if lhs.isGroupedAtEnd != rhs.isGroupedAtEnd {
                    return !lhs.isGroupedAtEnd
                }
                return lhs.comparableValue.isLessThanOrNilIfEqual(rhs.comparableValue)
                    ?? (lhs.comparableIdentifier < rhs.comparableIdentifier)
            }
        }

        var sortKey: SortKey {
            SortKey(
                isGroupedAtEnd: isGroupedAtEnd,
                comparableValue: comparableValue,
                comparableIdentifier: comparableIdentifier,
            )
        }

        private var comparableIdentifier: String {
            switch identity {
            case .recipient(let rowId): "\(rowId)"
            case .systemContact(let cnContactId): cnContactId
            }
        }
    }

    // MARK: - SystemContactWrapper

    struct SystemContactWrapper {
        private enum Kind {
            /// Has a person's name; sorts under A-Z.
            case person
            /// Has no person's name but has a Company; listed under "#" by that.
            case business
            /// Has no name, so it's only listed when attached to a Signal contact.
            case contactInfo
        }

        let systemContact: SystemContact

        // MARK: Derived Data

        private let kind: Kind
        let displayName: String
        let comparableValue: DisplayName.ComparableValue
        let avatarNameComponents: PersonNameComponents

        /// Whether this card is listed under "#" rather than under a letter.
        var isGroupedAtEnd: Bool {
            switch kind {
            case .person: false
            case .business: true
            case .contactInfo: true
            }
        }

        var hasName: Bool {
            switch kind {
            case .person: true
            case .business: true
            case .contactInfo: false
            }
        }

        // MARK: Initialization

        /// Nil when the card has no name, no Company, no email address, and no phone
        /// number: there is nothing to list it by, so it is omitted.
        init?(
            systemContact: SystemContact,
            comparableValueConfig: DisplayName.ComparableValue.Config,
        ) {
            let kind: Kind
            let displayName: String
            let comparableValue: DisplayName.ComparableValue
            var avatarNameComponents = PersonNameComponents()

            if
                let nameComponents = Self.personNameComponents(
                    for: systemContact,
                    displayNameConfig: comparableValueConfig.displayNameConfig,
                )
            {
                let systemContactName = DisplayName.SystemContactName(
                    nameComponents: nameComponents,
                    multipleAccountLabel: nil,
                )
                kind = .person
                displayName = systemContactName.resolvedValue(config: comparableValueConfig.displayNameConfig)
                comparableValue = DisplayName.systemContactName(systemContactName).comparableValue(config: comparableValueConfig)
                avatarNameComponents = nameComponents
            } else if let organizationName = systemContact.organizationName?.strippedOrNil {
                kind = .business
                displayName = organizationName
                comparableValue = .nameValue(organizationName)
            } else if let fullName = systemContact.fullName.strippedOrNil {
                // A person named only by a middle name, prefix, or suffix: those reach
                // the formatted full name but not `firstName`/`lastName`.
                kind = .person
                displayName = fullName
                comparableValue = .nameValue(fullName)
            } else if let emailAddress = systemContact.emailAddresses.lazy.compactMap({ $0.strippedOrNil }).first {
                kind = .contactInfo
                displayName = emailAddress
                comparableValue = .nameValue(emailAddress)
            } else if let phoneNumber = systemContact.phoneNumbers.lazy.compactMap({ $0.value.strippedOrNil }).first {
                kind = .contactInfo
                displayName = phoneNumber
                comparableValue = .phoneNumber(phoneNumber)
            } else {
                return nil
            }

            if avatarNameComponents.givenName == nil, avatarNameComponents.familyName == nil {
                avatarNameComponents.givenName = displayName
            }

            self.systemContact = systemContact
            self.kind = kind
            self.displayName = displayName
            self.comparableValue = comparableValue
            self.avatarNameComponents = avatarNameComponents
        }

        // MARK: Functionality

        func canonicalPhoneNumbers(
            localPhoneNumber: CanonicalPhoneNumber?,
            phoneNumberUtil: PhoneNumberUtil,
        ) -> Set<CanonicalPhoneNumber> {
            Set(
                FetchedSystemContacts.parsePhoneNumbers(
                    for: systemContact,
                    phoneNumberUtil: phoneNumberUtil,
                    localPhoneNumber: localPhoneNumber,
                ),
            )
        }

        var contactName: OWSContactName {
            guard hasName else {
                return OWSContactName(givenName: displayName)
            }
            return OWSContactName(
                givenName: systemContact.firstName.strippedOrNil,
                familyName: systemContact.lastName.strippedOrNil,
                nickname: systemContact.nickname.strippedOrNil,
                organizationName: systemContact.organizationName?.strippedOrNil,
            )
        }

        /// A share built without the address book card, for when it has gone away
        /// since the list was loaded. It carries everything `SystemContact` retains,
        /// which is everything but postal addresses and the avatar.
        func contactShareDraft(phoneNumberUtil: PhoneNumberUtil) -> ContactShareDraft {
            ContactShareDraft(
                name: contactName,
                addresses: [],
                emails: systemContact.emailAddresses.map {
                    OWSContactEmail(type: .custom, email: $0)
                },
                phoneNumbers: systemContact.phoneNumbers.map {
                    OWSContactPhoneNumber(
                        type: .custom,
                        label: $0.label,
                        phoneNumber: phoneNumberUtil
                            .parsePhoneNumber(userSpecifiedText: $0.value)?.e164 ?? $0.value,
                    )
                },
                aci: nil,
                signalNote: nil,
                existingAvatarAttachment: nil,
                avatarImageData: nil,
            )
        }

        // MARK: Helpers

        private static func personNameComponents(
            for systemContact: SystemContact,
            displayNameConfig: DisplayName.Config,
        ) -> PersonNameComponents? {
            var nameComponents = PersonNameComponents()
            nameComponents.givenName = systemContact.firstName.strippedOrNil
            nameComponents.familyName = systemContact.lastName.strippedOrNil
            nameComponents.nickname = systemContact.nickname.strippedOrNil

            guard
                nameComponents.givenName != nil
                || nameComponents.familyName != nil
                || (displayNameConfig.shouldUseSystemContactNicknames && nameComponents.nickname != nil)
            else {
                return nil
            }
            return nameComponents
        }
    }
}

// MARK: - Private Helpers

private extension OWSContactName {
    convenience init(components: PersonNameComponents) {
        self.init(
            givenName: components.givenName,
            familyName: components.familyName,
            middleName: components.middleName,
            nickname: components.nickname,
        )
    }
}

private extension Publisher where Failure == Never {
    func debounce<S: Combine.Scheduler>(
        for interval: S.SchedulerTimeType.Stride,
        scheduler: S,
        immediatelyWhen isImmediate: @escaping (Output) -> Bool,
    ) -> AnyPublisher<Output, Never> {
        map { output -> AnyPublisher<Output, Never> in
            guard !isImmediate(output) else {
                return Just(output).eraseToAnyPublisher()
            }
            return Just(output)
                .delay(for: interval, scheduler: scheduler)
                .eraseToAnyPublisher()
        }
        .switchToLatest()
        .eraseToAnyPublisher()
    }
}

private class CollatableContactSharingRow: NSObject {
    private let value: String

    init(_ row: ContactSharingPickerViewModel.Row) {
        self.value = row.collationString
    }

    @objc
    func collationString() -> String {
        value
    }
}
