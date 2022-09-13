//// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.
//
//import Combine
//import Quick
//import Nimble
//
//@testable import Session
//
//class ThreadDisappearingMessagesViewModelSpec: import Combine {
//    typealias Item = ConversationDisappearingMessagesViewModel.Item
//
//    var disposables: Set<AnyCancellable>!
//    var dataChangedCallbackTriggered: Bool = false
//    var thread: TSThread!
//    var config: OWSDisappearingMessagesConfiguration!
//    var contact: Contact!
//    var defaultItems: [ConversationDisappearingMessagesViewModel.Item]!
//    var defaultItems: [Item]!
//    var viewModel: ConversationDisappearingMessagesViewModel!
//
//    // MARK: - Configuration
//
//    override func setUpWithError() throws {
//        dataChangedCallbackTriggered = false
//
//        disposables = Set()
//        thread = TSContactThread(uniqueId: "TestId")
//        config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: "TestId")
//        contact = Contact(sessionID: "TestContactId")
//        defaultItems = [
//            ConversationDisappearingMessagesViewModel.Item(id: 0, title: "Off", isActive: true),
//            ConversationDisappearingMessagesViewModel.Item(id: 1, title: "5 seconds", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 2, title: "10 seconds", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 3, title: "30 seconds", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 4, title: "1 minute", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 5, title: "5 minutes", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 6, title: "30 minutes", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 7, title: "1 hour", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 8, title: "6 hours", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 9, title: "12 hours", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 10, title: "1 day", isActive: false),
//            ConversationDisappearingMessagesViewModel.Item(id: 11, title: "1 week", isActive: false)
//            Item(id: 0, title: "Off", isActive: true),
//            Item(id: 1, title: "5 seconds", isActive: false),
//            Item(id: 2, title: "10 seconds", isActive: false),
//            Item(id: 3, title: "30 seconds", isActive: false),
//            Item(id: 4, title: "1 minute", isActive: false),
//            Item(id: 5, title: "5 minutes", isActive: false),
//            Item(id: 6, title: "30 minutes", isActive: false),
//            Item(id: 7, title: "1 hour", isActive: false),
//            Item(id: 8, title: "6 hours", isActive: false),
//            Item(id: 9, title: "12 hours", isActive: false),
//            Item(id: 10, title: "1 day", isActive: false),
//            Item(id: 11, title: "1 week", isActive: false)
//        ]
//
//        viewModel = ConversationDisappearingMessagesViewModel(thread: thread, disappearingMessagesConfiguration: config) { [weak self] in
//            self?.dataChangedCallbackTriggered = true
//        }
//    }
//
//    override func tearDownWithError() throws {
//        disposables = nil
//        dataChangedCallbackTriggered = false
//        thread = nil
//        config = nil
//        contact = nil
//        defaultItems = nil
//        viewModel = nil
//    }
//
//    // MARK: - ConversationDisappearingMessagesViewModel.Item
//
//    func testItDefaultsToTheExistingValuesWhenUpdatedWithNullValues() throws {
//        var item: ConversationDisappearingMessagesViewModel.Item = ConversationDisappearingMessagesViewModel.Item(
//            id: 1,
//            title: "Test",
//            isActive: true
//        )
//
//        expect(item.isActive).to(beTrue())
//
//        item = item.with(isActive: nil)
//        expect(item.isActive).to(beTrue())
//
//        item = item.with(isActive: false)
//        expect(item.isActive).to(beFalse())
//    }
//
//    // MARK: - Basic Tests
//
//    func testItHasTheCorrectTitle() throws {
//        expect(self.viewModel.title).to(equal("DISAPPEARING_MESSAGES_SETTINGS_TITLE".localized()))
//    }
//
//    func testItHasTheCorrectDescriptionForAGroup() throws {
//        thread = TSGroupThread(uniqueId: "TestId1")
//        config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: "TestId1")
//        viewModel = ConversationDisappearingMessagesViewModel(thread: thread, disappearingMessagesConfiguration: config) { [weak self] in
//            self?.dataChangedCallbackTriggered = true
//        }
//
//        expect(self.viewModel.description)
//            .to(equal(
//                String(format: NSLocalizedString("When enabled, messages between you and %@ will disappear after they have been seen.", comment: ""), arguments: ["the group"])
//            ))
//    }
//
//    func testItHasTheCorrectDescriptionForAKnownContact() throws {
//        var hasWrittenToStorage: Bool = false
//
//        // TODO: Mock storage
//        Storage.write { [weak self] transaction in
//            guard let strongSelf = self else { return }
//
//            Storage.shared.setContact(strongSelf.contact, using: transaction)
//
//            // Need to do these after setting the contact to ensure it's picked up correctly
//            strongSelf.thread = TSContactThread(contactSessionID: "TestContactId")
//            strongSelf.config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: (strongSelf.thread.uniqueId ?? "TestContactId"))
//            strongSelf.viewModel = ConversationDisappearingMessagesViewModel(thread: strongSelf.thread, disappearingMessagesConfiguration: strongSelf.config) {
//                self?.dataChangedCallbackTriggered = true
//            }
//            hasWrittenToStorage = true
//        }
//
//        // Note: We need this to ensure the test doesn't run before the subsequent 'expect' doesn't
//        // run before the viewModel gets recreated in the 'Storage.write'
//        expect(hasWrittenToStorage)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.description)
//            .toEventually(
//                equal(
//                    String(format: NSLocalizedString("When enabled, messages between you and %@ will disappear after they have been seen.", comment: ""), arguments: ["anonymous"])
//                ),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItHasTheCorrectDescriptionForAKnownContactWithADisplayName() throws {
//        var hasWrittenToStorage: Bool = false
//        contact.nickname = "TestName"
//
//        // TODO: Mock storage
//        Storage.write { [weak self] transaction in
//            guard let strongSelf = self else { return }
//
//            Storage.shared.setContact(strongSelf.contact, using: transaction)
//
//            // Need to do these after setting the contact to ensure it's picked up correctly
//            strongSelf.thread = TSContactThread(contactSessionID: "TestContactId")
//            strongSelf.config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: (strongSelf.thread.uniqueId ?? "TestContactId"))
//            strongSelf.viewModel = ConversationDisappearingMessagesViewModel(thread: strongSelf.thread, disappearingMessagesConfiguration: strongSelf.config) {
//                self?.dataChangedCallbackTriggered = true
//            }
//            hasWrittenToStorage = true
//        }
//
//        // Note: We need this to ensure the test doesn't run before the subsequent 'expect' doesn't
//        // run before the viewModel gets recreated in the 'Storage.write'
//        expect(hasWrittenToStorage)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.description)
//            .toEventually(equal(
//                String(format: NSLocalizedString("When enabled, messages between you and %@ will disappear after they have been seen.", comment: ""), arguments: ["TestName"])
//            ))
//    }
//
//    func testItHasTheCorrectDescriptionForAnUnexpectedThreadType() throws {
//        var hasWrittenToStorage: Bool = false
//        contact.nickname = "TestName"
//
//        // TODO: Mock storage
//        Storage.write { [weak self] transaction in
//            guard let strongSelf = self else { return }
//
//            Storage.shared.setContact(strongSelf.contact, using: transaction)
//
//            // Need to do these after setting the contact to ensure it's picked up correctly
//            strongSelf.thread = TSThread(uniqueId: "TestId1")
//            strongSelf.config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: (strongSelf.thread.uniqueId ?? "TestId1"))
//            strongSelf.viewModel = ConversationDisappearingMessagesViewModel(thread: strongSelf.thread, disappearingMessagesConfiguration: strongSelf.config) {
//                self?.dataChangedCallbackTriggered = true
//            }
//            hasWrittenToStorage = true
//        }
//
//        // Note: We need this to ensure the test doesn't run before the subsequent 'expect' doesn't
//        // run before the viewModel gets recreated in the 'Storage.write'
//        expect(hasWrittenToStorage)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.description)
//            .toEventually(equal(
//                String(format: NSLocalizedString("When enabled, messages between you and %@ will disappear after they have been seen.", comment: ""), arguments: ["anonymous"])
//            ))
//    }
//
//    func testItHasTheCorrectNumberOfItems() throws {
//        expect(self.viewModel.items.value.count).to(equal(12))
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                haveCount(12),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItHasTheCorrectDefaultState() throws {
//        expect(self.viewModel.items.value).to(equal(defaultItems))
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                equal(defaultItems),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItStartsWithTheCorrectItemActiveIfNotDefault() throws {
//        config = OWSDisappearingMessagesConfiguration(defaultWithThreadId: "TestId1")
//        config.isEnabled = true
//        config.durationSeconds = 30
//        viewModel = ConversationDisappearingMessagesViewModel(thread: thread, disappearingMessagesConfiguration: config) { [weak self] in
//            self?.dataChangedCallbackTriggered = true
//        }
//
//        var nonDefaultItems: [ConversationDisappearingMessagesViewModel.Item] = defaultItems
//        nonDefaultItems[0] = nonDefaultItems[0].with(isActive: false)
//        nonDefaultItems[3] = nonDefaultItems[3].with(isActive: true)
//        expect(self.viewModel.items.value).to(equal(nonDefaultItems))
//    }
//
//    // MARK: - Interactions
//
//    func testItProvidesTheThreadAndGivenDataWhenAnInteractionOccurs() throws {
//        var interactionThread: TSThread? = nil
//
//        self.viewModel.interaction.on(0) { thread in
//            interactionThread = thread
//        }
//
//        self.viewModel.interaction.tap(0)
//
//        expect(interactionThread).to(equal(self.thread))
//    }
//
//    func testItRefreshesTheDataCorrectly() throws {
//        expect(self.viewModel.items.value.count).to(beGreaterThan(3))
//        expect(self.viewModel.items.value[3].id).to(equal(3))
//        expect(self.viewModel.items.value[3].isActive).to(beFalse())
//
//        config.isEnabled = true
//        config.durationSeconds = 30
//
//        viewModel.tryRefreshData(for: 3)
//
//        expect(self.viewModel.items.value[3].id).to(equal(3))
//        expect(self.viewModel.items.value[3].isActive).to(beTrue())
//    }
//
//    func testItDoesNotSetAnItemToActiveIfTheConfigIsNotEnabled() throws {
//        expect(self.viewModel.items.value.count).to(beGreaterThan(3))
//        expect(self.viewModel.items.value[3].id).to(equal(3))
//        expect(self.viewModel.items.value[3].isActive).to(beFalse())
//        var nonDefaultItems: [Item] = defaultItems
//        nonDefaultItems[0] = Item(id: nonDefaultItems[0].id, title: nonDefaultItems[0].title, isActive: false)
//        nonDefaultItems[3] = Item(id: nonDefaultItems[3].id, title: nonDefaultItems[3].title, isActive: true)
//
//        config.durationSeconds = 30
//
//        viewModel.tryRefreshData(for: 3)
//
//        expect(self.viewModel.items.value[3].id).to(equal(3))
//        expect(self.viewModel.items.value[3].isActive).to(beFalse())
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                equal(nonDefaultItems),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItUpdatesToADifferentValue() throws {
//        expect(self.viewModel.items.value.count).to(beGreaterThan(3))
//        expect(self.viewModel.items.value[0].id).to(equal(0))
//        expect(self.viewModel.items.value[0].isActive).to(beTrue())
//
//        viewModel.interaction.tap(3)
//    // MARK: - Interactions
//
//        expect(self.viewModel.items.value[0].id)
//    func testItSelectsTheItemCorrectly() throws {
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                equal(0),
//                satisfyAllOf(
//                    haveCountGreaterThan(3),
//                    valueFor(\.id, at: 3, to: equal(3)),
//                    valueFor(\.isActive, at: 3, to: beFalse())
//                ),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.items.value[0].isActive)
//
//        viewModel.itemSelected.send(3)
//
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                beFalse(),
//                satisfyAllOf(
//                    valueFor(\.id, at: 3, to: equal(3)),
//                    valueFor(\.isActive, at: 3, to: beTrue())
//                ),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.items.value[3].id)
//    }
//
//    func testItUpdatesToADifferentValue() throws {
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                equal(3),
//                satisfyAllOf(
//                    haveCountGreaterThan(3),
//                    valueFor(\.id, at: 0, to: equal(0)),
//                    valueFor(\.isActive, at: 0, to: beTrue())
//                ),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.items.value[3].isActive)
//
//        viewModel.itemSelected.send(3)
//
//        expect(self.viewModel.items.newest)
//            .toEventually(
//                beTrue(),
//                satisfyAllOf(
//                    valueFor(\.id, at: 0, to: equal(0)),
//                    valueFor(\.isActive, at: 0, to: beFalse()),
//                    valueFor(\.id, at: 3, to: equal(3)),
//                    valueFor(\.isActive, at: 3, to: beTrue())
//                ),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItUpdatesTheConfigWhenChangingValue() throws {
//        // Note: Default for 'durationSectionds' is OWSDisappearingMessagesConfigurationDefaultExpirationDuration
//        // currently set to 86400
//        expect(self.config.isEnabled).to(beFalse())
//        expect(self.config.durationSeconds).to(equal(86400))
//
//        viewModel.interaction.tap(3)
//
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.itemSelected.send(3)
//
//        expect(self.config.isEnabled)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.config.durationSeconds)
//            .toEventually(
//                equal(30),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItDisablesTheConfigWhenSetToZero() throws {
//        config.isEnabled = true
//
//        viewModel.interaction.tap(0)
//
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.itemSelected.send(0)
//
//        expect(self.config.isEnabled)
//            .toEventually(
//                beFalse(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.config.durationSeconds)
//            .toEventually(
//                equal(0),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItDoesNotSaveChangesIfTheConfigHasNotChangedFromItsDefaultState() {
//        viewModel.trySaveChanges()
//
//
//        // TODO: Mock out Storage.write
//        expect(self.dataChangedCallbackTriggered)
//            .toEventually(
//                beFalse(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItDoesSaveChangesIfTheConfigHasChanged() {
//        config.isEnabled = true
//        config.durationSeconds = 30
//
//
//        viewModel.trySaveChanges()
//
//
//        // TODO: Mock out Storage.write
//        expect(self.dataChangedCallbackTriggered)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//    }
//}
