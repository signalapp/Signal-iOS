//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSSyncGroupsMessage {

    @objc
    public func buildPlainTextAttachmentFile(transaction: SDSAnyReadTransaction) -> URL? {
        let fileUrl = OWSFileSystem.temporaryFileUrl(isAvailableWhileDeviceLocked: true)
        guard let outputStream = OutputStream(url: fileUrl, append: false) else {
            owsFailDebug("Could not open outputStream.")
            return nil
        }
        let outputStreamDelegate = OWSStreamDelegate()
        outputStream.delegate = outputStreamDelegate
        outputStream.schedule(in: .current, forMode: .default)
        outputStream.open()
        guard outputStream.streamStatus == .open else {
            owsFailDebug("Could not open outputStream.")
            return nil
        }

        func closeOutputStream() {
            outputStream.remove(from: .current, forMode: .default)
            outputStream.close()
        }

        let groupsOutputStream = OWSGroupsOutputStream(outputStream: outputStream)
        let batchSize: UInt = CurrentAppContext().isNSE ? 16 : 100
        TSGroupThread.anyEnumerate(transaction: transaction, batchSize: batchSize) { (thread, _) in
            // We only sync v1 groups via group sync messages.
            guard let groupThread = thread as? TSGroupThread,
                  groupThread.isGroupV1Thread else {
                return
            }
            groupsOutputStream.writeGroup(groupThread, transaction: transaction)
        }

        closeOutputStream()

        guard !groupsOutputStream.hasError else {
            owsFailDebug("Could not write groups sync stream.")
            return nil
        }
        guard outputStream.streamStatus == .closed,
              !outputStreamDelegate.hadError else {
                  owsFailDebug("Could not close stream.")
                  return nil
              }

        return fileUrl
    }
}

// MARK: -

@objc
public class OWSStreamDelegate: NSObject, StreamDelegate {
    private let _hadError = AtomicBool(false)
    @objc
    public var hadError: Bool { _hadError.get() }

    @objc
    public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .errorOccurred {
            _hadError.set(true)
        }
    }
}
