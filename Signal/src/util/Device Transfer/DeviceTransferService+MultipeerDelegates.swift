//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity
import SignalCoreKit
import SignalServiceKit

extension DeviceTransferService: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer newDevicePeerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Logger.info("Notifying of discovered new device \(newDevicePeerID)")
        notifyObservers { $0.deviceTransferServiceDiscoveredNewDevice(peerId: newDevicePeerID, discoveryInfo: info) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Swift.Error) {
        Logger.error("Failed to start browsing for peers \(error)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerId: MCPeerID) {}
}

extension DeviceTransferService: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerId: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Logger.info("Accepting invitation from old device \(peerId)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Swift.Error) {
        Logger.error("Failed to start advertising for peers \(error)")
    }
}

extension DeviceTransferService: MCSessionDelegate {
    func session(_ session: MCSession, peer peerId: MCPeerID, didChange state: MCSessionState) {
        Logger.debug("Connection to \(peerId) did change: \(state.rawValue)")

        switch transferState {
        case .outgoing(let newDevicePeerId, _, _, let transferredFiles, let progress):
            // We only care about state changes for the device we're sending to.
            guard peerId == newDevicePeerId else { return }

            Logger.info("Connection to new device did change: \(state.rawValue)")

            switch state {
            case .connected:
                notifyObservers { $0.deviceTransferServiceDidStartTransfer(progress: progress) }

                // Only send the files if we haven't yet sent the manifest.
                guard !transferredFiles.contains(DeviceTransferService.manifestIdentifier) else { return }

                do {
                    try sendManifest().done {
                        try self.sendAllFiles()
                    }.catch { error in
                        self.failTransfer(.assertion, "Failed to send manifest to new device \(error)")
                    }
                } catch {
                    failTransfer(.assertion, "Failed to send manifest to new device \(error)")
                }
            case .connecting:
                break
            case .notConnected:
                failTransfer(.assertion, "Lost connection to new device")
            @unknown default:
                failTransfer(.assertion, "Unexpected connection state: \(state.rawValue)")
            }
        case .incoming(let oldDevicePeerId, _, _, _, _):
            // We only care about state changes for the device we're receiving from.
            guard peerId == oldDevicePeerId else { return }

            if state == .notConnected { failTransfer(.assertion, "Lost connection to old device") }
        case .idle:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerId: MCPeerID) {
        switch transferState {
        case .idle:
            break
        case .outgoing(let newDevicePeerId, _, _, _, _):
            guard peerId == newDevicePeerId else {
                return owsFailDebug("Ignoring data from unexpected peer \(peerId)")
            }

            guard data == DeviceTransferService.doneMessage else {
                return failTransfer(.assertion, "Received unexpected data")
            }

            // Notify the UI that the transfer completed successfully.
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: nil) }

            stopTransfer()

            // When the old device receives the done message from the new device,
            // it can be confident that the transfer has completed successfully and
            // clear out all data from this device. This will crash the app.
            if !DebugFlags.deviceTransferPreserveOldDevice {
                SignalApp.resetAppData()
            }

        case .incoming(let oldDevicePeerId, _, let receivedFileIds, let skippedFileIds, _):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring data from unexpected peer \(peerId)")
            }

            guard data == DeviceTransferService.doneMessage else {
                return failTransfer(.assertion, "Received unexpected data")
            }

            stopThroughputCalculation()

            // When the new device receives the done message from the old device,
            // it indicates that the old device thinks we should have received
            // everything at this point.

            guard verifyTransferCompletedSuccessfully(
                receivedFileIds: receivedFileIds,
                skippedFileIds: skippedFileIds
            ) else {
                return failTransfer(.assertion, "transfer is missing data")
            }

            // Record that we have a pending restore, so even if the app exits
            // we can still know to restore the data that was transferred.
            let startPhase = RestorationPhase.start
            Logger.info("Setting restoration phase to: \(startPhase)")
            rawRestorationPhase = startPhase.rawValue

            // Try and notify the old device that we agree, everything is done.
            // At this point, we consider the transfer complete regardless of
            // whether or not this message is received by the old device. If the
            // old device misses this message (because the app crashes, etc.) it
            // will continue acting as if it is "unregistered", but it won't delete
            // all data because it doesn't know for sure if the data was safely
            // received by the new device.
            do {
                try sendDoneMessage(to: oldDevicePeerId)
            } catch {
                owsFailDebug("Failed to send done message to old device \(error)")
            }

            // Notify the UI that the transfer completed successfully.
            notifyObservers { $0.deviceTransferServiceDidEndTransfer(error: nil) }

            // Try and restore the received data. If for some reason the app exits
            // or crashes at this point, we will retry the restore when the app next
            // launches.
            do {
                try restoreTransferredData()
            } catch {
                owsFail("Restore failed. Will try again on next launch. Error: \(error)")
            }

            firstly(on: DispatchQueue.main) { () -> Guarantee<Void> in
                // A successful restoration means we've updated our database path.
                // Extensions will learn of this through NSUserDefaults KVO and exit ASAP
                self.databaseStorage.reloadAsMainDatabase()
            }.then(on: DispatchQueue.main) { () -> Guarantee<Void> in
                self.finalizeRestorationIfNecessary()
            }.done(on: DispatchQueue.main) {
                // After transfer our push token has changed, update it.
                SyncPushTokensJob.run(mode: .forceUpload)
                SignalApp.shared().showConversationSplitView()
            }

