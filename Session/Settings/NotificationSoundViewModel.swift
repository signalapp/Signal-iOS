// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class NotificationSoundViewModel: SessionTableViewModel<NotificationSoundViewModel.NavButton, NotificationSettingsViewModel.Section, Preferences.Sound> {
    // MARK: - Config
    
    enum NavButton: Equatable {
        case cancel
        case save
    }
    
    public enum Section: SessionTableSection {
        case content
    }
    
    // FIXME: Remove `threadId` once we ditch the per-thread notification sound
    private let threadId: String?
    private var audioPlayer: OWSAudioPlayer?
    private var storedSelection: Preferences.Sound?
    private var currentSelection: CurrentValueSubject<Preferences.Sound?, Never> = CurrentValueSubject(nil)
    
    // MARK: - Initialization
    
    init(threadId: String? = nil) {
        self.threadId = threadId
    }
    
    deinit {
        self.audioPlayer?.stop()
        self.audioPlayer = nil
    }
    
    // MARK: - Navigation
    
    override var leftNavItems: AnyPublisher<[NavItem]?, Never> {
        Just([
            NavItem(
                id: .cancel,
                systemItem: .cancel,
                accessibilityIdentifier: "Cancel button"
            ) { [weak self] in
                self?.dismissScreen()
            }
        ]).eraseToAnyPublisher()
    }

    override var rightNavItems: AnyPublisher<[NavItem]?, Never> {
        currentSelection
            .removeDuplicates()
            .map { [weak self] currentSelection in (self?.storedSelection != currentSelection) }
            .map { isChanged in
                guard isChanged else { return [] }
                
                return [
                    NavItem(
                        id: .save,
                        systemItem: .save,
                        accessibilityIdentifier: "Save button"
                    ) { [weak self] in
                        self?.saveChanges()
                        self?.dismissScreen()
                    }
                ]
            }
           .eraseToAnyPublisher()
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
            self?.storedSelection = try {
                guard let threadId: String = self?.threadId else {
                    return db[.defaultNotificationSound]
                        .defaulting(to: .defaultNotificationSound)
                }
                
                return try SessionThread
                    .filter(id: threadId)
                    .select(.notificationSound)
                    .asRequest(of: Preferences.Sound.self)
                    .fetchOne(db)
                    .defaulting(
                        to: db[.defaultNotificationSound]
                            .defaulting(to: .defaultNotificationSound)
                    )
            }()
            self?.currentSelection.send(self?.currentSelection.value ?? self?.storedSelection)
            
            return [
                SectionModel(
                    model: .content,
                    elements: Preferences.Sound.notificationSounds
                        .map { sound in
                            SessionCell.Info(
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
                                rightAccessory: .radio(
                                    isSelected: { (self?.currentSelection.value == sound) },
                                    storedSelection: (self?.storedSelection == sound)
                                ),
                                onTap: {
                                    self?.currentSelection.send(sound)
                                    
                                    // Play the sound (to prevent UI lag we dispatch this to the next
                                    // run loop
                                    DispatchQueue.main.async {
                                        self?.audioPlayer?.stop()
                                        self?.audioPlayer = Preferences.Sound.audioPlayer(
                                            for: sound,
                                            behavior: .playback
                                        )
                                        self?.audioPlayer?.isLooping = false
                                        self?.audioPlayer?.play()
                                    }
                                }
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
    
    private func saveChanges() {
        guard let currentSelection: Preferences.Sound = self.currentSelection.value else { return }

        let threadId: String? = self.threadId
        
        Storage.shared.writeAsync { db in
            guard let threadId: String = threadId else {
                db[.defaultNotificationSound] = currentSelection
                return
            }
            
            try SessionThread
                .filter(id: threadId)
                .updateAll(
                    db,
                    SessionThread.Columns.notificationSound.set(to: currentSelection)
                )
        }
    }
}
