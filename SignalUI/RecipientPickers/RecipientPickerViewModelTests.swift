//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import LibSignalClient
import Testing

@testable import SignalServiceKit
@testable import SignalUI

private extension RecipientPickerViewModel.State {
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

@MainActor
struct RecipientPickerViewModelTests {

    private let db = InMemoryDB()
    private let dataSource = MockDataSource()
    private let contactsViewHelper = ContactsViewHelper()

    /// Addresses must be built against an explicit cache; the convenience
    /// initializers reach for `SSKEnvironment.shared`, which tests don't have.
    private let addressCache = SignalServiceAddressCache()

    init() {
        dataSource.localAddressToReturn = makeAddress()
    }

    // MARK: - Initial State

    @Test
    func testInitialStateIsInitial() {
        let viewModel = makeViewModel()

        #expect(viewModel.state.isInitial)
        #expect(loadedData(of: viewModel) == nil)
    }

    @Test
    func testLoadDataPublishesInitialThenLoaded() {
        let viewModel = makeViewModel()

        var states: [RecipientPickerViewModel.State] = []
        var cancellables: Set<AnyCancellable> = []
        viewModel.statePublisher.sink { states.append($0) }.store(in: &cancellables)

        #expect(states.count == 1, "CurrentValueSubject should replay the current state on subscribe.")
        #expect(states[0].isInitial)

        viewModel.loadData()

        #expect(states.count == 2)
        #expect(states[1].isLoaded)
    }

    @Test
    func testReloadPublishesLoadedAgain() {
        let viewModel = makeViewModel()
        viewModel.loadData()

        var states: [RecipientPickerViewModel.State] = []
        var cancellables: Set<AnyCancellable> = []
        viewModel.statePublisher.sink { states.append($0) }.store(in: &cancellables)

        viewModel.contactsViewHelperDidUpdateContacts()

        #expect(states.count == 2, "A reload should go straight from loaded to loaded.")
        #expect(states.allSatisfy { $0.isLoaded })
    }

    // MARK: - Recipients

    @Test
    func testLoadedRecipientsAreWhitelistedConnections() {
        let alice = addConnection(named: "Alice")
        let bob = addConnection(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice, bob])
    }

