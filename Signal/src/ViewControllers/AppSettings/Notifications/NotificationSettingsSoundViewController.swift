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
            self.originalNotificationSound = Sounds.globalNotificationSound
        }

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SETTINGS_ITEM_NOTIFICATION_SOUND",
            comment: "Label for settings view that allows user to change the notification sound."
        )

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
        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            self?.didTapCancel()
        }

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()

        for sound in Sounds.allNotificationSounds {
            let soundName: String
            if sound == .standard(.note) {
                soundName = String(
                    format: OWSLocalizedString(
                        "SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT",
                        comment: "Format string for the default 'Note' sound. Embeds the system {{sound name}}."
                    ),
                    sound.displayName
                )
            } else {
                soundName = sound.displayName
            }

            section.add(.init(
                text: soundName,
                actionBlock: { [weak self] in
                    self?.soundWasSelected(sound)
                },
                accessoryType: sound == notificationSound ? .checkmark : .none
            ))
        }

        section.add(.disclosureItem(
            withText: OWSLocalizedString(
                "NOTIFICATIONS_SECTION_SOUNDS_ADD_CUSTOM_SOUND",
                comment: "Label for settings UI that allows user to add a new notification sound."
            ),
            actionBlock: { [weak self] in
                guard let self = self else { return }
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
            }
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

    @objc
    private func didTapDone() {
        if let thread {
            Sounds.setNotificationSound(notificationSound, forThread: thread)
        } else {
            Sounds.setGlobalNotificationSound(notificationSound)
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
