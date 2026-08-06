//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import SignalServiceKit

///
/// The following service is used to facilitate users in transferring their account from
/// an old device (OD) to a new device (ND) using MultipeerConnectivity. The general steps
/// of the process follow the following flow:
///
/// 1) As you begin setting up a new device (ND), you are asked if you want to transfer data
///    from an old device (OD). This happens *after* the SMS code and reg lock pin are provided,
///    but (importantly) before the service replaces your old account. Accounts are identified
///    by the service as being eligible for transfer by setting the "transfer" capability.
/// 2) In order to notify potential ODs on the network, the ND will begin advertising a
///    “transfer service” using Bonjour. Nearby ODs will be readily browsing for this service,
///     but not establishing any connections until the user takes action. The ND will actively
///     attempt to connect to any other “transfer service” it finds. MC will under-the-hood
///     determine whether it’s best to use peer-to-peer Wi-Fi, Bluetooth, or infrastructure Wi-Fi
/// 3) In order to prepare for a session from the OD, the ND will generate an RSA 2048 private
///    key and self-signed public certificate (used for DTLS). It will then present a QR code
///    that contains:
///      a. The transfer version, so we can eliminate the need for a lot of backwards compatibility
///      b. The MC Peer identifier (an opaque blob of data that represents the ND, that the
///         OD can use to determine what device to connect to)
///      c. A sha256 hash of the public certificate, so we can verify we're connected to
///         the appropriate ND
///      d. A mode flag indicating whether we're expecting to transfer from a primary device
///         or a linked device.
/// 4) On your OD, you will accept the prompt in the Signal app to enter transfer mode.
///    A QR scanner will be presented to you.
/// 5) When the OD scans the QR code presented on the ND, it will:
///      a. Attempt to open an encrypted (DTLS) session with the specified MC session identifier
///      b. Validate the certificate for the connection exactly matches the certificate scanned from the ND
///      c. Start locally behaving as if it is unregistered, without actually unregistering from the
///         service (to prevent two devices registered with the same number)
///      d. Send a manifest to the ND that outlines a list of all the files it should expect, including:
///          i. The SQLCipher DB key
///          ii. The sqlite database file (with no additional encryption beyond SQLCipher)
///          iii. All attachment files stored on the device
///          iv. The user preference dictionary (user defaults)
///      e. Start transferring all the files to the new device
///  6) When all data has been transferred successfully,
///      a. the OD will:
///          i. Flag that it was transferred, it will now remain unregistered regardless of what
///             happens on the ND.
///          ii. Send a "done" message to the ND, to notify that it thinks it's done
///          iii. Wait for a "done" message from the ND – if received, all local data will be deleted.
///      b. the ND will, upon receipt of the "done" message:
///          i. Verify all data that was expected to be received was received
///          ii. Mark itself as pending restore
///          iii. Notify the ND that it is "done" and it's safe to self-destruct
///          iv. Move all the received files into place, set the new database key, etc.
///          v. Hot-swap the new database into place and present the conversation list
enum DeviceTransfer {

    enum Error: Swift.Error {
        case assertion
        case backgroundedDevice
        case certificateMismatch
        case modeMismatch
        case notEnoughSpace
        case unsupportedVersion
        case cancel
    }

    enum Mode: String {
        case linked
        case primary
    }

    enum Message {
        case done
        case backgroundApp

        var data: Data {
            switch self {
            case .done: return Data("Transfer Complete".utf8)
            case .backgroundApp: return Data("App backgrounded".utf8)
            }
        }
    }

    enum Constants {
        static let appSharedDataDirectory = URL(fileURLWithPath: OWSFileSystem.appSharedDataDirectoryPath())
        static let pendingTransferDirectory = URL(fileURLWithPath: "transfer", isDirectory: true, relativeTo: appSharedDataDirectory)
        static let pendingTransferFilesDirectory = URL(fileURLWithPath: "files", isDirectory: true, relativeTo: pendingTransferDirectory)

        static let manifestIdentifier = "manifest"
        static let databaseIdentifier = "database"
        static let databaseWALIdentifier = "database-wal"

        static let missingFileData = Data("Missing File".utf8)
        static let missingFileHash = Data(SHA256.hash(data: missingFileData))

        // This must also be updated in the info.plist
        static let newDeviceServiceIdentifier = "sgnl-new-device"
    }

    enum UrlConstants {
        static let currentTransferVersion = 1

        static let versionKey = "version"
        static let peerIdKey = "peerId"
        static let certificateHashKey = "certificateHash"
        static let transferModeKey = "transferMode"

        static let transferHost = "transfer"
    }

    enum Utils {
        static func readManifestFromTransferDirectory() -> DeviceTransferProtoManifest? {
            let manifestPath = URL(
                fileURLWithPath: DeviceTransfer.Constants.manifestIdentifier,
                relativeTo: DeviceTransfer.Constants.pendingTransferDirectory,
            ).path
            guard OWSFileSystem.fileOrFolderExists(atPath: manifestPath) else { return nil }
            guard let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)) else { return nil }
            return try? DeviceTransferProtoManifest(serializedData: manifestData)
        }

        static func resetTransferDirectory(createNewTransferDirectory: Bool) {
            do {
                try FileManager.default.removeItem(atPath: DeviceTransfer.Constants.pendingTransferDirectory.path)
            } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile, POSIXError.ENOENT {
                // it doesn't exist -- this is fine
            } catch {
                owsFailDebug("Failed to delete existing transfer directory \(error)")
            }
            if createNewTransferDirectory {
                OWSFileSystem.ensureDirectoryExists(DeviceTransfer.Constants.pendingTransferDirectory.path)
            }
        }
    }

    enum SessionMessage {
        case message(DeviceTransfer.Message)
        case startResource(String, UInt64?, Progress?)
        case finishResource(String, URL)
    }

    protocol PeerID: Equatable { }

    @MainActor
    protocol Session {
        func waitForConnection() async throws
        func disconnect(error: Swift.Error?)

        var messages: AsyncThrowingStream<SessionMessage, Swift.Error> { get }

        func send(message: Message) throws
        func sendFile(url: URL, name: String, size: UInt64) async throws
    }

    protocol ConnectionFactory {
        @MainActor
        func buildOutgoingConnection(tsAccountManager: TSAccountManager) -> OutgoingConnection
        @MainActor
        func buildIncomingConnection(tsAccountManager: TSAccountManager) -> IncomingConnection
    }

    @MainActor
    protocol OutgoingConnection {
        func connect(deviceTransferUrl: URL) async throws -> Session
        func stop(error: Swift.Error?)
    }

    @MainActor
    protocol IncomingConnection {
        func start(mode: DeviceTransfer.Mode) throws -> URL
        func waitForConnection() async throws -> Session
        func stop(error: Swift.Error?)
    }

    static let defaultFactory: DeviceTransfer.ConnectionFactory = MPCDeviceTransferConnectionFactory()
}
