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
        var viewModel: NotificationContentViewModel!
        
        describe("a NotificationContentViewModel") {
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
                viewModel = NotificationContentViewModel(storage: mockStorage)
                dataChangeCancellable = viewModel.observableSettingsData
                    .receiveOnMain(immediately: true)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { viewModel.updateSettings($0) }
                    )
            }
            
            afterEach {
                dataChangeCancellable?.cancel()
                
                mockStorage = nil
                dataChangeCancellable = nil
                viewModel = nil
            }
            
            // MARK: - Basic Tests
            
            it("has the correct title") {
                expect(viewModel.title).to(equal("NOTIFICATIONS_STYLE_CONTENT_TITLE".localized()))
            }

            it("has the correct number of items") {
                expect(viewModel.settingsData.count)
                    .toEventually(
                        equal(1),
                        timeout: .milliseconds(10)
                    )
                expect(viewModel.settingsData.first?.elements.count)
                    .toEventually(
                        equal(3),
                        timeout: .milliseconds(10)
                    )
            }
            
            it("has the correct default state") {
                expect(viewModel.settingsData.first?.elements )
                    .toEventually(
                        equal([
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.nameAndPreview,
                                title: "NOTIFICATIONS_SENDER_AND_MESSAGE".localized(),
                                action: .listSelection(
                                    isSelected: { true },
                                    storedSelection: true,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            ),
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.nameNoPreview,
                                title: "NOTIFICATIONS_SENDER_ONLY".localized(),
                                action: .listSelection(
                                    isSelected: { false },
                                    storedSelection: false,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            ),
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.noNameNoPreview,
                                title: "NOTIFICATIONS_NONE".localized(),
                                action: .listSelection(
                                    isSelected: { false },
                                    storedSelection: false,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            )
                        ]),
                        timeout: .milliseconds(10)
                    )
            }
            
            it("starts with the correct item active if not default") {
                mockStorage.write { db in
                    db[.preferencesNotificationPreviewType] = Preferences.NotificationPreviewType.nameNoPreview
                }
                viewModel = NotificationContentViewModel(storage: mockStorage)
                dataChangeCancellable = viewModel.observableSettingsData
                    .receiveOnMain(immediately: true)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { viewModel.updateSettings($0) }
                    )
                
                expect(viewModel.settingsData.first?.elements )
                    .toEventually(
                        equal([
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.nameAndPreview,
                                title: "NOTIFICATIONS_SENDER_AND_MESSAGE".localized(),
                                action: .listSelection(
                                    isSelected: { false },
                                    storedSelection: false,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            ),
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.nameNoPreview,
                                title: "NOTIFICATIONS_SENDER_ONLY".localized(),
                                action: .listSelection(
                                    isSelected: { true },
                                    storedSelection: true,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            ),
                            SettingInfo(
                                id: Preferences.NotificationPreviewType.noNameNoPreview,
                                title: "NOTIFICATIONS_NONE".localized(),
                                action: .listSelection(
                                    isSelected: { false },
                                    storedSelection: false,
                                    shouldAutoSave: true,
                                    selectValue: {}
                                )
                            )
                        ]),
                        timeout: .milliseconds(10)
                    )
            }
        }
    }
}
