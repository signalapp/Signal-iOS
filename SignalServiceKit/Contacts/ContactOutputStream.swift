//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class ContactOutputStream {

    let chunkedOutputTransform = ChunkedOutputStreamTransform()
    let outputStream: OutputStream

    init(outputStream: OutputStream) {
        self.outputStream = outputStream
    }

    func writeContact(
        aci: Aci?,
        phoneNumber: E164?,
        signalAccount: SignalAccount?,
        disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration?,
        inboxPosition: Int?
    ) throws {
        let contactBuilder = SSKProtoContactDetails.builder()
        if let phoneNumber {
            contactBuilder.setContactE164(phoneNumber.stringValue)
        }
        if let aci {
            contactBuilder.setAci(aci.serviceIdString)
        }

        // TODO: this should be removed after a 90-day timer from when Desktop stops
        // relying on names in contact sync messages, and is instead using the
        // `system[Given|Family]Name` fields from StorageService ContactRecords.
        if let fullName = signalAccount?.fullName {
            contactBuilder.setName(fullName)
        }

        if let inboxPosition, let truncatedInboxPosition = UInt32(exactly: inboxPosition) {
            contactBuilder.setInboxPosition(truncatedInboxPosition)
        }

        let avatarJpegData = signalAccount?.buildContactAvatarJpegData()
        if let avatarJpegData {
            let avatarBuilder = SSKProtoContactDetailsAvatar.builder()
            avatarBuilder.setContentType(MimeType.imageJpeg.rawValue)
            avatarBuilder.setLength(UInt32(avatarJpegData.count))
            contactBuilder.setAvatar(avatarBuilder.buildInfallibly())
        }

        // Always ensure the "expire timer" property is set so that desktop
        // can easily distinguish between a modern client declaring "off" vs a
        // legacy client "not specifying".
        contactBuilder.setExpireTimer(0)
        contactBuilder.setExpireTimerVersion(disappearingMessagesConfiguration?.timerVersion ?? 1)
        if let disappearingMessagesConfiguration, disappearingMessagesConfiguration.isEnabled {
            contactBuilder.setExpireTimer(disappearingMessagesConfiguration.durationSeconds)
        }

        let contactData: Data
        do {
            contactData = try chunkedOutputTransform.transform(data: contactBuilder.buildSerializedData())
        } catch {
            owsFailDebug("Couldn't serialize protobuf: \(error)")
            return // Eat the error and silently drop this entry.
        }
        try outputStream.write(data: contactData)
        if let avatarJpegData {
            try outputStream.write(data: avatarJpegData)
        }
    }
}
