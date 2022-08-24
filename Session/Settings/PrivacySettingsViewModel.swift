// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class PrivacySettingsViewModel: SettingsTableViewModel<PrivacySettingsViewModel.Section, PrivacySettingsViewModel.Section> {
    // MARK: - Section
    
    public enum Section: SettingSection {
        case screenLock
        case screenshotNotifications
        case readReceipts
        case typingIndicators
        case linkPreviews
        case calls
        
        var title: String {
            switch self {
                case .screenLock: return "PRIVACY_SECTION_SCREEN_SECURITY".localized()
                case .screenshotNotifications: return ""   // No title
                case .readReceipts: return "PRIVACY_SECTION_READ_RECEIPTS".localized()
                case .typingIndicators: return "PRIVACY_SECTION_TYPING_INDICATORS".localized()
                case .linkPreviews: return "PRIVACY_SECTION_LINK_PREVIEWS".localized()
                case .calls: return "PRIVACY_SECTION_CALLS".localized()
            }
        }
    }
    
    // MARK: - Content
    
    override var title: String { "PRIVACY_TITLE".localized() }
    
    private var _settingsData: [SectionModel] = []
    public override var settingsData: [SectionModel] { _settingsData }
    
    public override var observableSettingsData: ObservableData { _observableSettingsData }
    
    /// This is all the data the screen needs to populate itself, please see the following link for tips to help optimise
    /// performance https://github.com/groue/GRDB.swift#valueobservation-performance
    ///
    /// **Note:** This observation will be triggered twice immediately (and be de-duped by the `removeDuplicates`)
    /// this is due to the behaviour of `ValueConcurrentObserver.asyncStartObservation` which triggers it's own
    /// fetch (after the ones in `ValueConcurrentObserver.asyncStart`/`ValueConcurrentObserver.syncStart`)
    /// just in case the database has changed between the two reads - unfortunately it doesn't look like there is a way to prevent this
    private lazy var _observableSettingsData: ObservableData = ValueObservation
        .trackingConstantRegion { db -> [SectionModel] in
            return [
                SectionModel(
                    model: .screenLock,
                    elements: [
                        SettingInfo(
                            id: .screenLock,
                            title: "PRIVACY_SCREEN_SECURITY_LOCK_SESSION_TITLE".localized(),
                            subtitle: "PRIVACY_SCREEN_SECURITY_LOCK_SESSION_DESCRIPTION".localized(),
                            action: .settingBool(key: .isScreenLockEnabled)
                        )
                    ]
                ),
                SectionModel(
                    model: .screenshotNotifications,
                    elements: [
                        SettingInfo(
                            id: .screenshotNotifications,
                            title: "PRIVACY_SCREEN_SECURITY_SCREENSHOT_NOTIFICATIONS_TITLE".localized(),
                            subtitle: "PRIVACY_SCREEN_SECURITY_SCREENSHOT_NOTIFICATIONS_DESCRIPTION".localized(),
                            action: .settingBool(key: .showScreenshotNotifications)
                        )
                    ]
                ),
                SectionModel(
                    model: .readReceipts,
                    elements: [
                        SettingInfo(
                            id: .readReceipts,
                            title: "PRIVACY_READ_RECEIPTS_TITLE".localized(),
                            subtitle: "PRIVACY_READ_RECEIPTS_DESCRIPTION".localized(),
                            action: .settingBool(key: .areReadReceiptsEnabled)
                        )
                    ]
                ),
                SectionModel(
                    model: .typingIndicators,
                    elements: [
                        SettingInfo(
                            id: .typingIndicators,
                            title: "PRIVACY_TYPING_INDICATORS_TITLE".localized(),
                            subtitle: "PRIVACY_TYPING_INDICATORS_DESCRIPTION".localized(),
                            action: .settingBool(key: .typingIndicatorsEnabled)
                        )
                    ]
                ),
                SectionModel(
                    model: .linkPreviews,
                    elements: [
                        SettingInfo(
                            id: .linkPreviews,
                            title: "PRIVACY_LINK_PREVIEWS_TITLE".localized(),
                            subtitle: "PRIVACY_LINK_PREVIEWS_DESCRIPTION".localized(),
                            action: .settingBool(key: .areLinkPreviewsEnabled)
                        )
                    ]
                ),
                SectionModel(
                    model: .calls,
                    elements: [
                        SettingInfo(
                            id: .calls,
                            title: "PRIVACY_CALLS_TITLE".localized(),
                            subtitle: "PRIVACY_CALLS_DESCRIPTION".localized(),
                            action: .settingBool(
                                key: .areCallsEnabled,
                                confirmationInfo: ConfirmationModal.Info(
                                    title: "PRIVACY_CALLS_WARNING_TITLE".localized(),
                                    explanation: "PRIVACY_CALLS_WARNING_DESCRIPTION".localized(),
                                    stateToShow: .whenDisabled,
                                    confirmStyle: .textPrimary
                                ) { requestMicrophonePermissionIfNeeded() }
                            )
                        )
                    ]
                )
            ]
        }
        .removeDuplicates()
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    public override func saveChanges() {}
}
