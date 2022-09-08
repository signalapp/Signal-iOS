// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class NotificationSettingsViewModel: SettingsTableViewModel<NoNav, NotificationSettingsViewModel.Section, NotificationSettingsViewModel.Setting> {
    // MARK: - Config
    
    public enum Section: SettingSection {
        case strategy
        case style
        case content
        
        var title: String? {
            switch self {
                case .strategy: return "NOTIFICATIONS_SECTION_STRATEGY".localized()
                case .style: return "NOTIFICATIONS_SECTION_STYLE".localized()
                case .content: return nil
            }
        }
        
        var style: SettingSectionHeaderStyle {
            switch self {
                case .content: return .padding
                default: return .title
            }
        }
    }
    
    public enum Setting: Differentiable {
        case strategyUseFastMode
        case styleSound
        case styleSoundWhenAppIsOpen
        case content
    }
    
    // MARK: - Content
    
    override var title: String { "NOTIFICATIONS_TITLE".localized() }
    
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
                    model: .strategy,
                    elements: [
                        SettingInfo(
                            id: .strategyUseFastMode,
                            title: "NOTIFICATIONS_STRATEGY_FAST_MODE_TITLE".localized(),
                            subtitle: "NOTIFICATIONS_STRATEGY_FAST_MODE_DESCRIPTION".localized(),
                            action: .userDefaultsBool(
                                defaults: UserDefaults.standard,
                                key: "isUsingFullAPNs",
                                onChange: {
                                    // Force sync the push tokens on change
                                    SyncPushTokensJob.run(uploadOnlyIfStale: false)
                                }
                            ),
                            extraActionTitle: { theme, primaryColor in
                                NSMutableAttributedString()
                                    .appending(
                                        NSAttributedString(
                                            string: "NOTIFICATIONS_STRATEGY_FAST_MODE_ACTION_1".localized(),
                                            attributes: [
                                                .foregroundColor: primaryColor.color
                                            ]
                                        )
                                    )
                                    .appending(
                                        NSAttributedString(
                                            string: "NOTIFICATIONS_STRATEGY_FAST_MODE_ACTION_2".localized(),
                                            attributes: [
                                                .foregroundColor: (theme.colors[.textPrimary] ?? .white)
                                            ]
                                        )
                                    )
                            },
                            onExtraAction: { UIApplication.shared.openSystemSettings() }
                        )
                    ]
                ),
                SectionModel(
                    model: .style,
                    elements: [
                        SettingInfo(
                            id: .styleSound,
                            title: "NOTIFICATIONS_STYLE_SOUND_TITLE".localized(),
                            action: .settingEnum(
                                db,
                                type: Preferences.Sound.self,
                                key: .defaultNotificationSound,
                                titleGenerator: { $0.defaulting(to: .defaultNotificationSound).displayName },
                                createUpdateScreen: {
                                    SettingsTableViewController(viewModel: NotificationSoundViewModel())
                                }
                            )
                        ),
                        SettingInfo(
                            id: .styleSoundWhenAppIsOpen,
                            title: "NOTIFICATIONS_STYLE_SOUND_WHEN_OPEN_TITLE".localized(),
                            action: .settingBool(key: .playNotificationSoundInForeground)
                        )
                    ]
                ),
                SectionModel(
                    model: .content,
                    elements: [
                        SettingInfo(
                            id: .content,
                            title: "NOTIFICATIONS_STYLE_CONTENT_TITLE".localized(),
                            subtitle: "NOTIFICATIONS_STYLE_CONTENT_DESCRIPTION".localized(),
                            action: .settingEnum(
                                db,
                                type: Preferences.NotificationPreviewType.self,
                                key: .preferencesNotificationPreviewType,
                                titleGenerator: { $0.defaulting(to: .defaultPreviewType).name },
                                createUpdateScreen: {
                                    SettingsTableViewController(viewModel: NotificationContentViewModel())
                                }
                            )
                        )
                    ]
                )
            ]
        }
        .removeDuplicates()
        .publisher(in: Storage.shared)
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
}
