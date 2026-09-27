//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
import SignalServiceKit

@MainActor
final class RecipientPickerViewModel: @MainActor ContactsViewHelperObserver {

    // MARK: - Related Types

    enum Recipient {
        case signalConnection(ComparableDisplayName)

        var pickedRecipient: PickedRecipient {
            switch self {
            case .signalConnection(let signalConnection):
                PickedRecipient.for(address: signalConnection.address)
            }
        }

        var comparableDisplayName: ComparableDisplayName {
            switch self {
            case .signalConnection(let signalConnection):
                signalConnection
            }
        }
    }

    // MARK: - Configuration

    private let shouldHideLocalRecipient: Bool

    // MARK: - Dependencies

    private let dataSource: any RecipientPickerViewModelDataSource
    private let db: any DB

    // MARK: - State

    struct LoadedData {
        fileprivate var signalConnections: [ComparableDisplayName]
        fileprivate var signalConnectionAddresses: Set<SignalServiceAddress>

        func contains(address: SignalServiceAddress) -> Bool {
            signalConnectionAddresses.contains(address)
        }

        var recipients: [Recipient]
    }

    enum State {
        case initial
        case loaded(LoadedData)

        var isInitial: Bool {
            switch self {
            case .initial: return true
            default: return false
            }
        }
    }

    private var stateSubject = CurrentValueSubject<State, Never>(.initial)
    var statePublisher: AnyPublisher<State, Never> { stateSubject.eraseToAnyPublisher() }
    var state: State { stateSubject.value }

    // MARK: - Lifecycle

    init(
        contactsViewHelper: ContactsViewHelper = SUIEnvironment.shared.contactsViewHelperRef,
        dataSource: any RecipientPickerViewModelDataSource = RecipientPickerViewModelDataSourceImpl(),
        db: any DB = SSKEnvironment.shared.databaseStorageRef,
        shouldHideLocalRecipient: Bool = true,
    ) {
        self.dataSource = dataSource
        self.db = db
        self.shouldHideLocalRecipient = shouldHideLocalRecipient
        contactsViewHelper.addObserver(self)
    }

    // MARK: - Loading

    func loadData() {
        loadData(loadSignalConnections: true)
    }

    func loadData(loadSignalConnections: Bool) {
        var signalConnections: [ComparableDisplayName] = []
        var signalConnectionAddresses: Set<SignalServiceAddress> = []

        if case .loaded(let currentData) = state {
            if !loadSignalConnections {
                signalConnections = currentData.signalConnections
                signalConnectionAddresses = currentData.signalConnectionAddresses
            }
        }

        if loadSignalConnections {
            db.read { tx in
                // All Signal Connections that we believe are registered. In theory, this
                // should include your system contacts, the people you chat with, and Note to Self.
                let whitelistedAddresses = Set(dataSource.whitelistedRegisteredAddresses(tx: tx))
                let blockedAddresses = dataSource.blockedAddresses(tx: tx)
                let hiddenAddresses = dataSource.hiddenAddresses(tx: tx)

                var resolvedAddresses = whitelistedAddresses.subtracting(blockedAddresses).subtracting(hiddenAddresses)

                if let localAddress = dataSource.localRecipientAddress(tx: tx) {
                    if !shouldHideLocalRecipient {
                        resolvedAddresses.insert(localAddress)
                    } else {
                        resolvedAddresses.remove(localAddress)
                    }

                    signalConnections = dataSource.sortedComparableNames(for: Array(resolvedAddresses), tx: tx).filter { $0.displayName.hasKnownValue }
                    signalConnectionAddresses = Set(signalConnections.lazy.map { $0.address })
                } else {
                    Logger.error("No local address")
                }
            }
        }

        let mergedRecipients = signalConnections.map { Recipient.signalConnection($0) }

        stateSubject.value = .loaded(
            LoadedData(
                signalConnections: signalConnections,
                signalConnectionAddresses: signalConnectionAddresses,
                recipients: mergedRecipients,
            ),
        )
    }

    // MARK: ContactsViewHelperObserver

    func contactsViewHelperDidUpdateContacts() {
        switch state {
        case .loaded:
            loadData(loadSignalConnections: true)
        case .initial:
            break
        }
    }
}

// MARK: - Data Source

protocol RecipientPickerViewModelDataSource {
    func whitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress]
    func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress>
    func hiddenAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress>
    func localRecipientAddress(tx: DBReadTransaction) -> SignalServiceAddress?
    func sortedComparableNames(
        for addresses: [SignalServiceAddress],
        tx: DBReadTransaction,
    ) -> [ComparableDisplayName]
}

struct RecipientPickerViewModelDataSourceImpl: RecipientPickerViewModelDataSource {

    private let blockingManager: BlockingManager
    private let contactManager: any ContactManager
    private let profileManager: any ProfileManager
    private let recipientHidingManager: any RecipientHidingManager
    private let tsAccountManager: any TSAccountManager

    init() {
        self.blockingManager = SSKEnvironment.shared.blockingManagerRef
        self.contactManager = SSKEnvironment.shared.contactManagerRef
        self.profileManager = SSKEnvironment.shared.profileManagerRef
        self.recipientHidingManager = DependenciesBridge.shared.recipientHidingManager
        self.tsAccountManager = DependenciesBridge.shared.tsAccountManager
    }

    func whitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] {
        profileManager.allWhitelistedRegisteredAddresses(tx: tx)
    }

    func blockedAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        blockingManager.blockedAddresses(transaction: tx)
    }

    func hiddenAddresses(tx: DBReadTransaction) -> Set<SignalServiceAddress> {
        recipientHidingManager.hiddenAddresses(tx: tx)
    }

    func localRecipientAddress(tx: DBReadTransaction) -> SignalServiceAddress? {
        tsAccountManager.localIdentifiers(tx: tx)?.aciAddress
    }

    func sortedComparableNames(
        for addresses: [SignalServiceAddress],
        tx: DBReadTransaction,
    ) -> [ComparableDisplayName] {
        contactManager.sortedComparableNames(for: addresses, tx: tx)
    }
}
