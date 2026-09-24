//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import Contacts
import LibSignalClient
import Testing
import UIKit

@testable import SignalServiceKit
@testable import SignalUI

@MainActor
struct ContactSharingPickerViewModelTests {

    private let db = InMemoryDB()
    private let phoneNumberVisibilityFetcher = MockPhoneNumberVisibilityFetcher()
    private let providers = StubbedProviders()
    private let recipientHidingManager = MockRecipientHidingManager()
    private let localAci = LocalIdentifiers.forUnitTests.aci

    /// Pinned so that tests don't depend on the device's name-display settings.
    private let comparableValueConfig = DisplayName.ComparableValue.Config(
        displayNameConfig: DisplayName.Config(shouldUseSystemContactNicknames: false),
        shouldSortByGivenName: true,
    )

    // MARK: - Initial State

    @Test
    func testInitialStateIsInitial() {
        #expect(makeViewModel().state.isInitial)
    }

    @Test
    func testLoadSetsLoadedState() {
        let viewModel = makeViewModel()
        viewModel.loadData()

        switch viewModel.state {
        case .loaded:
            break
        case .initial:
            Issue.record("Expected the loaded state.")
        }
    }

    // MARK: - Signal Contacts

    @Test
    func testWhitelistedRegisteredRecipientsAreListed() async throws {
        addContact(named: "Alice")
        addContact(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let displayedRows = try await displayedRows(of: viewModel)
        #expect(displayedRows.rows.map(\.displayName) == ["Alice", "Bob"])
    }

    @Test
    func testUnregisteredRecipientsAreExcluded() async throws {
        addContact(named: "Alice")
        addContact(named: "Gone", isRegistered: false)

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice"], "A deregistered contact isn't a Signal contact.")
    }

    @Test
    func testBlockedRecipientsAreExcluded() async throws {
        addContact(named: "Alice")
        let blocked = addContact(named: "Bob")
        providers.blockedRecipientIds.insert(blocked.id)

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice"])
    }

    @Test
    func testHiddenRecipientsAreExcluded() async throws {
        addContact(named: "Alice")
        let hidden = addContact(named: "Bob")
        recipientHidingManager.hiddenRecipients.append(hidden)

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice"])
    }

    @Test
    func testARegisteredRecipientShowsTheContactIcon() async throws {
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.shouldShowContactIcon, "There's an ACI to share, so the row is marked.")
    }

    @Test
    func testAnAddressBookOnlyRowShowsNoContactIcon() async throws {
        providers.systemContacts = [makeSystemContact(givenName: "Dave", phoneNumber: "+16505550199")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(!row.shouldShowContactIcon, "No Signal account, so no ACI to share.")
    }

    // MARK: - Your Own Contact

    @Test
    func testYourOwnContactIsListedLikeAnyOther() async throws {
        addContact(named: "Alice")
        addContact(named: "Me", aci: localAci, isWhitelisted: false)

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(
            try await names(of: viewModel) == ["Alice", "Me"],
            "Your own contact is shareable, and sorts by name rather than being pinned.",
        )
    }

    @Test
    func testYourOwnContactIsNotDuplicatedWhenAlreadyWhitelisted() async throws {
        addContact(named: "Me", aci: localAci)

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Me"])
    }

    @Test
    func testYourOwnCardMergesOntoYourOwnRow() async throws {
        let localRecipient = addContact(named: "Me", aci: localAci, phoneNumber: "+16505550100")
        providers.systemContacts = [
            makeSystemContact(givenName: "My", familyName: "Self", phoneNumber: "+16505550100"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["My Self"], "The card names the row, and there is only one row.")
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.recipient?.id == localRecipient.id)
        #expect(row.systemContact != nil)
    }

    @Test
    func testYourOwnRowStandsAloneWithoutACard() async throws {
        addContact(named: "Me", aci: localAci, phoneNumber: "+16505550100")

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Me"])
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.systemContact == nil)
    }

