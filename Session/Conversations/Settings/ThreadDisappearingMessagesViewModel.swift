// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

class ThreadDisappearingMessagesViewModel: SettingsTableViewModel<ThreadDisappearingMessagesViewModel.NavButton, ThreadDisappearingMessagesViewModel.Section, ThreadDisappearingMessagesViewModel.Item> {
    // MARK: - Config
    
    enum NavButton: Equatable {
        case cancel
        case save
    }
    
    public enum Section: SettingSection {
        case content
    }
    
    public struct Item: Equatable, Hashable, Differentiable {
        let title: String
        
        public var differenceIdentifier: String { title }
    }
    
    // MARK: - Variables
    
    private let threadId: String
    private let config: DisappearingMessagesConfiguration
    private var storedSelection: TimeInterval
    private var currentSelection: CurrentValueSubject<TimeInterval, Never>
    
    // MARK: - Initialization
    
    init(threadId: String, config: DisappearingMessagesConfiguration) {
        self.threadId = threadId
        self.config = config
        self.storedSelection = (config.isEnabled ? config.durationSeconds : 0)
        self.currentSelection = CurrentValueSubject(self.storedSelection)
    }
    
    // MARK: - Navigation
    
    override var leftNavItems: AnyPublisher<[NavItem]?, Never> {
        Just([
            NavItem(
                id: .cancel,
                systemItem: .cancel,
                accessibilityIdentifier: "Cancel button"
            )
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
                    )
                ]
            }
           .eraseToAnyPublisher()
    }
    
    override var closeScreen: AnyPublisher<Bool, Never> {
        navItemTapped
            .handleEvents(receiveOutput: { [weak self] navItemId in
                switch navItemId {
                    case .save: self?.saveChanges()
                    default: break
                }
                self?.setIsEditing(true)
            })
            .map { _ in false }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Content
    
    override var title: String { "DISAPPEARING_MESSAGES".localized() }
    
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
        .trackingConstantRegion { [weak self, config = self.config] db -> [SectionModel] in
            return [
                SectionModel(
                    model: .content,
                    elements: [
                        SettingInfo(
                            id: Item(title: "DISAPPEARING_MESSAGES_OFF".localized()),
                            title: "DISAPPEARING_MESSAGES_OFF".localized(),
                            action: .listSelection(
                                isSelected: { (self?.currentSelection.value == 0) },
                                storedSelection: (self?.config.isEnabled == false),
                                shouldAutoSave: false,
                                selectValue: { self?.currentSelection.send(0) }
                            )
                        )
                    ].appending(
                        contentsOf: DisappearingMessagesConfiguration.validDurationsSeconds
                            .map { duration in
                                let title: String = NSString.formatDurationSeconds(
                                    UInt32(duration),
                                    useShortFormat: false
                                )
                                
                                return SettingInfo(
                                    id: Item(title: title),
                                    title: title,
                                    action: .listSelection(
                                        isSelected: { (self?.currentSelection.value == duration) },
                                        storedSelection: (self?.config.durationSeconds == duration),
                                        shouldAutoSave: false,
                                        selectValue: { self?.currentSelection.send(duration) }
                                    )
                                )
                            }
                    )
                )
            ]
        }
        .removeDuplicates()
    
    // MARK: - Functions

    public override func updateSettings(_ updatedSettings: [SectionModel]) {
        self._settingsData = updatedSettings
    }
    
    private func saveChanges() {
        let threadId: String = self.threadId
        let currentSelection: TimeInterval = self.currentSelection.value
        let updatedConfig: DisappearingMessagesConfiguration = self.config
            .with(
                isEnabled: (currentSelection != 0),
                durationSeconds: currentSelection
            )
        
        guard self.config != updatedConfig else { return }
        
        Storage.shared.writeAsync { db in
            guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                return
            }
            
            let config: DisappearingMessagesConfiguration = try DisappearingMessagesConfiguration
                .fetchOne(db, id: threadId)
                .defaulting(to: DisappearingMessagesConfiguration.defaultWith(threadId))
                .with(
                    isEnabled: (currentSelection != 0),
                    durationSeconds: currentSelection
                )
                .saved(db)
            
            let interaction: Interaction = try Interaction(
                threadId: threadId,
                authorId: getUserHexEncodedPublicKey(db),
                variant: .infoDisappearingMessagesUpdate,
                body: config.messageInfoString(with: nil),
                timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000))
            )
            .inserted(db)
            
            try MessageSender.send(
                db,
                message: ExpirationTimerUpdate(
                    syncTarget: nil,
                    duration: UInt32(floor(updatedConfig.isEnabled ? updatedConfig.durationSeconds : 0))
                ),
                interactionId: interaction.id,
                in: thread
            )
        }
    }
}
