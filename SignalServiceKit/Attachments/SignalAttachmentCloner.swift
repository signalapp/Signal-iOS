//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalAttachmentCloner {

    // TODO: add v2 attachment cloning methods

    func cloneAsSignalAttachment(request: CloneAsSignalAttachmentRequest) throws -> SignalAttachment
}

public class SignalAttachmentClonerImpl: SignalAttachmentCloner {

    public init() {}

    public func cloneAsSignalAttachment(
        request: CloneAsSignalAttachmentRequest
    ) throws -> SignalAttachment {
        let newUrl = OWSFileSystem.temporaryFileUrl(fileExtension: request.sourceUrl.pathExtension)
        try FileManager.default.copyItem(at: request.sourceUrl, to: newUrl)

        let clonedDataSource = try DataSourcePath.dataSource(with: newUrl,
                                                             shouldDeleteOnDeallocation: true)
        clonedDataSource.sourceFilename = request.sourceFilename

        var signalAttachment: SignalAttachment
        if request.isVoiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: clonedDataSource, dataUTI: request.dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: clonedDataSource, dataUTI: request.dataUTI)
        }
        signalAttachment.captionText = request.caption
        signalAttachment.isBorderless = request.isBorderless
        signalAttachment.isLoopingVideo = request.isLoopingVideo
        return signalAttachment
    }
}

#if TESTABLE_BUILD

public class SignalAttachmentClonerMock: SignalAttachmentCloner {

    public func cloneAsSignalAttachment(
        request: CloneAsSignalAttachmentRequest
    ) throws -> SignalAttachment {
        let dataSource = try DataSourcePath.dataSource(
            with: request.sourceUrl,
            shouldDeleteOnDeallocation: false
        )
        dataSource.sourceFilename = request.sourceFilename

        var signalAttachment: SignalAttachment
        if request.isVoiceMessage {
            signalAttachment = SignalAttachment.voiceMessageAttachment(dataSource: dataSource, dataUTI: request.dataUTI)
        } else {
            signalAttachment = SignalAttachment.attachment(dataSource: dataSource, dataUTI: request.dataUTI)
        }
        signalAttachment.captionText = request.caption
        signalAttachment.isBorderless = request.isBorderless
        signalAttachment.isLoopingVideo = request.isLoopingVideo
        return signalAttachment
    }
}

#endif
