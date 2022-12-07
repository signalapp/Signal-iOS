//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

class NotificationSettingsSoundViewController: OWSTableViewController2 {
    private let thread: TSThread?
    private let completion: (() -> Void)?

    private let originalNotificationSound: OWSSound
    private lazy var notificationSound: OWSSound = originalNotificationSound

    init(thread: TSThread? = nil, completion: (() -> Void)? = nil) {
        self.thread = thread
        self.completion = completion

        if let thread = thread {
            self.originalNotificationSound = OWSSounds.notificationSound(for: thread)
        } else {
            self.originalNotificationSound = OWSSounds.globalNotificationSound()
        }

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

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

        for sound in OWSSounds.allNotificationSounds().map({ $0.uintValue }) {
            let soundName: String
            if sound == OWSStandardSound.note.rawValue {
                soundName = String(
                    format: NSLocalizedString(
                        "SETTINGS_AUDIO_DEFAULT_TONE_LABEL_FORMAT",
                        comment: "Format string for the default 'Note' sound. Embeds the system {{sound name}}."
                    ),
                    OWSSounds.displayName(forSound: sound)
                )
            } else {
                soundName = OWSSounds.displayName(forSound: sound)
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
            withText: NSLocalizedString(
                "NOTIFICATIONS_SECTION_SOUNDS_ADD_CUSTOM_SOUND",
                comment: "Label for settings UI that allows user to add a new notification sound."
            ),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let picker = UIDocumentPickerViewController(
                    documentTypes: [
                        "com.microsoft.waveform-audio",
                        "public.aifc-audio",
                        "public.aiff-audio",
                        "com.apple.coreaudio-format",
                        "public.mp3",
                        "com.apple.mpeg-4-ringtone"
                    ],
                    in: .import
                )
                picker.delegate = self
                self.present(picker, animated: true)
            }
        ))

        contents.addSection(section)

        self.contents = contents
    }

    private var player: AudioPlayer?
    private func soundWasSelected(_ sound: OWSSound) {
        player?.stop()
        player = OWSSounds.audioPlayer(forSound: sound, audioBehavior: .playback)
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

    @objc
    func didTapCancel() {
        guard hasUnsavedChanges else {
            stopPlayingAndDismiss()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.stopPlayingAndDismiss()
        })
    }

    @objc
    func didTapDone() {
        if let thread = thread {
            OWSSounds.setNotificationSound(notificationSound, for: thread)
        } else {
            OWSSounds.setGlobalNotificationSound(notificationSound)
        }

        stopPlayingAndDismiss()
    }
}

extension NotificationSettingsSoundViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        OWSSounds.import(at: urls)
        updateTableContents()
    }
}
