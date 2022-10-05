// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Combine
import GRDB
import Quick
import Nimble

@testable import Session

class ThreadSettingsViewModelSpec: QuickSpec {
    typealias ParentType = SessionTableViewModel<ThreadSettingsViewModel.NavButton, ThreadSettingsViewModel.Section, ThreadSettingsViewModel.Setting>
    
    // MARK: - Spec
    
    override func spec() {
        var mockStorage: Storage!
        var mockGeneralCache: MockGeneralCache!
        var cancellables: [AnyCancellable] = []
        var dependencies: Dependencies!
        var viewModel: ThreadSettingsViewModel!
        var didTriggerSearchCallbackTriggered: Bool = false
        
        describe("a ThreadSettingsViewModel") {
            // MARK: - Configuration
            
            beforeEach {
                mockStorage = SynchronousStorage(
                    customWriter: DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNSnodeKit.migrations(),
                        SNMessagingKit.migrations(),
                        SNUIKit.migrations()
                    ]
                )
                mockGeneralCache = MockGeneralCache()
                dependencies = Dependencies(
                    generalCache: Atomic(mockGeneralCache),
                    storage: mockStorage,
                    scheduler: .immediate
                )
                mockGeneralCache.when { $0.encodedPublicKey }.thenReturn("05\(TestConstants.publicKey)")
                mockStorage.write { db in
                    try SessionThread(
                        id: "TestId",
                        variant: .contact
                    ).insert(db)
                    
                    try Identity(
                        variant: .x25519PublicKey,
                        data: Data(hex: TestConstants.publicKey)
                    ).insert(db)
                    
                    try Profile(
                        id: "05\(TestConstants.publicKey)",
                        name: "TestMe"
                    ).insert(db)
                    
                    try Profile(
                        id: "TestId",
                        name: "TestUser"
                    ).insert(db)
                }
                viewModel = ThreadSettingsViewModel(
                    dependencies: dependencies,
                    threadId: "TestId",
                    threadVariant: .contact,
                    didTriggerSearch: {
                        didTriggerSearchCallbackTriggered = true
                    }
                )
                cancellables.append(
                    viewModel.observableSettingsData
                        .receiveOnMain(immediately: true)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { viewModel.updateSettings($0) }
                        )
                )
            }
            
            afterEach {
                cancellables.forEach { $0.cancel() }
                
                mockStorage = nil
                cancellables = []
                dependencies = nil
                viewModel = nil
                didTriggerSearchCallbackTriggered = false
            }
            
            // MARK: - Basic Tests
            
            context("with any conversation type") {
                it("triggers the search callback when tapping search") {
                    viewModel.settingsData
                        .first(where: { $0.model == .content })?
                        .elements
                        .first(where: { $0.id == .searchConversation })?
                        .onTap?(nil)
                    
                    expect(didTriggerSearchCallbackTriggered).to(beTrue())
                }
                
                it("mutes a conversation") {
                    viewModel.settingsData
                        .first(where: { $0.model == .content })?
                        .elements
                        .first(where: { $0.id == .notificationMute })?
                        .onTap?(nil)
                    
                    expect(
                        mockStorage
                            .read { db in try SessionThread.fetchOne(db, id: "TestId") }?
                            .mutedUntilTimestamp
                    )
                    .toNot(beNil())
                }
                
                it("unmutes a conversation") {
                    mockStorage.write { db in
                        try SessionThread
                            .updateAll(
                                db,
                                SessionThread.Columns.mutedUntilTimestamp.set(to: 1234567890)
                            )
                    }
                    
                    expect(
                        mockStorage
                            .read { db in try SessionThread.fetchOne(db, id: "TestId") }?
                            .mutedUntilTimestamp
                    )
                    .toNot(beNil())
                    
                    viewModel.settingsData
                        .first(where: { $0.model == .content })?
                        .elements
                        .first(where: { $0.id == .notificationMute })?
                        .onTap?(nil)
                
                    expect(
                        mockStorage
                            .read { db in try SessionThread.fetchOne(db, id: "TestId") }?
                            .mutedUntilTimestamp
                    )
                    .to(beNil())
                }
            }
            
            context("with a note-to-self conversation") {
                beforeEach {
                    mockStorage.write { db in
                        try SessionThread.deleteAll(db)
                        
                        try SessionThread(
                            id: "05\(TestConstants.publicKey)",
                            variant: .contact
                        ).insert(db)
                    }
                    
                    viewModel = ThreadSettingsViewModel(
                        dependencies: dependencies,
                        threadId: "05\(TestConstants.publicKey)",
                        threadVariant: .contact,
                        didTriggerSearch: {
                            didTriggerSearchCallbackTriggered = true
                        }
                    )
                    cancellables.append(
                        viewModel.observableSettingsData
                            .receiveOnMain(immediately: true)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { viewModel.updateSettings($0) }
                            )
                    )
                }
                
