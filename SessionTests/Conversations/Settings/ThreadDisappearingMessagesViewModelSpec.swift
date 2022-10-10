// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Combine
import GRDB
import Quick
import Nimble

@testable import Session

class ThreadDisappearingMessagesViewModelSpec: QuickSpec {
    typealias ParentType = SessionTableViewModel<ThreadDisappearingMessagesViewModel.NavButton, ThreadDisappearingMessagesViewModel.Section, ThreadDisappearingMessagesViewModel.Item>
    
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        var cancellables: [AnyCancellable] = []
        var dependencies: Dependencies!
        var viewModel: ThreadDisappearingMessagesViewModel!
        
        describe("a ThreadDisappearingMessagesViewModel") {
            // MARK: - Configuration
            
            beforeEach {
                mockStorage = Storage(
                    customWriter: DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNSnodeKit.migrations(),
                        SNMessagingKit.migrations(),
                        SNUIKit.migrations()
                    ]
                )
                dependencies = Dependencies(
                    storage: mockStorage,
                    scheduler: .immediate
                )
                mockStorage.write { db in
                    try SessionThread(
                        id: "TestId",
                        variant: .contact
                    ).insert(db)
                }
                viewModel = ThreadDisappearingMessagesViewModel(
                    dependencies: dependencies,
                    threadId: "TestId",
                    config: DisappearingMessagesConfiguration.defaultWith("TestId")
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
            }
            
            // MARK: - Basic Tests
            
            it("has the correct title") {
                expect(viewModel.title).to(equal("DISAPPEARING_MESSAGES".localized()))
            }
            
            it("has the correct number of items") {
                expect(viewModel.settingsData.count)
                    .to(equal(1))
                expect(viewModel.settingsData.first?.elements.count)
                    .to(equal(12))
            }
            
            it("has the correct default state") {
                expect(viewModel.settingsData.first?.elements.first)
                    .to(
                        equal(
                            SessionCell.Info(
                                id: ThreadDisappearingMessagesViewModel.Item(
                                    title: "DISAPPEARING_MESSAGES_OFF".localized()
                                ),
                                title: "DISAPPEARING_MESSAGES_OFF".localized(),
                                rightAccessory: .radio(
                                    isSelected: { true }
                                )
                            )
                        )
                    )
                
                let title: String = (DisappearingMessagesConfiguration.validDurationsSeconds.last?
                    .formatted(format: .long))
                    .defaulting(to: "")
                expect(viewModel.settingsData.first?.elements.last)
                    .to(
                        equal(
                            SessionCell.Info(
                                id: ThreadDisappearingMessagesViewModel.Item(title: title),
                                title: title,
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            )
                        )
                    )
            }
            
            it("starts with the correct item active if not default") {
                let config: DisappearingMessagesConfiguration = DisappearingMessagesConfiguration
                    .defaultWith("TestId")
                    .with(
                        isEnabled: true,
                        durationSeconds: DisappearingMessagesConfiguration.validDurationsSeconds.last
                    )
                mockStorage.write { db in
                    _ = try config.saved(db)
                }
                viewModel = ThreadDisappearingMessagesViewModel(
                    dependencies: dependencies,
                    threadId: "TestId",
                    config: config
                )
                cancellables.append(
                    viewModel.observableSettingsData
                        .receiveOnMain(immediately: true)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { viewModel.updateSettings($0) }
                        )
                )
                
                expect(viewModel.settingsData.first?.elements.first)
                    .to(
                        equal(
                            SessionCell.Info(
                                id: ThreadDisappearingMessagesViewModel.Item(
                                    title: "DISAPPEARING_MESSAGES_OFF".localized()
                                ),
                                title: "DISAPPEARING_MESSAGES_OFF".localized(),
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            )
                        )
                    )
                
                let title: String = (DisappearingMessagesConfiguration.validDurationsSeconds.last?
                    .formatted(format: .long))
                    .defaulting(to: "")
                expect(viewModel.settingsData.first?.elements.last)
                    .to(
                        equal(
                            SessionCell.Info(
                                id: ThreadDisappearingMessagesViewModel.Item(title: title),
                                title: title,
                                rightAccessory: .radio(
                                    isSelected: { true }
                                )
                            )
                        )
                    )
            }
            
            it("has no right bar button") {
                var items: [ParentType.NavItem]?
                
                cancellables.append(
                    viewModel.rightNavItems
                        .receiveOnMain(immediately: true)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { navItems in items = navItems }
                        )
                )
                
                expect(items).to(equal([]))
            }
            
            context("when changed from the previous setting") {
                var items: [ParentType.NavItem]?
                
                beforeEach {
                    cancellables.append(
                        viewModel.rightNavItems
                            .receiveOnMain(immediately: true)
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: { navItems in items = navItems }
                            )
                    )
                    
                    viewModel.settingsData.first?.elements.last?.onTap?(nil)
                }
                
                it("shows the save button") {
                    expect(items)
                        .to(equal([
                            ParentType.NavItem(
                                id: .save,
                                systemItem: .save,
                                accessibilityIdentifier: "Save button"
                            )
                        ]))
                }
                
                context("and saving") {
                    it("dismisses the screen") {
                        var didDismissScreen: Bool = false
                        
                        cancellables.append(
                            viewModel.dismissScreen
                                .receiveOnMain(immediately: true)
                                .sink(
                                    receiveCompletion: { _ in },
                                    receiveValue: { _ in didDismissScreen = true }
                                )
                        )
                        
                        items?.first?.action?()
                        
                        expect(didDismissScreen)
                            .toEventually(
                                beTrue(),
                                timeout: .milliseconds(100)
                            )
                    }
                    
                    it("saves the updated config") {
                        items?.first?.action?()
                        
                        let updatedConfig: DisappearingMessagesConfiguration? = mockStorage.read { db in
                            try DisappearingMessagesConfiguration.fetchOne(db, id: "TestId")
                        }
                        
                        expect(updatedConfig?.isEnabled)
                            .toEventually(
                                beTrue(),
                                timeout: .milliseconds(100)
                            )
                        expect(updatedConfig?.durationSeconds)
                            .toEventually(
                                equal(DisappearingMessagesConfiguration.validDurationsSeconds.last ?? -1),
                                timeout: .milliseconds(100)
                            )
                    }
                }
            }
        }
    }
}
