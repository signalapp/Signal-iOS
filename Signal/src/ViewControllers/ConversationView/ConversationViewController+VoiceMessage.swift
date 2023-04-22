//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension ConversationViewController {
    func checkPermissionsAndStartRecordingVoiceMessage() {
        AssertIsOnMainThread()

        // Cancel any ongoing audio playback.
        cvAudioPlayer.stopAll()

        let inProgressVoiceMessage = VoiceMessageInProgressDraft(
            thread: thread,
            audioSession: audioSession,
            sleepManager: deviceSleepManager
        )
        viewState.inProgressVoiceMessage = inProgressVoiceMessage

        // Delay showing the voice memo UI for N ms to avoid a jarring transition
        // when you just tap and don't hold.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else { return }
            guard self.viewState.inProgressVoiceMessage === inProgressVoiceMessage else { return }
            self.configureScrollDownButtons()
            self.inputToolbar?.showVoiceMemoUI()
        }

        ows_askForMicrophonePermissions { [weak self] granted in
            guard let self = self else { return }
            guard self.viewState.inProgressVoiceMessage === inProgressVoiceMessage else { return }

            guard granted else {
                self.cancelRecordingVoiceMessage()
                self.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            self.startRecordingVoiceMessage(inProgressVoiceMessage)
        }
    }

    private func startRecordingVoiceMessage(_ inProgressVoiceMessage: VoiceMessageInProgressDraft) {
        AssertIsOnMainThread()

        ImpactHapticFeedback.impactOccurred(style: .light)

        do {
            try inProgressVoiceMessage.startRecording()
        } catch {
            owsFailDebug("Failed to start recording voice message \(error)")
            cancelRecordingVoiceMessage()
        }
    }

    func cancelRecordingVoiceMessage() {
        AssertIsOnMainThread()

        viewState.inProgressVoiceMessage?.stopRecordingAsync()
        viewState.inProgressVoiceMessage = nil

        NotificationHapticFeedback().notificationOccurred(.warning)

        clearVoiceMessageDraft()
        inputToolbar?.hideVoiceMemoUI(animated: true)
        configureScrollDownButtons()
    }

    private static let minimumVoiceMessageDuration: TimeInterval = 1

    @objc(finishRecordingVoiceMessageAndSendImmediately:)
    func finishRecordingVoiceMessage(sendImmediately: Bool = false) {
        AssertIsOnMainThread()

        guard let inProgressVoiceMessage = viewState.inProgressVoiceMessage else { return }
        viewState.inProgressVoiceMessage = nil

        inProgressVoiceMessage.stopRecording()

        guard let duration = inProgressVoiceMessage.duration, duration >= Self.minimumVoiceMessageDuration else {
            inputToolbar?.showVoiceMemoTooltip()
            cancelRecordingVoiceMessage()
            return
        }

        ImpactHapticFeedback.impactOccurred(style: .medium)

        configureScrollDownButtons()

        if sendImmediately {
            sendVoiceMessageDraft(inProgressVoiceMessage)
        } else {
            databaseStorage.asyncWrite {
                let interruptedDraft = inProgressVoiceMessage.convertToDraft(transaction: $0)
                DispatchQueue.main.async {
                    self.inputToolbar?.showVoiceMemoDraft(interruptedDraft)
                }
            }
        }
    }

    func sendVoiceMessageDraft(_ voiceMemoDraft: VoiceMessageSendableDraft) {
        inputToolbar?.hideVoiceMemoUI(animated: true)

        do {
            tryToSendAttachments([try voiceMemoDraft.prepareAttachment()], messageBody: nil)
            clearVoiceMessageDraft()
        } catch {
            owsFailDebug("Failed to send prepare voice message for sending \(error)")
        }
    }

    func clearVoiceMessageDraft() {
        databaseStorage.asyncWrite { [thread] in
            VoiceMessageInterruptedDraftStore.clearDraft(for: thread, transaction: $0)
        }
    }
}