                it("has the correct title") {
                    expect(viewModel.title).to(equal("vc_settings_title".localized()))
                }
                
                it("starts in the standard nav state") {
                    expect(viewModel.navState.firstValue())
                        .to(equal(.standard))
                    
                    expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                    expect(viewModel.rightNavItems.firstValue())
                        .to(equal([
                            ParentType.NavItem(
                                id: .edit,
                                systemItem: .edit,
                                accessibilityIdentifier: "Edit button"
                            )
                        ]))
                }
                
                it("has no mute button") {
                    expect(
                        viewModel.settingsData
                            .first(where: { $0.model == .content })?
                            .elements
                            .first(where: { $0.id == .notificationMute })
                    ).to(beNil())
                }
                
                context("when entering edit mode") {
                    beforeEach {
                        viewModel.rightNavItems.firstValue()??.first?.action?()
                        
                        let leftAccessory: SessionCell.Accessory? = viewModel.settingsData.first?
                            .elements.first?
                            .leftAccessory
                        
                        switch leftAccessory {
                            case .threadInfo(_, _, _, _, let titleChanged): titleChanged?("TestNew")
                            default: break
                        }
                    }
                    
                    it("enters the editing state") {
                        expect(viewModel.navState.firstValue())
                            .to(equal(.editing))
                        
                        expect(viewModel.leftNavItems.firstValue())
                            .to(equal([
                                ParentType.NavItem(
                                    id: .cancel,
                                    systemItem: .cancel,
                                    accessibilityIdentifier: "Cancel button"
                                )
                            ]))
                        expect(viewModel.rightNavItems.firstValue())
                            .to(equal([
                                ParentType.NavItem(
                                    id: .done,
                                    systemItem: .done,
                                    accessibilityIdentifier: "Done button"
                                )
                            ]))
                    }
                    
                    context("when cancelling edit mode") {
                        beforeEach {
                            viewModel.leftNavItems.firstValue()??.first?.action?()
                        }
                        
                        it("exits editing mode") {
                            expect(viewModel.navState.firstValue())
                                .to(equal(.standard))
                            
                            expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                            expect(viewModel.rightNavItems.firstValue())
                                .to(equal([
                                    ParentType.NavItem(
                                        id: .edit,
                                        systemItem: .edit,
                                        accessibilityIdentifier: "Edit button"
                                    )
                                ]))
                        }
                        
                        it("does not update the nickname for the current user") {
                            expect(
                                mockStorage
                                    .read { db in
                                        try Profile.fetchOne(db, id: "05\(TestConstants.publicKey)")
                                    }?
                                    .nickname
                            )
                            .to(beNil())
                        }
                    }
                    
                    context("when saving edit mode") {
                        beforeEach {
                            viewModel.rightNavItems.firstValue()??.first?.action?()
                        }
                        
                        it("exits editing mode") {
                            expect(viewModel.navState.firstValue())
                                .to(equal(.standard))
                            
                            expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                            expect(viewModel.rightNavItems.firstValue())
                                .to(equal([
                                    ParentType.NavItem(
                                        id: .edit,
                                        systemItem: .edit,
                                        accessibilityIdentifier: "Edit button"
                                    )
                                ]))
                        }
                        
                        it("updates the nickname for the current user") {
                            expect(
                                mockStorage
                                    .read { db in
                                        try Profile.fetchOne(db, id: "05\(TestConstants.publicKey)")
                                    }?
                                    .nickname
                            )
                            .to(equal("TestNew"))
                        }
                    }
                }
            }
            
            context("with a one-to-one conversation") {
                beforeEach {
                    mockStorage.write { db in
                        try SessionThread.deleteAll(db)
                        
                        try SessionThread(
                            id: "TestId",
                            variant: .contact
                        ).insert(db)
                    }
                }
                
                it("has the correct title") {
                    expect(viewModel.title).to(equal("vc_settings_title".localized()))
                }
                
                it("starts in the standard nav state") {
                    expect(viewModel.navState.firstValue())
                        .to(equal(.standard))
                    
                    expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                    expect(viewModel.rightNavItems.firstValue())
                        .to(equal([
                            ParentType.NavItem(
                                id: .edit,
                                systemItem: .edit,
                                accessibilityIdentifier: "Edit button"
                            )
                        ]))
                }
                
                context("when entering edit mode") {
                    beforeEach {
                        viewModel.rightNavItems.firstValue()??.first?.action?()
                        
                        let leftAccessory: SessionCell.Accessory? = viewModel.settingsData.first?
                            .elements.first?
                            .leftAccessory
                        
                        switch leftAccessory {
                            case .threadInfo(_, _, _, _, let titleChanged): titleChanged?("TestUserNew")
                            default: break
                        }
                    }
                    
                    it("enters the editing state") {
                        expect(viewModel.navState.firstValue())
                            .to(equal(.editing))
                        
                        expect(viewModel.leftNavItems.firstValue())
                            .to(equal([
                                ParentType.NavItem(
                                    id: .cancel,
                                    systemItem: .cancel,
                                    accessibilityIdentifier: "Cancel button"
                                )
                            ]))
                        expect(viewModel.rightNavItems.firstValue())
                            .to(equal([
                                ParentType.NavItem(
                                    id: .done,
                                    systemItem: .done,
                                    accessibilityIdentifier: "Done button"
                                )
                            ]))
                    }
                    
                    context("when cancelling edit mode") {
                        beforeEach {
                            viewModel.leftNavItems.firstValue()??.first?.action?()
                        }
                        
                        it("exits editing mode") {
                            expect(viewModel.navState.firstValue())
                                .to(equal(.standard))
                            
                            expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                            expect(viewModel.rightNavItems.firstValue())
                                .to(equal([
                                    ParentType.NavItem(
                                        id: .edit,
                                        systemItem: .edit,
                                        accessibilityIdentifier: "Edit button"
                                    )
                                ]))
                        }
                        
                        it("does not update the nickname for the current user") {
                            expect(
                                mockStorage
                                    .read { db in try Profile.fetchOne(db, id: "TestId") }?
                                    .nickname
                            )
                            .to(beNil())
                        }
                    }
                    
                    context("when saving edit mode") {
                        beforeEach {
                            viewModel.rightNavItems.firstValue()??.first?.action?()
                        }
                        
                        it("exits editing mode") {
                            expect(viewModel.navState.firstValue())
                                .to(equal(.standard))
                            
                            expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                            expect(viewModel.rightNavItems.firstValue())
                                .to(equal([
                                    ParentType.NavItem(
                                        id: .edit,
                                        systemItem: .edit,
                                        accessibilityIdentifier: "Edit button"
                                    )
                                ]))
                        }
                        
                        it("updates the nickname for the current user") {
                            expect(
                                mockStorage
                                    .read { db in try Profile.fetchOne(db, id: "TestId") }?
                                    .nickname
                            )
                            .to(equal("TestUserNew"))
                        }
                    }
                }
            }
            
            context("with a group conversation") {
                beforeEach {
                    mockStorage.write { db in
                        try SessionThread.deleteAll(db)
                        
                        try SessionThread(
                            id: "TestId",
                            variant: .closedGroup
                        ).insert(db)
                    }
                    
                    viewModel = ThreadSettingsViewModel(
                        dependencies: dependencies,
                        threadId: "TestId",
                        threadVariant: .closedGroup,
                        didTriggerSearch: {
                            didTriggerSearchCallbackTriggered = true
                        }
                    )
                    cancellables.append(
                        viewModel.observableSettingsData
                            .receiveOnMain(immediately: true)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { viewModel.updateSettings($0) }
                            )
                    )
                }
                
                it("has the correct title") {
                    expect(viewModel.title).to(equal("vc_group_settings_title".localized()))
                }
                
                it("starts in the standard nav state") {
                    expect(viewModel.navState.firstValue())
                        .to(equal(.standard))
                    
                    expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                    expect(viewModel.rightNavItems.firstValue()).to(equal([]))
                }
            }
            
            context("with a community conversation") {
                beforeEach {
                    mockStorage.write { db in
                        try SessionThread.deleteAll(db)
                        
                        try SessionThread(
                            id: "TestId",
                            variant: .openGroup
                        ).insert(db)
                    }
                    
                    viewModel = ThreadSettingsViewModel(
                        dependencies: dependencies,
                        threadId: "TestId",
                        threadVariant: .openGroup,
                        didTriggerSearch: {
                            didTriggerSearchCallbackTriggered = true
                        }
                    )
                    cancellables.append(
                        viewModel.observableSettingsData
                            .receiveOnMain(immediately: true)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { viewModel.updateSettings($0) }
                            )
                    )
                }
                
                it("has the correct title") {
                    expect(viewModel.title).to(equal("vc_group_settings_title".localized()))
                }
                
                it("starts in the standard nav state") {
                    expect(viewModel.navState.firstValue())
                        .to(equal(.standard))
                    
                    expect(viewModel.leftNavItems.firstValue()).to(equal([]))
                    expect(viewModel.rightNavItems.firstValue()).to(equal([]))
                }
            }
        }
    }
}
