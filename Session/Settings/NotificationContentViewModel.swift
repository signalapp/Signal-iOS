// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class NotificationContentViewModel: SessionTableViewModel<NoNav, NotificationSettingsViewModel.Section, Preferences.NotificationPreviewType> {
    private let storage: Storage
    
    // MARK: - Initialization
    
    init(storage: Storage = Storage.shared) {
        self.storage = storage
    }
    
    // MARK: - Section
    
    public enum Section: SessionTableSection {
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
        .trackingConstantRegion { [storage] db -> [SectionModel] in
            let currentSelection: Preferences.NotificationPreviewType? = db[.preferencesNotificationPreviewType]
                .defaulting(to: .defaultPreviewType)
            
            return [
                SectionModel(
                    model: .content,
                    elements: Preferences.NotificationPreviewType.allCases
                        .map { previewType in
                            SessionCell.Info(
                                id: previewType,
                                title: previewType.name,
                                rightAccessory: .radio(
                                    isSelected: { (currentSelection == previewType) }
                                ),
                                onTap: { [weak self] in
                                    storage.writeAsync { db in
                                        db[.preferencesNotificationPreviewType] = previewType
                                    }
                                    
                                    self?.dismissScreen()
                                }
                            )
                        }
                )
            ]
        }
        .removeDuplicates()
        .publisher(in: storage)
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
}
