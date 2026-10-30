//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UniformTypeIdentifiers

import SignalServiceKit
import SignalUI

class NotificationSettingsSoundViewController: OWSTableViewController2 {
    private let thread: TSThread?
    private let completion: (() -> Void)?

    private let originalNotificationSound: Sound
    private lazy var notificationSound: Sound = originalNotificationSound

    init(thread: TSThread? = nil, completion: (() -> Void)? = nil) {
        self.thread = thread
        self.completion = completion

        if let thread {
            self.originalNotificationSound = Sounds.notificationSoundWithSneakyTransaction(forThreadUniqueId: thread.uniqueId)
        } else {
            self.originalNotificationSound = DependenciesBridge.shared.db.read { tx in
                DependenciesBridge.shared.notificationPreferencesManager.globalNotificationSound(tx: tx)
            }
        }

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_ITEM_NOTIFICATION_SOUND",
            comment: "Label for settings view that allows user to change the notification sound.",
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapCancel()
        }

        navigationItem.rightBarButtonItem = .setButton { [weak self] in
            self?.didTapDone()
        }

        updateTableContents()
        updateNavigation()
    }

    private var hasUnsavedChanges: Bool {
        notificationSound != originalNotificationSound
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        for sound in Sounds.allNotificationSounds {
            let soundName: String
            if sound == NotificationPreferencesManager.Defaults.globalNotificationSound {
                soundName = String.nonPluralLocalizedStringWithFormat(
                    OWSLocalizedString(
                        "SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT",
                        comment: "Format string for the default 'Note' sound. Embeds the system {{sound name}}.",
                    ),
                    sound.displayName,
                )
            } else {
                soundName = sound.displayName
            }

            let contextMenuActionProvider: UIContextMenuActionProvider?
            if case .custom = sound {
                contextMenuActionProvider = { [weak self] _ in
                    guard let self else { return nil }
                    return UIMenu(children: [
                        UIAction(
                            title: OWSLocalizedString(
                                "NOTIFICATIONS_DELETE_CUSTOM_SOUND_ACTION",
                                comment: "Context menu action that deletes a custom notification sound.",
                            ),
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive,
                        ) { _ in
                            self.didTapDeleteCustomSound(sound)
                        },
                    ])
                }
            } else {
                contextMenuActionProvider = nil
            }

            section.add(.init(
                text: soundName,
                actionBlock: { [weak self] in
                    self?.soundWasSelected(sound)
                },
                accessoryType: sound == notificationSound ? .checkmark : .none,
                contextMenuActionProvider: contextMenuActionProvider,
            ))
        }

        section.add(.disclosureItem(
            withText: OWSLocalizedString(
                "NOTIFICATIONS_SECTION_SOUNDS_ADD_CUSTOM_SOUND",
                comment: "Label for settings UI that allows user to add a new notification sound.",
            ),
            actionBlock: { [weak self] in
                guard let self else { return }
                var contentTypes: [UTType] = [.wav, .aiff, .mp3]
                for additionalUti in [
                    "public.aifc-audio",
                    "com.apple.coreaudio-format",
                    "com.apple.mpeg-4-ringtone",
                ] {
                    if let element = UTType(additionalUti) {
                        contentTypes.append(element)
                    }
                }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
                picker.delegate = self
                self.present(picker, animated: true)
            },
        ))

        contents.add(section)

        self.contents = contents
    }

    private var player: AudioPlayer?
    private func soundWasSelected(_ sound: Sound) {
        player?.stop()
        player = Sounds.audioPlayer(forSound: sound, audioBehavior: .playback)
        player?.isLooping = false
        player?.play()

        guard notificationSound != sound else { return }

        notificationSound = sound
        updateTableContents()
        updateNavigation()
    }

    private func stopPlayingAndDismiss() {
        player?.stop()
        dismiss(animated: true)
        completion?()
    }

    private func didTapCancel() {
        guard hasUnsavedChanges else {
            stopPlayingAndDismiss()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.stopPlayingAndDismiss()
        })
    }

    private func didTapDeleteCustomSound(_ sound: Sound) {
        OWSActionSheets.showConfirmationAlert(
            title: String.nonPluralLocalizedStringWithFormat(
                OWSLocalizedString(
                    "NOTIFICATIONS_DELETE_CUSTOM_SOUND_CONFIRMATION_FORMAT",
                    comment: "Title of the confirmation alert shown before deleting a custom notification sound. Embeds the {{sound name}}.",
                ),
                sound.displayName,
            ),
            proceedTitle: OWSLocalizedString(
                "NOTIFICATIONS_DELETE_CUSTOM_SOUND_ACTION",
                comment: "Context menu action that deletes a custom notification sound.",
            ),
            proceedStyle: .destructive,
            proceedAction: { [weak self] _ in
                self?.deleteCustomSound(sound)
            },
            fromViewController: self,
        )
    }

    private func deleteCustomSound(_ sound: Sound) {
        player?.stop()
        player = nil

        Sounds.deleteCustomSound(sound)

        if notificationSound == sound {
            notificationSound = NotificationPreferencesManager.Defaults.globalNotificationSound
        }
        updateTableContents()
        updateNavigation()
    }

    private func didTapDone() {
        if let thread {
            Sounds.setNotificationSound(notificationSound, forThread: thread)
        } else {
            DependenciesBridge.shared.db.write { tx in
                DependenciesBridge.shared.notificationPreferencesManager
                    .setGlobalNotificationSound(notificationSound, tx: tx)
            }
        }

        stopPlayingAndDismiss()
    }
}

extension NotificationSettingsSoundViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        Sounds.importSoundsAtUrls(urls)
        updateTableContents()
    }
}
