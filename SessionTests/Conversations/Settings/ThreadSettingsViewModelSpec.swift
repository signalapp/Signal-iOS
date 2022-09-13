//// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.
//
//import Combine
//import Quick
//import Nimble
//
//@testable import Session
//
//class ThreadSettingsViewModelSpec: QuickSpec {
//    typealias Item = ConversationSettingsViewModel.Item
//    typealias ActionableItem = ConversationSettingsViewModel.ActionableItem
//    typealias NavItem = ConversationSettingsViewModel.NavItem
//
//    var disposables: Set<AnyCancellable>!
//    var didTriggerSearchCallbackTriggered: Bool = false
//    var publicKey: String!
//    var thread: TSThread!
//    var uiDatabaseConnection: YapDatabaseConnection!
//    var defaultContactThreadItems: [[Item]]!
//    var viewModel: ConversationSettingsViewModel!
//
//
//    // MARK: - Configuration
//
//    override func setUpWithError() throws {
//        didTriggerSearchCallbackTriggered = false
//
//        // TODO: Need to mock TSThread, YapDatabaseConnection and the publicKey retrieval logic
//        disposables = Set()
//        didTriggerSearchCallbackTriggered = false
//        publicKey = SNGeneralUtilities.getUserPublicKey()
//        thread = TSContactThread(contactSessionID: "TestContactId")
//        uiDatabaseConnection = OWSPrimaryStorage.shared().uiDatabaseConnection
//        defaultContactThreadItems = [
//            [
//                Item(
//                    id: .header,
//                    style: .header,
//                    title: "Anonymous",
//                    subtitle: "TestContactId"
//                )
//            ],
//            [
//                Item(
//                    id: .search,
//                    style: .search,
//                    icon: UIImage(named: "conversation_settings_search")?.withRenderingMode(.alwaysTemplate),
//                    title: "CONVERSATION_SETTINGS_SEARCH".localized(),
//                    accessibilityIdentifier: "ConversationSettingsViewModel.search"
//                )
//            ],
//            [
//                Item(
//                    id: .allMedia,
//                    icon: UIImage(named: "actionsheet_camera_roll_black")?.withRenderingMode(.alwaysTemplate),
//                    title: MediaStrings.allMedia,
//                    accessibilityIdentifier: "ConversationSettingsViewModel.all_media"
//                ),
//                Item(
//                    id: .pinConversation,
//                    icon: UIImage(named: "settings_pin")?.withRenderingMode(.alwaysTemplate),
//                    title: "CONVERSATION_SETTINGS_PIN".localized(),
//                    accessibilityIdentifier: "ConversationSettingsViewModel.pin_conversation"
//                ),
//                Item(
//                    id: .disappearingMessages,
//                    icon: UIImage(named: "timer_55")?.withRenderingMode(.alwaysTemplate),
//                    title: "DISAPPEARING_MESSAGES".localized(),
//                    subtitle: "DISAPPEARING_MESSAGES_OFF".localized(),
//                    accessibilityIdentifier: "ConversationSettingsViewModel.disappearing_messages"
//                ),
//                Item(
//                    id: .notifications,
//                    icon: UIImage(named: "mute_unfilled")?.withRenderingMode(.alwaysTemplate),
//                    title: "CONVERSATION_SETTINGS_MUTE_ACTION_NEW".localized(),
//                    accessibilityIdentifier: "ConversationSettingsViewModel.mute"
//                )
//            ],
//            [
//                Item(
//                    id: .deleteMessages,
//                    icon: UIImage(named: "trash")?.withRenderingMode(.alwaysTemplate),
//                    title: "DELETE_MESSAGES".localized(),
//                    isNegativeAction: true,
//                    accessibilityIdentifier: "ConversationSettingsViewModel.delete_messages"
//                ),
//                Item(
//                    id: .blockUser,
//                    icon: UIImage(named: "table_ic_block")?.withRenderingMode(.alwaysTemplate),
//                    title: "CONVERSATION_SETTINGS_BLOCK_USER".localized(),
//                    isNegativeAction: true,
//                    accessibilityIdentifier: "ConversationSettingsViewModel.block"
//                )
//            ]
//        ]
//
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//    }
//
//
//    override func tearDownWithError() throws {
//        disposables = nil
//        didTriggerSearchCallbackTriggered = false
//        publicKey = nil
//        thread = nil
//        uiDatabaseConnection = nil
//        defaultContactThreadItems = nil
//        viewModel = nil
//    }
//
//    // MARK: - Basic Tests
//    // MARK: - Item
//
//    func testTheItemGetsCreatedCorrectly() {
//        let image: UIImage = UIImage()
//        let item: Item = Item(
//            id: .allMedia,
//            style: .header,
//            icon: image,
//            title: "Test",
//            subtitle: "TestSub",
//            isEnabled: false,
//            isEditing: true,
//            isNegativeAction: true,
//            accessibilityIdentifier: "TestAccessibility"
//        )
//
//        expect(item.id).to(equal(.allMedia))
//        expect(item.style).to(equal(.header))
//        expect(item.icon).to(equal(image))
//        expect(item.title).to(equal("Test"))
//        expect(item.subtitle).to(equal("TestSub"))
//        expect(item.isEnabled).to(beFalse())
//        expect(item.isEditing).to(beTrue())
//        expect(item.isNegativeAction).to(beTrue())
//        expect(item.accessibilityIdentifier).to(equal("TestAccessibility"))
//    }
//
//    func testTheItemHasTheCorrectDefaultValues() {
//        let item: Item = Item(id: .allMedia)
//
//        expect(item.id).to(equal(.allMedia))
//        expect(item.style).to(equal(.standard))
//        expect(item.icon).to(beNil())
//        expect(item.title).to(equal(""))
//        expect(item.subtitle).to(beNil())
//        expect(item.isEnabled).to(beTrue())
//        expect(item.isEditing).to(beFalse())
//        expect(item.isNegativeAction).to(beFalse())
//        expect(item.accessibilityIdentifier).to(beNil())
//    }
//
//    // MARK: - ActionableItem
//
//    func testTheActionableItemGetsCreatedCorrectly() {
//        let item: Item = Item(id: .allMedia)
//        let subject: PassthroughSubject<Void, Never> = PassthroughSubject()
//        let actionableItem: ActionableItem = ActionableItem(
//            data: item,
//            action: subject
//        )
//
//        expect(actionableItem.data).to(equal(item))
//        expect(actionableItem.action).to(beIdenticalTo(subject))
//    }
//
//    // MARK: - Basic Tests
//
//    func testItHasTheCorrectTitleForAnIndividualThread() {
//        expect(self.viewModel.title).to(equal("vc_settings_title".localized()))
//    }
//
//
//    func testItHasTheCorrectTitleForAGroupThread() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//
//        expect(self.viewModel.title).to(equal("vc_group_settings_title".localized()))
//    }
//
//
//    // MARK: - All Conversation Type Shared Tests
//
//
//    func testItTriggersTheSearchCallbackWhenInteractingWithSearch() {
//        viewModel.interaction.tap(.search)
//
//        expect(self.didTriggerSearchCallbackTriggered).to(beTrue())
//        viewModel.viewSearch.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.searchTapped.send()
//
//        expect(self.didTriggerSearchCallbackTriggered)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItPinsAConversation() {
//        viewModel.interaction.tap(.togglePinConversation)
//
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.pinConversationTapped.send()
//
//        expect(self.thread.isPinned)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItUnPinsAConversation() {
//        viewModel.interaction.tap(.togglePinConversation)
//        thread.isPinned = true
//
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.pinConversationTapped.send()
//
//        expect(self.thread.isPinned)
//            .toEventually(
//                beTrue(),
//                beFalse(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItUpdatesTheItemTitleToReflectThePinnedState() {
//        thread.isPinned = true
//
//        viewModel.interaction.tap(.togglePinConversation)
//        let itemsData = viewModel.items
//            .map { sections in sections.map { section in section.map { $0.data } } }
//
//        expect(self.thread.isPinned)
//        expect(itemsData.newest)
//            .toEventually(
//                beFalse(),
//                satisfyAllOf(
//                    haveCountGreaterThan(2),
//                    valueAt(2, haveCountGreaterThan(1))
//                ),
//                timeout: .milliseconds(100)
//            )
//        expect(itemsData.map { $0[2][1].title }.newest)
//            .toEventually(
//                equal("CONVERSATION_SETTINGS_UNPIN".localized()),
//                timeout: .milliseconds(10000)
//            )
//    }
//
//    func testDeletingMessageShowsAndThensHidesTheLoadingState() {
//        let replayLoadingState = viewModel.loadingStateVisible.shareReplay(2)
//        replayLoadingState.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.deleteMessages()
//
//        expect(replayLoadingState.all)
//            .toEventually(
//                equal([
//                    true,
//                    false
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    // MARK: - Individual & Note to Self Conversation Shared Tests
//
//
//    func testItHasTheCorrectDefaultNavButtonsForAContactConversation() {
//        expect(self.viewModel.leftNavItems.value).to(equal([]))
//        expect(self.viewModel.rightNavItems.value)
//            .to(equal([
//                ConversationSettingsViewModel.Item(
//                    id: .navEdit,
//                    style: .navigation,
//                    action: .startEditingDisplayName,
//                    icon: nil,
//                    title: "",
//                    barButtonItem: .edit,
//                    subtitle: nil,
//                    isEnabled: true,
//                    isNegativeAction: false,
//                    accessibilityIdentifier: "Edit button"
//                )
//            ]))
//        expect(self.viewModel.leftNavItems.newest)
//            .toEventually(
//                haveCount(0),
//                timeout: .milliseconds(100)
//            )
//        expect(self.viewModel.rightNavItems.map { items in items.map { $0.data } }.newest)
//            .toEventually(
//                equal([
//                    NavItem(
//                        systemItem: .edit,
//                        accessibilityIdentifier: "Edit button"
//                    )
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItUpdatesTheNavButtonsWhenEnteringEditMode() {
//        viewModel.interaction.tap(.startEditingDisplayName)
//
//        expect(self.viewModel.leftNavItems.value)
//            .to(equal([
//                ConversationSettingsViewModel.Item(
//                    id: .navCancel,
//                    style: .navigation,
//                    action: .cancelEditingDisplayName,
//                    icon: nil,
//                    title: "",
//                    barButtonItem: .cancel,
//                    subtitle: nil,
//                    isEnabled: true,
//                    isNegativeAction: false,
//                    accessibilityIdentifier: "Cancel button"
//                )
//            ]))
//        expect(self.viewModel.rightNavItems.value)
//            .to(equal([
//                ConversationSettingsViewModel.Item(
//                    id: .navDone,
//                    style: .navigation,
//                    action: .saveUpdatedDisplayName,
//                    icon: nil,
//                    title: "",
//                    barButtonItem: .done,
//                    subtitle: nil,
//                    isEnabled: true,
//                    isNegativeAction: false,
//                    accessibilityIdentifier: "Done button"
//                )
//            ]))
//        let replayLeftNavItems = viewModel.leftNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        let replayRightNavItems = viewModel.rightNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        replayLeftNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//        replayRightNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.editDisplayNameTapped.send()
//
//        expect(replayLeftNavItems.newest)
//            .toEventually(
//                equal([
//                    NavItem(
//                        systemItem: .cancel,
//                        accessibilityIdentifier: "Cancel button"
//                    )
//                ]),
//                timeout: .milliseconds(100)
//            )
//        expect(replayRightNavItems.newest)
//            .toEventually(
//                equal([
//                    NavItem(
//                        systemItem: .done,
//                        accessibilityIdentifier: "Done button"
//                    )
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItGoesBackToTheDefaultNavButtonsWhenYouCancelEditingTheDisplayName() {
//        viewModel.interaction.tap(.startEditingDisplayName)
//
//        expect(self.viewModel.leftNavItems.value.first?.id).to(equal(.navCancel))
//
//        viewModel.interaction.tap(.cancelEditingDisplayName)
//
//        expect(self.viewModel.leftNavItems.value).to(equal([]))
//        expect(self.viewModel.rightNavItems.value)
//            .to(equal([
//                ConversationSettingsViewModel.Item(
//                    id: .navEdit,
//                    style: .navigation,
//                    action: .startEditingDisplayName,
//                    icon: nil,
//                    title: "",
//                    barButtonItem: .edit,
//                    subtitle: nil,
//                    isEnabled: true,
//                    isNegativeAction: false,
//                    accessibilityIdentifier: "Edit button"
//                )
//            ]))
//        let replayLeftNavItems = viewModel.leftNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        let replayRightNavItems = viewModel.rightNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        replayLeftNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//        replayRightNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        // Change to editing state
//        viewModel.editDisplayNameTapped.send()
//
//        expect(replayLeftNavItems.newest)
//            .toEventually(
//                valueFor(\.systemItem, at: 0, to: equal(.cancel)),
//                timeout: .milliseconds(100)
//            )
//
//        // Change back
//        viewModel.cancelEditDisplayNameTapped.send()
//
//        expect(replayLeftNavItems.newest)
//            .toEventually(
//                haveCount(0),
//                timeout: .milliseconds(100)
//            )
//        expect(replayRightNavItems.newest)
//            .toEventually(
//                equal([
//                    NavItem(
//                        systemItem: .edit,
//                        accessibilityIdentifier: "Edit button"
//                    )
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItGoesBackToTheDefaultNavButtonsWhenYouSaveTheUpdatedDisplayName() {
//        viewModel.interaction.tap(.startEditingDisplayName)
//
//        expect(self.viewModel.leftNavItems.value.first?.id).to(equal(.navCancel))
//
//        viewModel.interaction.tap(.saveUpdatedDisplayName)
//
//        expect(self.viewModel.leftNavItems.value).to(equal([]))
//        expect(self.viewModel.rightNavItems.value)
//            .to(equal([
//                ConversationSettingsViewModel.Item(
//                    id: .navEdit,
//                    style: .navigation,
//                    action: .startEditingDisplayName,
//                    icon: nil,
//                    title: "",
//                    barButtonItem: .edit,
//                    subtitle: nil,
//                    isEnabled: true,
//                    isNegativeAction: false,
//                    accessibilityIdentifier: "Edit button"
//                )
//            ]))
//        let replayLeftNavItems = viewModel.leftNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        let replayRightNavItems = viewModel.rightNavItems.map { items in items.map { $0.data } }.shareReplay(1)
//        replayLeftNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//        replayRightNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        // Change to editing state
//        viewModel.editDisplayNameTapped.send()
//
//        expect(replayLeftNavItems.newest)
//            .toEventually(
//                valueFor(\.systemItem, at: 0, to: equal(.cancel)),
//                timeout: .milliseconds(100)
//            )
//
//        // Change back
//        viewModel.saveDisplayNameTapped.send()
//
//        expect(replayLeftNavItems.newest)
//            .toEventually(
//                haveCount(0),
//                timeout: .milliseconds(100)
//            )
//        expect(replayRightNavItems.newest)
//            .toEventually(
//                equal([
//                    NavItem(
//                        systemItem: .edit,
//                        accessibilityIdentifier: "Edit button"
//                    )
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItHasTheCorrectDefaultState() throws {
//        let itemsData = viewModel.items
//            .map { sections in sections.map { section in section.map { $0.data } } }
//
//        expect(itemsData.newest)
//            .toEventually(
//                equal(defaultContactThreadItems),
//                timeout: .milliseconds(1000)
//            )
//    }
//
//    func testItUpdatesTheContactNicknameWhenSavingTheUpdatedDisplayName() {
//        viewModel.interaction.tap(.startEditingDisplayName)
//        viewModel.interaction.change(.changeDisplayName, data: "Test123")
//        viewModel.interaction.tap(.saveUpdatedDisplayName)
//        viewModel.leftNavItems.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.displayName = "Test123"
//        viewModel.saveDisplayNameTapped.send()
//
//        expect(Storage.shared.getContact(with: "TestContactId")?.nickname)
//            .toEventually(
//                equal("Test123"),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItMutesAConversation() {
//        viewModel.interaction.tap(.toggleMuteNotifications)
//
//
//    func testItMutesAContactConversation() {
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.notificationsTapped.send()
//
//        expect(self.thread.isMuted)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    func testItUnMutesAConversation() {
//        viewModel.interaction.tap(.toggleMuteNotifications)
//        var hasWrittenToStorage: Bool = false
//
//        Storage.write { transaction in
//            self.thread.updateWithMuted(
//                until: Date.distantFuture,
//                transaction: transaction
//            )
//            hasWrittenToStorage = true
//        }
//
//        // Note: Wait for the setup to complete
//        expect(hasWrittenToStorage)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//        expect(self.thread.isMuted)
//            .toEventually(
//                beTrue(),
//                timeout: .milliseconds(100)
//            )
//
//        viewModel.interaction.tap(.toggleMuteNotifications)
//
//        viewModel.items.sink(receiveValue: { _ in }).store(in: &disposables)
//        viewModel.notificationsTapped.send()
//
//        expect(self.thread.isMuted)
//            .toEventually(
//                beFalse(),
//                timeout: .milliseconds(100)
//            )
//    }
//
//
//    // MARK: - Group Conversation Tests
//
//
//    func testItHasNoCustomLeftNavButtons() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//        expect(self.viewModel.leftNavItems.newest)
//            .toEventually(
//                haveCount(0),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItHasNoCustomRightNavButtons() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//        expect(self.viewModel.rightNavItems.newest)
//            .toEventually(
//                haveCount(0),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testLeavingGroupShowsAndThensHidesTheLoadingState() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        (thread as? TSGroupThread)?.groupModel = TSGroupModel(
//            title: nil,
//            memberIds: [],
//            image: nil,
//            groupId: "".data(using: .utf8)!,
//            groupType: .closedGroup,
//            adminIds: []
//        )
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//        let replayLoadingState = viewModel.loadingStateVisible.shareReplay(2)
//        replayLoadingState.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        expect(self.viewModel.leftNavItems.value).to(equal([]))
//        viewModel.leaveGroup()
//
//        expect(replayLoadingState.all)
//            .toEventually(
//                equal([
//                    true//,
//                    //false // TODO: Need to mock MessageSender for this to work
//                ]),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItHasNoCustomRightNavButtons() {
//    // MARK: - Transitions
//
//    func testItViewsTheSearch() {
//        let replayViewSearch = viewModel.viewSearch.shareReplay(1)
//        replayViewSearch.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.searchTapped.send()
//
//        expect(replayViewSearch.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItViewsAddToGroup() {
//        let replayViewAddToGroup = viewModel.viewAddToGroup.shareReplay(1)
//        replayViewAddToGroup.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.addToGroupTapped.send()
//
//        expect(replayViewAddToGroup.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItViewsEditGroup() {
//        let replayViewEditGroup = viewModel.viewEditGroup.shareReplay(1)
//        replayViewEditGroup.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.editGroupTapped.send()
//
//        expect(replayViewEditGroup.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItViewsAllMedia() {
//        let replayViewAllMedia = viewModel.viewAllMedia.shareReplay(1)
//        replayViewAllMedia.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.viewAllMediaTapped.send()
//
//        expect(replayViewAllMedia.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItViewsDisappearingMessages() {
//        let replayViewDisappearingMessages = viewModel.viewDisappearingMessages.shareReplay(1)
//        replayViewDisappearingMessages.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.disappearingMessagesTapped.send()
//
//        expect(replayViewDisappearingMessages.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItViewsNotificationSettings() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//        let replayViewNotificationSettings = viewModel.viewNotificationSettings.shareReplay(1)
//        replayViewNotificationSettings.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.notificationsTapped.send()
//
//        expect(replayViewNotificationSettings.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItShowsTheDeleteMessagesAlert() {
//        let replayViewDeleteMessagesAlert = viewModel.viewDeleteMessagesAlert.shareReplay(1)
//        replayViewDeleteMessagesAlert.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.deleteMessagesTapped.send()
//
//        expect(replayViewDeleteMessagesAlert.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItShowsTheLeaveGroupAlert() {
//        thread = TSGroupThread(uniqueId: "TestGroupId1")
//        viewModel = ConversationSettingsViewModel(thread: thread, uiDatabaseConnection: uiDatabaseConnection, didTriggerSearch: { [weak self] in
//            self?.didTriggerSearchCallbackTriggered = true
//        })
//
//        let replayViewLeaveGroupAlert = viewModel.viewLeaveGroupAlert.shareReplay(1)
//        replayViewLeaveGroupAlert.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.leaveGroupTapped.send()
//
//        expect(replayViewLeaveGroupAlert.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    func testItShowsTheBlockUserAlert() {
//        let replayViewBlockUserAlert = viewModel.viewBlockUserAlert.shareReplay(1)
//        replayViewBlockUserAlert.sink(receiveValue: { _ in }).store(in: &disposables)
//
//        viewModel.blockTapped.send()
//
//        expect(self.viewModel.rightNavItems.value).to(equal([]))
//        expect(replayViewBlockUserAlert.all)
//            .toEventually(
//                haveCount(1),
//                timeout: .milliseconds(100)
//            )
//    }
//
//    // TODO: Mock 'OWSProfileManager' to test 'viewProfilePicture'
//    // TODO: Various item states depending on thread type
//    // TODO: Group title options (need mocking?)
//    // TODO: Notification item title options (need mocking?)
//    // TODO: Delete All Messages (need mocking)
//    // TODO: Add to Group (need mocking)
//    // TODO: Leave Group (need mocking)
//}
