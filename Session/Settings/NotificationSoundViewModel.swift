// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class NotificationSoundViewModel: SettingsTableViewModel<NotificationSettingsViewModel.Section, Preferences.Sound> {
    private var audioPlayer: OWSAudioPlayer?
    private var currentSelection: Preferences.Sound?
    
    deinit {
        self.audioPlayer?.stop()
        self.audioPlayer = nil
    }
    
    // MARK: - Section
    
    public enum Section: SettingSection {
        case content
        
        var title: String { return "" }   // No title
    }
    
    // MARK: - Content
    
    override var title: String { "NOTIFICATIONS_STYLE_SOUND_TITLE".localized() }
    
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
            self?.currentSelection = (self?.currentSelection ?? db[.defaultNotificationSound])
                .defaulting(to: .defaultNotificationSound)
            
            return [
                SectionModel(
                    model: .content,
                    elements: Preferences.Sound.notificationSounds
                        .map { sound in
                            SettingInfo(
                                id: sound,
                                title: {
                                    guard sound != .note else {
                                        return String(
                                            format: "SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT".localized(),
                                            sound.displayName
                                        )
                                    }
                                    
                                    return sound.displayName
                                }(),
                                action: .listSelection(
                                    isSelected: { (self?.currentSelection == sound) },
                                    storedSelection: (
                                        sound == db[.defaultNotificationSound]
                                            .defaulting(to: .defaultNotificationSound)
                                    ),
                                    shouldAutoSave: false,
                                    selectValue: {
                                        self?.currentSelection = sound
                                        
                                        // Play the sound (to prevent UI lag we dispatch this to the next
                                        // run loop
                                        DispatchQueue.main.async {
                                            self?.audioPlayer?.stop()
                                            self?.audioPlayer = SMKSound.audioPlayer(
                                                for: sound.rawValue,
                                                audioBehavior: .playback
                                            )
                                            self?.audioPlayer?.isLooping = false
                                            self?.audioPlayer?.play()
                                        }
                                    }
                                )
                            )
                        }
                )
            ]
        }
        .removeDuplicates()
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    public override func saveChanges() {
        guard let currentSelection: Preferences.Sound = self.currentSelection else { return }
        
        Storage.shared.write { db in
            db[.defaultNotificationSound] = currentSelection
        }
    }
}