            stopTransfer()
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerId: MCPeerID) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        with fileProgress: Progress
    ) {
        switch transferState {
        case .idle:
            guard resourceName == DeviceTransferService.manifestIdentifier else {
                return Logger.info("Ignoring unexpected incoming file \(resourceName)")
            }
        case .outgoing:
            owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
        case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let skippedFileIds, let progress):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring file from unexpected peer \(peerId)")
            }

            let nameComponents = resourceName.components(separatedBy: " ")

            guard let fileIdentifier = nameComponents.first, nameComponents.count == 2 else {
                return owsFailDebug("Received incorrectly formatted resourceName: \(resourceName)")
            }

            guard !receivedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
            }

            guard !skippedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring previously skipped file: \(fileIdentifier)")
            }

            guard let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransferService.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransferService.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }() else {
                return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
            }

            Logger.info("Receiving file: \(file.identifier), estimatedSize: \(file.estimatedSize)")
            progress.addChild(fileProgress, withPendingUnitCount: Int64(file.estimatedSize))
        }
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerId: MCPeerID,
        at localURL: URL?,
        withError error: Swift.Error?
    ) {
        switch transferState {
        case .idle:
            guard resourceName == DeviceTransferService.manifestIdentifier else {
                return Logger.info("Ignoring unexpected incoming file \(resourceName)")
            }

            if let error = error {
                owsFailDebug("Failed to receive manifest \(error)")
            } else if let localURL = localURL {
                handleReceivedManifest(at: localURL, fromPeer: peerId)
            } else {
                owsFailDebug("Unexpectedly completed transfer of resource with no URL or error")
            }
        case .outgoing:
            owsFailDebug("Unexpectedly received a file on old device \(resourceName)")
        case .incoming(let oldDevicePeerId, let manifest, let receivedFileIds, let skippedFileIds, _):
            guard peerId == oldDevicePeerId else {
                return owsFailDebug("Ignoring file from unexpected peer \(peerId)")
            }

            let nameComponents = resourceName.components(separatedBy: " ")

            guard let fileIdentifier = nameComponents.first, let fileHash = nameComponents.last, nameComponents.count == 2 else {
                return owsFailDebug("Received incorrectly formatted resourceName: \(resourceName)")
            }

            guard !receivedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring duplicate file: \(fileIdentifier)")
            }

            guard !skippedFileIds.contains(fileIdentifier) else {
                return Logger.info("Ignoring previously skipped file: \(fileIdentifier)")
            }

            guard let file: DeviceTransferProtoFile = {
                switch fileIdentifier {
                case DeviceTransferService.databaseIdentifier:
                    return manifest.database?.database
                case DeviceTransferService.databaseWALIdentifier:
                    return manifest.database?.wal
                default:
                    return manifest.files.first(where: { $0.identifier == fileIdentifier })
                }
            }() else {
                return owsFailDebug("Received unexpected file on new device: \(fileIdentifier)")
            }

            if let error = error {
                failTransfer(.assertion, "Failed to receive file \(file.identifier) \(error)")
            } else if let localURL = localURL {
                OWSFileSystem.ensureDirectoryExists(DeviceTransferService.pendingTransferFilesDirectory.path)

                guard let computedHash = try? Cryptography.computeSHA256DigestOfFile(at: localURL) else {
                    return failTransfer(.assertion, "Failed to compute hash for \(file.identifier)")
                }

                guard computedHash.hexadecimalString == fileHash else {
                    return failTransfer(.assertion, "Received file with incorrect hash \(file.identifier)")
                }

                guard computedHash != DeviceTransferService.missingFileHash else {
                    Logger.warn("Received notification of missing file: \(file.identifier), skipping.")
                    transferState = transferState.appendingSkippedFileId(file.identifier)
                    return
                }

                guard OWSFileSystem.moveFilePath(
                    localURL.path,
                    toFilePath: URL(
                        fileURLWithPath: file.identifier,
                        relativeTo: DeviceTransferService.pendingTransferFilesDirectory
                    ).path
                ) else {
                    return failTransfer(.assertion, "Failed to move file into place \(file.identifier)")
                }

                Logger.info("Received file: \(file.identifier)")
                transferState = transferState.appendingFileId(file.identifier)
            } else {
                owsFailDebug("Unexpectedly completed transfer of resource with no URL or error")
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceiveCertificate certificates: [Any]?,
        fromPeer peerId: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        var certificateIsTrusted = false

        defer {
            certificateHandler(certificateIsTrusted)
            if !certificateIsTrusted {
                self.failTransfer(.certificateMismatch, "the received certificate did not match the expected certificate")
            }
        }

        guard case .outgoing(let newDevicePeerId, let expectedCertificateHash, _, _, _) = transferState else {
            // Accept all connections if we're not doing an outgoing transfer AND we aren't yet registered.
            // Registered devices can only ever perform outgoing transfers.
            certificateIsTrusted = !tsAccountManager.isRegistered
            return
        }

        // Reject any connections from unexpected devices.
        guard peerId == newDevicePeerId else { return }

        // Verify the received certificate matches the expected certificate.
        guard let certificate = certificates?.first else {
            return owsFailDebug("new connection did not provide any certificate")
        }

        let certificateData = SecCertificateCopyData(certificate as! SecCertificate) as Data

        // Reject any connections where we can't compute the certificate hash
        guard let certificateHash = Cryptography.computeSHA256Digest(certificateData) else {
            return owsFailDebug("failed to calculate certificate hash")
        }

        // Reject any connections where the certificate doesn't match the expected certificate
        guard expectedCertificateHash.ows_constantTimeIsEqual(to: certificateHash) else {
            return owsFailDebug("connection from known peer \(peerId) using unexpected certificate")
        }

        Logger.info("Successfully verified new device certificate \(peerId)")

        certificateIsTrusted = true
    }
}
