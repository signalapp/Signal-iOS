// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class NotificationContentViewModel: SettingsTableViewModel<NoNav, NotificationSettingsViewModel.Section, Preferences.NotificationPreviewType> {
    // MARK: - Section
    
    public enum Section: SettingSection {
        case content
    }
    
    // MARK: - Content
    
    override var title: String { "NOTIFICATIONS_STYLE_CONTENT_TITLE".localized() }
    
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
        .trackingConstantRegion { [weak self] db -> [SectionModel] in
            let currentSelection: Preferences.NotificationPreviewType? = db[.preferencesNotificationPreviewType]
                .defaulting(to: .defaultPreviewType)
            
            return [
                SectionModel(
                    model: .content,
                    elements: Preferences.NotificationPreviewType.allCases
                        .map { previewType in
                            SettingInfo(
                                id: previewType,
                                title: previewType.name,
                                action: .listSelection(
                                    isSelected: { (currentSelection == previewType) },
                                    storedSelection: (currentSelection == previewType),
                                    shouldAutoSave: true,
                                    selectValue: {
                                        Storage.shared.write { db in
                                            db[.preferencesNotificationPreviewType] = previewType
                                        }
                                    }
                                )
                            )
                        }
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
