// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Combine
import GRDB
import Quick
import Nimble

@testable import Session

class NotificationContentViewModelSpec: QuickSpec {
    // MARK: - Spec

    override func spec() {
        var mockStorage: Storage!
        var dataChangeCancellable: AnyCancellable?
        var dismissCancellable: AnyCancellable?
        var viewModel: NotificationContentViewModel!
        
        describe("a NotificationContentViewModel") {
            // MARK: - Configuration
            
            beforeEach {
                mockStorage = Storage(
                    customWriter: try! DatabaseQueue(),
                    customMigrations: [
                        SNUtilitiesKit.migrations(),
                        SNSnodeKit.migrations(),
                        SNMessagingKit.migrations(),
                        SNUIKit.migrations()
                    ]
                )
                viewModel = NotificationContentViewModel(storage: mockStorage, scheduling: .immediate)
                dataChangeCancellable = viewModel.observableSettingsData
                    .receiveOnMain(immediately: true)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { viewModel.updateSettings($0) }
                    )
            }
            
            afterEach {
                dataChangeCancellable?.cancel()
                dismissCancellable?.cancel()
                
                mockStorage = nil
                dataChangeCancellable = nil
                dismissCancellable = nil
                viewModel = nil
            }
            
            // MARK: - Basic Tests
            
            it("has the correct title") {
                expect(viewModel.title).to(equal("NOTIFICATIONS_STYLE_CONTENT_TITLE".localized()))
            }

            it("has the correct number of items") {
                expect(viewModel.settingsData.count)
                    .to(equal(1))
                expect(viewModel.settingsData.first?.elements.count)
                    .to(equal(3))
            }
            
            it("has the correct default state") {
                expect(viewModel.settingsData.first?.elements)
                    .to(
                        equal([
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.nameAndPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NAME_AND_CONTENT".localized(),
                                rightAccessory: .radio(
                                    isSelected: { true }
                                )
                            ),
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.nameNoPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NAME_ONLY".localized(),
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            ),
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.noNameNoPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NO_NAME_OR_CONTENT".localized(),
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            )
                        ])
                    )
            }
            
            it("starts with the correct item active if not default") {
                mockStorage.write { db in
                    db[.preferencesNotificationPreviewType] = Preferences.NotificationPreviewType.nameNoPreview
                }
                viewModel = NotificationContentViewModel(storage: mockStorage, scheduling: .immediate)
                dataChangeCancellable = viewModel.observableSettingsData
                    .receiveOnMain(immediately: true)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { viewModel.updateSettings($0) }
                    )
                
                expect(viewModel.settingsData.first?.elements)
                    .to(
                        equal([
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.nameAndPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NAME_AND_CONTENT".localized(),
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            ),
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.nameNoPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NAME_ONLY".localized(),
                                rightAccessory: .radio(
                                    isSelected: { true }
                                )
                            ),
                            SessionCell.Info(
                                id: Preferences.NotificationPreviewType.noNameNoPreview,
                                title: "NOTIFICATIONS_STYLE_CONTENT_OPTION_NO_NAME_OR_CONTENT".localized(),
                                rightAccessory: .radio(
                                    isSelected: { false }
                                )
                            )
                        ])
                    )
            }
            
            context("when tapping an item") {
                it("updates the saved preference") {
                    viewModel.settingsData.first?.elements.last?.onTap?(nil)
                    
                    expect(mockStorage[.preferencesNotificationPreviewType])
                        .to(equal(Preferences.NotificationPreviewType.noNameNoPreview))
                }
                
                it("dismisses the screen") {
                    var didDismissScreen: Bool = false
                    
                    dismissCancellable = viewModel.dismissScreen
                        .receiveOnMain(immediately: true)
                        .sink(
                            receiveCompletion: { _ in },
                            receiveValue: { _ in didDismissScreen = true }
                        )
                    viewModel.settingsData.first?.elements.last?.onTap?(nil)
                    
                    expect(didDismissScreen).to(beTrue())
                }
            }
        }
    }
}