    @Test
    func testBlockedAddressesAreExcluded() {
        let alice = addConnection(named: "Alice")
        let bob = addConnection(named: "Bob")
        dataSource.blocked = [bob]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice])
    }

    @Test
    func testHiddenAddressesAreExcluded() {
        let alice = addConnection(named: "Alice")
        let bob = addConnection(named: "Bob")
        dataSource.hidden = [alice]

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [bob])
    }

    @Test
    func testRecipientsWithoutKnownDisplayNamesAreExcluded() {
        let alice = addConnection(named: "Alice")

        let deleted = makeAddress()
        dataSource.whitelisted.append(deleted)
        dataSource.displayNames[deleted] = .deletedAccount

        let unknown = makeAddress()
        dataSource.whitelisted.append(unknown)
        dataSource.displayNames[unknown] = .unknown

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice])
    }

    @Test
    func testRecipientsPreserveDataSourceOrdering() {
        // Added out of order; the data source sorts by display name.
        let carol = addConnection(named: "Carol")
        let alice = addConnection(named: "Alice")
        let bob = addConnection(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice, bob, carol])
    }

    @Test
    func testRecipientsMapToPickedRecipients() {
        let alice = addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()

        let recipients = loadedData(of: viewModel)?.recipients ?? []
        #expect(recipients.map { $0.pickedRecipient.address } == [alice])
        #expect(recipients.map { $0.comparableDisplayName.address } == [alice])
    }

    // MARK: - Local Recipient

    @Test
    func testLocalRecipientIsExcludedWhenHidden() throws {
        let localAddress = try #require(dataSource.localAddressToReturn)
        let alice = addConnection(named: "Alice")
        addConnection(named: "Me", address: localAddress)

        let viewModel = makeViewModel(shouldHideLocalRecipient: true)
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice])
    }

    @Test
    func testLocalRecipientIsIncludedWhenNotHiddenEvenIfNotWhitelisted() throws {
        let alice = addConnection(named: "Alice")
        let localAddress = try #require(dataSource.localAddressToReturn)
        // Deliberately not whitelisted: it should be added back in regardless.
        dataSource.displayNames[localAddress] = displayName(givenName: "Zoe")

        let viewModel = makeViewModel(shouldHideLocalRecipient: false)
        viewModel.loadData()

        #expect(addresses(of: viewModel) == [alice, localAddress])
    }

    // MARK: - Signal Connection Lookup

    @Test
    func testLoadedDataContainsSignalConnectionAddresses() throws {
        let alice = addConnection(named: "Alice")
        let stranger = makeAddress()

        let viewModel = makeViewModel()
        viewModel.loadData()

        let loaded = try #require(loadedData(of: viewModel))
        #expect(loaded.contains(address: alice))
        #expect(!loaded.contains(address: stranger))
    }

    @Test
    func testFilteredRecipientsAreNotSignalConnections() throws {
        let blocked = addConnection(named: "Blocked")
        dataSource.blocked = [blocked]

        let viewModel = makeViewModel()
        viewModel.loadData()

        let loaded = try #require(loadedData(of: viewModel))
        #expect(!loaded.contains(address: blocked))
    }

    // MARK: - Contact Updates

    @Test
    func testContactsUpdateReloadsAfterInitialLoad() {
        let alice = addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()
        #expect(addresses(of: viewModel) == [alice])

        let bob = addConnection(named: "Bob")
        viewModel.contactsViewHelperDidUpdateContacts()

        #expect(addresses(of: viewModel) == [alice, bob])
    }

    @Test
    func testContactsUpdateIsIgnoredBeforeInitialLoad() {
        addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.contactsViewHelperDidUpdateContacts()

        #expect(viewModel.state.isInitial, "An update before the first load shouldn't start one.")
        #expect(dataSource.sortRequests.isEmpty, "The database shouldn't have been read.")
    }

    @Test
    func testContactsUpdateExcludesNewlyBlockedAddress() {
        let alice = addConnection(named: "Alice")
        let bob = addConnection(named: "Bob")

        let viewModel = makeViewModel()
        viewModel.loadData()
        #expect(addresses(of: viewModel) == [alice, bob])

        dataSource.blocked = [alice]
        viewModel.contactsViewHelperDidUpdateContacts()

        #expect(addresses(of: viewModel) == [bob])
    }

    // MARK: - Reusing Loaded Signal Connections

    @Test
    func testReloadWithoutSignalConnectionsReusesLoadedData() {
        let alice = addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()
        #expect(dataSource.sortRequests.count == 1)

        // Changes that a real reload would pick up.
        addConnection(named: "Bob")
        dataSource.blocked = [alice]

        viewModel.loadData(loadSignalConnections: false)

        #expect(addresses(of: viewModel) == [alice], "Signal Connections should have been reused.")
        #expect(dataSource.sortRequests.count == 1, "The database shouldn't have been read again.")
    }

    @Test
    func testReloadWithoutSignalConnectionsReusesConnectionAddresses() throws {
        let alice = addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()

        viewModel.loadData(loadSignalConnections: false)

        let loaded = try #require(loadedData(of: viewModel))
        #expect(loaded.contains(address: alice))
    }

    @Test
    func testLoadingWithoutSignalConnectionsBeforeInitialLoadProducesNoRecipients() {
        addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData(loadSignalConnections: false)

        #expect(loadedData(of: viewModel) != nil, "The load should still finish.")
        #expect(addresses(of: viewModel) == [], "There are no Signal Connections to reuse yet.")
        #expect(dataSource.sortRequests.isEmpty, "The database shouldn't have been read.")
    }

    @Test
    func testSignalConnectionsAreReloadableAfterBeingReused() {
        let alice = addConnection(named: "Alice")

        let viewModel = makeViewModel()
        viewModel.loadData()
        viewModel.loadData(loadSignalConnections: false)

        let bob = addConnection(named: "Bob")
        viewModel.loadData(loadSignalConnections: true)

        #expect(addresses(of: viewModel) == [alice, bob])
    }

    // MARK: - Helpers

    private func makeViewModel(shouldHideLocalRecipient: Bool = true) -> RecipientPickerViewModel {
        return RecipientPickerViewModel(
            contactsViewHelper: contactsViewHelper,
            dataSource: dataSource,
            db: db,
            shouldHideLocalRecipient: shouldHideLocalRecipient,
        )
    }

    private func loadedData(of viewModel: RecipientPickerViewModel) -> RecipientPickerViewModel.LoadedData? {
        guard case .loaded(let loadedData) = viewModel.state else { return nil }
        return loadedData
    }

    private func addresses(of viewModel: RecipientPickerViewModel) -> [SignalServiceAddress] {
        return loadedData(of: viewModel)?.recipients.map { $0.comparableDisplayName.address } ?? []
    }

    private func displayName(givenName: String) -> DisplayName {
        var nameComponents = PersonNameComponents()
        nameComponents.givenName = givenName
        return .profileName(nameComponents)
    }

    private func makeAddress() -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: Aci.randomForTesting(),
            phoneNumber: nil,
            cache: addressCache,
        )
    }

    @discardableResult
    private func addConnection(
        named givenName: String,
        address: SignalServiceAddress? = nil,
    ) -> SignalServiceAddress {
        let address = address ?? makeAddress()
        dataSource.whitelisted.append(address)
        dataSource.displayNames[address] = displayName(givenName: givenName)
        return address
    }
}

// MARK: - MockDataSource

private final class MockDataSource: RecipientPickerViewModelDataSource {

    var whitelisted: [SignalServiceAddress] = []
    var blocked: Set<SignalServiceAddress> = []
    var hidden: Set<SignalServiceAddress> = []
    var localAddressToReturn: SignalServiceAddress?

    /// Addresses without an entry here resolve to `.unknown`.
    var displayNames: [SignalServiceAddress: DisplayName] = [:]

    /// The addresses passed to `sortedComparableNames(for:tx:)`, oldest first.
    private(set) var sortRequests: [Set<SignalServiceAddress>] = []

    func whitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        return whitelisted
    }

    func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        return blocked
    }

    func hiddenAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        return hidden
    }

    func localRecipientAddress(tx: DBReadTransaction) -> SignalServiceAddress? {
        return localAddressToReturn
    }

    func sortedComparableNames(
        for addresses: [SignalServiceAddress],
        tx: DBReadTransaction,
    ) -> [ComparableDisplayName] {
        sortRequests.append(Set(addresses))

        let config = DisplayName.ComparableValue.Config(
            displayNameConfig: DisplayName.Config(shouldUseSystemContactNicknames: false),
            shouldSortByGivenName: true,
        )
        return addresses.map { address in
            ComparableDisplayName(
                address: address,
                displayName: displayNames[address] ?? .unknown,
                config: config,
            )
        }.sorted(by: <)
    }
}