    @Test
    func testACardWithNoPhoneNumberCannotMergeAndAppearsTwice() async throws {
        addContact(named: "Me", aci: localAci, phoneNumber: "+16505550100")
        providers.systemContacts = [makeSystemContact(givenName: "My", familyName: "Self")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(
            try await names(of: viewModel) == ["Me", "My Self"],
            "Phone number is the only match key, so a numberless card can't merge.",
        )
    }

    @Test
    func testAPhonelessAccountCannotMergeWithItsCard() async throws {
        addContact(named: "Me", aci: localAci, phoneNumber: nil)
        providers.systemContacts = [
            makeSystemContact(givenName: "My", familyName: "Self", phoneNumber: "+16505550100"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Me", "My Self"])
    }

    // MARK: - Merging

    @Test
    func testASystemContactMergesOntoAMatchingRecipient() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.systemContacts = [
            makeSystemContact(givenName: "Alicia", phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alicia"], "The address book card names the merged row.")
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.recipient != nil)
        #expect(row.systemContact != nil)
    }

    @Test
    func testAnUnmatchedCardBecomesItsOwnRow() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.systemContacts = [
            makeSystemContact(givenName: "Dave", phoneNumber: "+16505550199"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice", "Dave"])
    }

    @Test
    func testACardForAnUnregisteredRecipientStandsAlone() async throws {
        addContact(named: "Gone", phoneNumber: "+16505550101", isRegistered: false)
        providers.systemContacts = [
            makeSystemContact(givenName: "Gina", phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Gina"])
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.recipient == nil, "A former Signal user's card doesn't merge onto their old recipient.")
        #expect(!row.shouldShowContactIcon, "Their old ACI isn't shareable.")
    }

    @Test
    func testANamelessCardKeepsTheSignalName() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.systemContacts = [
            makeSystemContact(phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice"], "A card with no name shouldn't rename the row.")
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.systemContact != nil, "It's still attached, just not naming the row.")
    }

    @Test
    func testACardMatchingTwoRecipientsIsNotAlsoItsOwnRow() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        addContact(named: "Bob", phoneNumber: "+16505550102")
        providers.systemContacts = [
            makeSystemContact(givenName: "Shared", phoneNumbers: ["+16505550101", "+16505550102"]),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(
            try await displayedRows(of: viewModel).rows.count == 2,
            "Both recipients are listed, and the card they share isn't duplicated as a third row.",
        )
        #expect(try await names(of: viewModel) == ["Shared", "Shared"], "The card names both rows it's attached to.")
    }

    @Test
    func testABlockedRecipientsCardIsExcludedToo() async throws {
        addContact(named: "Alice")
        let blocked = addContact(named: "Bob", phoneNumber: "+16505550101")
        providers.blockedRecipientIds.insert(blocked.id)
        providers.systemContacts = [
            makeSystemContact(givenName: "Bobby", phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(
            try await names(of: viewModel) == ["Alice"],
            "Blocking someone shouldn't leave their address book card behind to share.",
        )
    }

    @Test
    func testAHiddenRecipientsCardIsExcludedToo() async throws {
        addContact(named: "Alice")
        let hidden = addContact(named: "Bob", phoneNumber: "+16505550101")
        recipientHidingManager.hiddenRecipients.append(hidden)
        providers.systemContacts = [
            makeSystemContact(givenName: "Bobby", phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Alice"])
    }

    @Test
    func testAnUnrelatedCardSurvivesAnExclusion() async throws {
        let blocked = addContact(named: "Bob", phoneNumber: "+16505550101")
        providers.blockedRecipientIds.insert(blocked.id)
        providers.systemContacts = [
            makeSystemContact(givenName: "Bobby", phoneNumber: "+16505550101"),
            makeSystemContact(givenName: "Dave", phoneNumber: "+16505550199"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Dave"], "Only the blocked contact's card is dropped.")
    }

    // MARK: - Sorting

    @Test
    func testBusinessesAreGroupedAtEndAfterPeople() async throws {
        providers.systemContacts = [
            makeSystemContact(organizationName: "Acme Plumbing"),
            makeSystemContact(givenName: "Zoe"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Zoe", "Acme Plumbing"])
        #expect(try await groupedAtEnd(of: viewModel) == [false, true])
    }

    @Test
    func testNamelessCardsSortLast() async throws {
        providers.systemContacts = [
            makeSystemContact(phoneNumber: "+16505550199"),
            makeSystemContact(givenName: "Zoe"),
            makeSystemContact(organizationName: "Acme Plumbing"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await names(of: viewModel) == ["Zoe", "Acme Plumbing", "+16505550199"])
    }

    @Test
    func testRowsWithEqualNamesGetAStableOrder() async throws {
        addContact(named: "Alice")
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let firstPass = try await displayedRows(of: viewModel).rows.map(\.identity)
        viewModel.loadData()
        let secondPass = try await displayedRows(of: viewModel).rows.map(\.identity)

        #expect(firstPass == secondPass, "The row id tiebreaker has to make the sort total.")
    }

    // MARK: - Publishing

    @Test
    func testThePublisherReplaysTheCurrentRowsOnSubscribe() {
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        var emissions = [ContactSharingPickerViewModel.DisplayedRows]()
        let cancellable = viewModel.displayedRowsPublisher.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        #expect(emissions.count == 1, "Subscribing replays whatever the current state is.")
        #expect(emissions[0].rows.isEmpty, "Nothing has loaded yet.")
    }

    @Test
    func testThePublisherEmitsWhenDataLoads() {
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        var emissions = [ContactSharingPickerViewModel.DisplayedRows]()
        let cancellable = viewModel.displayedRowsPublisher.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        viewModel.loadData()

        #expect(emissions.count == 2)
        #expect(emissions.last?.rows.map(\.displayName) == ["Alice"])
    }

    // MARK: - Collating

    @Test
    func testABusinessIsGroupedAtEndRatherThanUnderItsFirstLetter() async throws {
        providers.systemContacts = [makeSystemContact(organizationName: "Acme Plumbing")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        let collation = UILocalizedIndexedCollation.current()
        #expect(
            row.collationSection(in: collation) == collation.sectionTitles.firstIndex(of: "#"),
            "Collating by name alone would file this under \"A\".",
        )
    }

    @Test
    func testANamelessCardIsGroupedAtEnd() async throws {
        providers.systemContacts = [makeSystemContact(phoneNumber: "+16505550199")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        let collation = UILocalizedIndexedCollation.current()
        #expect(row.collationSection(in: collation) == collation.sectionTitles.firstIndex(of: "#"))
    }

    @Test
    func testAPersonIsNotGroupedAtEnd() async throws {
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        let collation = UILocalizedIndexedCollation.current()
        #expect(row.collationSection(in: collation) != collation.sectionTitles.firstIndex(of: "#"))
    }

    // MARK: - Searching

    @Test
    func testSearchFiltersByName() async throws {
        addContact(named: "Alice")
        addContact(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()
        viewModel.setSearchText("ali")

        #expect(try await names(of: viewModel) == ["Alice"], "Search is case-insensitive and matches prefixes.")
    }

    @Test
    func testSearchFiltersByPhoneNumber() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        addContact(named: "Bob", phoneNumber: "+16505550199")

        let viewModel = makeViewModel()
        viewModel.loadData()
        viewModel.setSearchText("555-0101")

        #expect(try await names(of: viewModel) == ["Alice"], "Punctuation in the query shouldn't matter.")
    }

    @Test
    func testSearchFiltersByEmailAddress() async throws {
        providers.systemContacts = [
            makeSystemContact(givenName: "Alice", emailAddresses: ["alice@example.com"]),
            makeSystemContact(givenName: "Bob", emailAddresses: ["bob@example.com"]),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()
        viewModel.setSearchText("bob@")

        #expect(try await names(of: viewModel) == ["Bob"])
    }

    @Test
    func testClearingSearchRestoresEveryRow() async throws {
        addContact(named: "Alice")
        addContact(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()
        viewModel.setSearchText("ali")
        viewModel.setSearchText("")

        #expect(try await names(of: viewModel) == ["Alice", "Bob"])
    }

    @Test
    func testSearchDoesNotReadTheDatabase() async throws {
        addContact(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()
        let readsAfterLoad = providers.displayNamesFetchCount

        viewModel.setSearchText("ali")
        _ = try await displayedRows(of: viewModel).rows

        #expect(providers.displayNamesFetchCount == readsAfterLoad, "Filtering happens in memory.")
    }

    // MARK: - Reloading

    @Test
    func testTheAddressBookIsReadOncePerLoad() async throws {
        addContact(named: "Alice")
        providers.systemContacts = [makeSystemContact(givenName: "Dave", phoneNumber: "+16505550199")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(providers.fetchSystemContactsCount == 1)
        #expect(try await names(of: viewModel) == ["Alice", "Dave"])
    }

    // MARK: - Sharing

    @Test
    func testASignalOnlyRowIsNamedByTheProfile() async throws {
        let recipient = addContact(named: "Alice")
        providers.displayNames[recipient.id] = .profileName(makeNameComponents(givenName: "Alice", familyName: "Adams"))

        let viewModel = makeViewModel()
        viewModel.loadData()

        let contactName = try await contactShareDraft(forFirstRowOf: viewModel).name
        #expect(contactName.givenName == "Alice")
        #expect(contactName.familyName == "Adams")
    }

    @Test
    func testANamedCardNamesTheShare() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.systemContacts = [
            makeSystemContact(givenName: "Alicia", phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await contactShareDraft(forFirstRowOf: viewModel).name.givenName == "Alicia")
    }

    @Test
    func testANamelessCardLeavesTheProfileNamingTheShare() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.systemContacts = [
            makeSystemContact(phoneNumber: "+16505550101"),
        ]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await contactShareDraft(forFirstRowOf: viewModel).name.givenName == "Alice")
    }

    @Test
    func testAnAddressBookOnlyRowIsNamedByItsCard() async throws {
        providers.systemContacts = [makeSystemContact(givenName: "Dave", phoneNumber: "+16505550199")]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await contactShareDraft(forFirstRowOf: viewModel).name.givenName == "Dave")
    }

    @Test
    func testARowWithoutNameComponentsFallsBackToItsDisplayName() async throws {
        let recipient = addContact(named: "Alice", phoneNumber: "+16505550101")
        providers.displayNames[recipient.id] = .username("alice.42")

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(try await contactShareDraft(forFirstRowOf: viewModel).name.givenName == "alice.42")
    }

    @Test
    func testAPrivateNicknameNamesTheRowButNotTheShare() async throws {
        let recipient = addContact(named: "Bob")
        providers.displayNames[recipient.id] = .nickname(
            try #require(ProfileName(givenName: "Bob", familyName: "(landlord)")),
        )
        providers.userProfiles[recipient.id] = makeUserProfile(givenName: "Robert", familyName: "Tables")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        #expect(row.displayName == "Bob (landlord)", "The row shows what the user calls them.")

        let contactName = viewModel.contactShareDraft(for: row).name
        #expect(
            contactName.givenName == "Robert" && contactName.familyName == "Tables",
            "A share carries the name they publish, never the user's private nickname.",
        )
    }

    @Test
    func testANicknameWithoutAProfileNameIsNotShared() async throws {
        let recipient = addContact(named: "Bob")
        providers.displayNames[recipient.id] = .nickname(
            try #require(ProfileName(givenName: "Bob", familyName: "(landlord)")),
        )

        let viewModel = makeViewModel()
        viewModel.loadData()

        let contactName = try await contactShareDraft(forFirstRowOf: viewModel).name
        #expect(contactName.givenName == CommonStrings.unknownUser)
        #expect(contactName.familyName == nil, "No part of the private nickname reaches the share.")
    }

    @Test
    func testProfileNamesAreOnlyFetchedWhenSharing() async throws {
        let recipient = addContact(named: "Bob")
        providers.displayNames[recipient.id] = .nickname(
            try #require(ProfileName(givenName: "Bob", familyName: "(landlord)")),
        )

        let viewModel = makeViewModel()
        viewModel.loadData()
        #expect(providers.userProfileFetchCount == 0, "Loading the list shouldn't read profiles.")

        _ = try await contactShareDraft(forFirstRowOf: viewModel)
        #expect(providers.userProfileFetchCount == 1)
    }

    @Test
    func testAVisiblePhoneNumberIsShared() async throws {
        addContact(named: "Alice", phoneNumber: "+16505550101")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let phoneNumbers = try await contactShareDraft(forFirstRowOf: viewModel).phoneNumbers
        #expect(phoneNumbers.map(\.phoneNumber) == ["+16505550101"])
    }

    @Test
    func testAHiddenPhoneNumberIsNotShared() async throws {
        let aci = Aci.randomForTesting()
        addContact(named: "Alice", aci: aci, phoneNumber: "+16505550101")
        phoneNumberVisibilityFetcher.acisWithHiddenPhoneNumbers = [aci]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(
            try await contactShareDraft(forFirstRowOf: viewModel).phoneNumbers.isEmpty,
            "A number its owner hides must not reach a contact share.",
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> ContactSharingPickerViewModel {
        let providers = providers
        let comparableValueConfig = comparableValueConfig
        return ContactSharingPickerViewModel(
            avatarBuilder: AvatarBuilder(appReadiness: AppReadinessMock()),
            blockedRecipientIdentifiersProvider: { _ in providers.blockedRecipientIds },
            comparableValueConfigProvider: { comparableValueConfig },
            contactManager: FakeContactsManager(),
            contactsSharingAuthorizationProvider: { .authorized },
            db: db,
            displayNamesForRecipientsProvider: { recipients, _ in providers.displayNames(for: recipients) },
            phoneNumberUtil: PhoneNumberUtil(),
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            profileManager: OWSFakeProfileManager(),
            recipientDatabaseTable: RecipientDatabaseTable(),
            recipientHidingManager: recipientHidingManager,
            recipientManager: SignalRecipientManagerImpl(
                phoneNumberVisibilityFetcher: MockPhoneNumberVisibilityFetcher(),
                recipientDatabaseTable: RecipientDatabaseTable(),
                storageServiceManager: FakeStorageServiceManager(),
            ),
            searchDebounceInterval: .zero,
            systemContactsProvider: { _ in providers.fetchSystemContacts() },
            tsAccountManager: MockTSAccountManager(),
            userProfileProvider: { recipient, _ in providers.userProfile(for: recipient) },
        )
    }

    private func displayedRows(
        of viewModel: ContactSharingPickerViewModel,
    ) async throws -> ContactSharingPickerViewModel.DisplayedRows {
        try #require(await viewModel.displayedRowsPublisher.values.first(where: { _ in true }))
    }

    private func contactShareDraft(
        forFirstRowOf viewModel: ContactSharingPickerViewModel,
    ) async throws -> ContactShareDraft {
        let row = try #require(try await displayedRows(of: viewModel).rows.first)
        return viewModel.contactShareDraft(for: row)
    }

    private func names(of viewModel: ContactSharingPickerViewModel) async throws -> [String] {
        try await displayedRows(of: viewModel).rows.map(\.displayName)
    }

    private func groupedAtEnd(of viewModel: ContactSharingPickerViewModel) async throws -> [Bool] {
        try await displayedRows(of: viewModel).rows.map(\.isGroupedAtEnd)
    }

    @discardableResult
    private func addContact(
        named givenName: String,
        aci: Aci = Aci.randomForTesting(),
        phoneNumber: String? = nil,
        isRegistered: Bool = true,
        isWhitelisted: Bool = true,
    ) -> SignalRecipient {
        let recipient = db.write { tx in
            try! SignalRecipient.insertRecord(
                aci: aci,
                phoneNumber: phoneNumber.flatMap { E164($0) },
                deviceIds: isRegistered ? [DeviceId(validating: 1)!] : [],
                status: isWhitelisted ? .whitelisted : .unspecified,
                tx: tx,
            )
        }

        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        providers.displayNames[recipient.id] = .profileName(nameComponents)

        return recipient
    }

    private func makeNameComponents(givenName: String, familyName: String? = nil) -> PersonNameComponents {
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        nameComponents.familyName = familyName
        return nameComponents
    }

    private func makeUserProfile(givenName: String, familyName: String) -> OWSUserProfile {
        OWSUserProfile(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: nil,
            phoneNumber: nil,
            avatarFileName: nil,
            avatarUrlPath: nil,
            profileKey: nil,
            givenName: givenName,
            familyName: familyName,
            bio: nil,
            bioEmoji: nil,
            badges: [],
            lastFetchDate: nil,
            lastMessagingDate: nil,
            isPhoneNumberShared: nil,
            hasPaymentAddress: nil,
        )
    }

    private func makeSystemContact(
        givenName: String = "",
        middleName: String = "",
        familyName: String = "",
        organizationName: String = "",
        phoneNumber: String? = nil,
        phoneNumbers: [String] = [],
        emailAddresses: [String] = [],
    ) -> SystemContact {
        let cnContact = CNMutableContact()
        cnContact.givenName = givenName
        cnContact.middleName = middleName
        cnContact.familyName = familyName
        cnContact.organizationName = organizationName
        cnContact.phoneNumbers = (phoneNumber.map { [$0] } ?? phoneNumbers).map {
            CNLabeledValue(label: CNLabelHome, value: CNPhoneNumber(stringValue: $0))
        }
        cnContact.emailAddresses = emailAddresses.map {
            CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
        }
        return SystemContact(cnContact: cnContact)
    }
}

// MARK: - StubbedProviders

private final class StubbedProviders {

    var blockedRecipientIds: Set<SignalRecipient.RowId> = []
    var systemContacts: [SystemContact] = []

    /// Recipients without an entry here resolve to `.unknown`.
    var displayNames: [SignalRecipient.RowId: DisplayName] = [:]

    var userProfiles: [SignalRecipient.RowId: OWSUserProfile] = [:]

    private(set) var displayNamesFetchCount = 0
    private(set) var fetchSystemContactsCount = 0
    private(set) var userProfileFetchCount = 0

    func displayNames(for recipients: [SignalRecipient]) -> [DisplayName] {
        displayNamesFetchCount += 1
        return recipients.map { displayNames[$0.id] ?? .unknown }
    }

    func userProfile(for recipient: SignalRecipient) -> OWSUserProfile? {
        userProfileFetchCount += 1
        return userProfiles[recipient.id]
    }

    func fetchSystemContacts() -> [SystemContact] {
        fetchSystemContactsCount += 1
        return systemContacts
    }
}

// MARK: - MockRecipientHidingManager

private final class MockRecipientHidingManager: RecipientHidingManager {

    var hiddenRecipients: [SignalRecipient] = []

    func hiddenRecipients(tx: DBReadTransaction) -> [SignalRecipient] {
        hiddenRecipients
    }

    func fetchHiddenRecipient(recipientId: SignalRecipient.RowId, tx: DBReadTransaction) -> HiddenRecipient? {
        owsFail("Not implemented.")
    }

    func isHiddenRecipientThreadInMessageRequest(
        hiddenRecipient: HiddenRecipient,
        contactThread: TSContactThread?,
        tx: DBReadTransaction,
    ) -> Bool {
        owsFail("Not implemented.")
    }

    func addHiddenRecipient(
        _ recipient: inout SignalRecipient,
        inKnownMessageRequestState: Bool,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    func removeHiddenRecipient(
        _ recipient: inout SignalRecipient,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }
}
