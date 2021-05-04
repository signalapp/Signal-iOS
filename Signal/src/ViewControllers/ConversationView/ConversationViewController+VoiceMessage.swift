//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

extension ConversationViewController {
    @objc
    func checkPermissionsAndStartRecordingVoiceMessage() {
        AssertIsOnMainThread()

        // Cancel any ongoing audio playback.
        cvAudioPlayer.stopAll()

        SelectionHapticFeedback().selectionChanged()
        inputToolbar?.showVoiceMemoUI()

        let voiceMessageModel = VoiceMessageModel(thread: thread)
        viewState.currentVoiceMessageModel = voiceMessageModel
        ows_askForMicrophonePermissions { [weak self] granted in
            guard let self = self else { return }
            guard self.viewState.currentVoiceMessageModel === voiceMessageModel else { return }

            guard granted else {
                self.cancelRecordingVoiceMessage()
                self.ows_showNoMicrophonePermissionActionSheet()
                return
            }

            self.startRecordingVoiceMessage()
        }
    }

    private func startRecordingVoiceMessage() {
        AssertIsOnMainThread()

        guard let voiceMessageModel = viewState.currentVoiceMessageModel else {
            return owsFailDebug("Unexpectedly missing voice message model")
        }

        do {
            try voiceMessageModel.startRecording()
        } catch {
            owsFailDebug("Failed to start recording voice message \(error)")
            cancelRecordingVoiceMessage()
        }
    }

    @objc
    func cancelRecordingVoiceMessage() {
        AssertIsOnMainThread()

        viewState.currentVoiceMessageModel?.stopRecording()
        clearVoiceMessageDraft()
        viewState.currentVoiceMessageModel = nil
        inputToolbar?.cancelVoiceMemoIfNecessary()
        inputToolbar?.hideVoiceMemoUI(true)
    }

    private static let minimumVoiceMessageDuration: TimeInterval = 1

    @objc(finishRecordingVoiceMessageAndSendImmediately:)
    func finishRecordingVoiceMessage(sendImmediately: Bool = false) {
        defer { viewState.currentVoiceMessageModel = nil }
        guard let voiceMessageModel = viewState.currentVoiceMessageModel else { return }

        let duration = voiceMessageModel.stopRecording()

        SelectionHapticFeedback().selectionChanged()

        guard duration >= Self.minimumVoiceMessageDuration else {
            presentToast(text: NSLocalizedString(
                "VOICE_MESSAGE_TOO_SHORT_ALERT_MESSAGE",
                comment: "Message for the alert indicating the 'voice message' needs to be held to be held down to record."
            ))
            cancelRecordingVoiceMessage()
            return
        }

        if sendImmediately {
            inputToolbar?.hideVoiceMemoUI(true)
            sendVoiceMessageModel(voiceMessageModel)
        } else {
            databaseStorage.asyncWrite { voiceMessageModel.saveDraft(transaction: $0) }
        }
    }

    func sendVoiceMessageModel(_ voiceMessageModel: VoiceMessageModel) {
        var attachment: SignalAttachment?
        databaseStorage.asyncWrite { transaction in
            do {
                attachment = try voiceMessageModel.consumeForSending(transaction: transaction)
            } catch {
                owsFailDebug("Failed to send prepare voice message for sending \(error)")
            }
        } completion: {
            guard let attachment = attachment else { return }
            self.tryToSendAttachments([attachment], messageBody: nil)
        }
    }

    func clearVoiceMessageDraft() {
        databaseStorage.asyncWrite { [thread] in VoiceMessageModel.clearDraft(for: thread, transaction: $0) }
    }
}
