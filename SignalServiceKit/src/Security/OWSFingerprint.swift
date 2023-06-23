//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CommonCrypto

public class OWSFingerprint {

    public let myStableAddress: SignalServiceAddress
    public let myIdentityKey: Data
    public let theirStableAddress: SignalServiceAddress
    public let theirIdentityKey: Data

    private let hashIterations: UInt32
    private let myFingerprintData: Data
    private let theirFingerprintData: Data
    private let theirName: String

    /**
     * Formats numeric fingerprint, 3 lines in groups of 5 digits.
     */
    public var displayableText: String {
        return generateDisplayableText()
    }

    public var image: UIImage? {
        return generateImage()
    }

    public init(
        myStableAddress: SignalServiceAddress,
        myIdentityKey: Data,
        theirStableAddress: SignalServiceAddress,
        theirIdentityKey: Data,
        theirName: String,
        hashIterations: UInt32 = Constants.defaultHashIterations
    ) {
        self.myStableAddress = myStableAddress
        let myIdentityKey = myIdentityKey.prependKeyType()
        self.myIdentityKey = myIdentityKey
        self.theirStableAddress = theirStableAddress
        let theirIdentityKey = theirIdentityKey.prependKeyType()
        self.theirIdentityKey = theirIdentityKey
        self.hashIterations = hashIterations
        self.theirName = theirName

        self.myFingerprintData = Self.dataForStableAddress(
            Self.stableData(for: myStableAddress),
            publicKey: myIdentityKey,
            hashIterations: hashIterations
        )
        self.theirFingerprintData = Self.dataForStableAddress(
            Self.stableData(for: theirStableAddress),
            publicKey: theirIdentityKey,
            hashIterations: hashIterations
        )
    }

    public enum MatchResult {
        case match
        case noMatch(localizedErrorDescription: String)
    }

    public func matchesLogicalFingerprintsData(_ otherData: Data) -> MatchResult {
        owsAssertDebug(otherData.isEmpty.negated)

        let logicalFingerprints: FingerprintProtoLogicalFingerprints
        do {
            logicalFingerprints = try FingerprintProtoLogicalFingerprints.init(serializedData: otherData)
        } catch {
            owsFailDebug("fingerprint failure: \(error)")
            let description = OWSLocalizedString("PRIVACY_VERIFICATION_FAILURE_INVALID_QRCODE", comment: "alert body")
            return .noMatch(localizedErrorDescription: description)
        }

        if logicalFingerprints.version < self.scannableFingerprintVersion {
            Logger.warn("Verification failed. They're running an old version.")
            let description = OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_WITH_OLD_REMOTE_VERSION", comment: "alert body")
            return .noMatch(localizedErrorDescription: description)
        }

        if logicalFingerprints.version > self.scannableFingerprintVersion {
            Logger.warn("Verification failed. We're running an old version.")
            let description = OWSLocalizedString("PRIVACY_VERIFICATION_FAILED_WITH_OLD_LOCAL_VERSION", comment: "alert body")
            return .noMatch(localizedErrorDescription: description)
        }

        // Their local is *our* remote.
        let localFingerprint = logicalFingerprints.remoteFingerprint
        let remoteFingerprint = logicalFingerprints.localFingerprint
        if remoteFingerprint.identityData != Self.scannableData(from: self.theirFingerprintData) {
            Logger.warn("Verification failed. We have the wrong fingerprint for them")
            let descriptionFormat = OWSLocalizedString(
                "PRIVACY_VERIFICATION_FAILED_I_HAVE_WRONG_KEY_FOR_THEM",
                comment: "Alert body when verifying with {{contact name}}"
            )
            let description = String(format: descriptionFormat, self.theirName)
            return .noMatch(localizedErrorDescription: description)
        }
        if localFingerprint.identityData != Self.scannableData(from: self.myFingerprintData) {
            Logger.warn("Verification failed. They have the wrong fingerprint for us")
            let descriptionFormat = OWSLocalizedString(
                "PRIVACY_VERIFICATION_FAILED_THEY_HAVE_WRONG_KEY_FOR_ME",
                comment: "Alert body when verifying with {{contact name}}"
            )
            let description = String(format: descriptionFormat, self.theirName)
            return .noMatch(localizedErrorDescription: description)
        }

        Logger.warn("Verification Succeeded.")
        return .match
    }

    // MARK: - Text Representation

    private var textRepresentation: String {
        let myDisplayString = Self.stringForFingerprintData(myFingerprintData)
        let theirDisplayString = Self.stringForFingerprintData(theirFingerprintData)

        if theirDisplayString.compare(myDisplayString) == .orderedAscending {
            return theirDisplayString + myDisplayString
        } else {
            return myDisplayString + theirDisplayString
        }
    }

    private func generateDisplayableText() -> String {
        let input = self.textRepresentation

        var lines = [String]()

        let lineLength = (input as NSString).length / 3
        for i in 0..<3 {
            let line = input.substring(withRange: NSRange(location: i * lineLength, length: lineLength))
            var chunks = [String]()
            for j in 0..<((line as NSString).length / 5) {
                let nextChunk = line.substring(withRange: NSRange(location: j * 5, length: 5))
                chunks.append(nextChunk)
            }
            lines.append(String(chunks.joined(separator: " ")))
        }
        return String(lines.joined(separator: "\n"))
    }

    // MARK: - Image Representation

    private func generateImage() -> UIImage? {
        let remoteFingerprintBuilder = FingerprintProtoLogicalFingerprint.builder(
            identityData: Self.scannableData(from: self.theirFingerprintData)
        )
        let localFingerprintBuilder = FingerprintProtoLogicalFingerprint.builder(
            identityData: Self.scannableData(from: self.myFingerprintData)
        )
        let remoteFingerprint: FingerprintProtoLogicalFingerprint
        let localFingerprint: FingerprintProtoLogicalFingerprint
        do {
            remoteFingerprint = try remoteFingerprintBuilder.build()
            localFingerprint = try localFingerprintBuilder.build()
        } catch {
            owsFailDebug("could not build proto \(error)")
            return nil
        }

        let logicalFingerprintsBuilder = FingerprintProtoLogicalFingerprints.builder(
            version: self.scannableFingerprintVersion,
            localFingerprint: localFingerprint,
            remoteFingerprint: remoteFingerprint
        )

        let fingerprintData: Data
        do {
            // Build ByteMode QR (Latin-1 encodable data)
            fingerprintData = try logicalFingerprintsBuilder.buildSerializedData()
        } catch {
            owsFailDebug("could not serialize proto \(error)")
            return nil
        }

        Logger.debug("Building fingerprint")

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            Logger.error("Failed to create QR code filter")
            return nil
        }
        filter.setDefaults()
        filter.setValue(fingerprintData, forKey: "inputMessage")
        guard let ciImage = filter.outputImage else {
            Logger.error("Failed to create QR image from fingerprint")
            return nil
        }

        // UIImages backed by a CIImage won't render without antialiasing, so we convert the backign image to a CGImage,
        // which can be scaled crisply.
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let qrImage = UIImage(cgImage: cgImage)
        return qrImage
    }

    // MARK: - Private helpers

    private static func stableData(for address: SignalServiceAddress) -> Data {
        // For now, leave safety number based on phone number unless the feature flag is enabled.
        // This prevents mismatch from occurring against old apps until we formally roll out the feature.
        if let uuid = address.uuid, RemoteConfig.uuidSafetyNumbers {
            // TODO UUID: Right now, uuid is nullable, but safety numbers require us to always have
            // the UUID for a user. This will need to be updated once we change this field to nonnull.
            return uuid.data
        } else if
            let phoneNumber = address.phoneNumber,
            phoneNumber.isEmpty.negated,
            let data = phoneNumber.data(using: .utf8)
        {
            return data
        } else {
            owsFail("Invalid address")
        }
    }

    /**
     * An identifier for a mutable public key, belonging to an immutable identifier (stableId).
     *
     * This method is intended to be somewhat expensive to produce in order to be brute force adverse.
     *
     * @param stableAddressData
     *      Immutable global identifier e.g. Signal Identifier, an e164 formatted phone number encoded as UTF-8 data
     * @param publicKey
     *      The current public key for <stableAddress>
     * @return
     *      All-number textual representation
     */
    private static func dataForStableAddress(_ stableAddressData: Data, publicKey: Data, hashIterations: UInt32) -> Data {
        var hash = Constants.hashingVersion.bigEndianData.suffix(2)
        hash.append(publicKey)
        hash.append(stableAddressData)

        var digestData = Data(count: Int(CC_SHA512_DIGEST_LENGTH))

        for _ in 0..<hashIterations {
            hash.append(publicKey)
            if hash.count >= UInt32.max {
                owsFail("Oversize data")
            }

            _ = digestData.withUnsafeMutableBytes { digestBytes in
                hash.withUnsafeBytes { hashBytes in
                    CC_SHA512(hashBytes, CC_LONG(hash.count), digestBytes)
                }
            }
            hash = digestData
        }

        return hash
    }

    private static func stringForFingerprintData(_ data: Data) -> String {
        return String(
            format: "%@%@%@%@%@%@",
            encodedChunkFromData(data, offset: 0),
            encodedChunkFromData(data, offset: 5),
            encodedChunkFromData(data, offset: 10),
            encodedChunkFromData(data, offset: 15),
            encodedChunkFromData(data, offset: 20),
            encodedChunkFromData(data, offset: 25)
        )
    }

    private static func encodedChunkFromData(_ data: Data, offset: Int) -> String {
        let fiveByteChunk = Data(data.dropFirst(offset).prefix(5))
        let chunk: Int = intFrom5Bytes(fiveByteChunk) % 100000
        return String(format: "%05d", chunk)
    }

    private static func intFrom5Bytes(_ data: Data) -> Int {
        return Int(data[0]) << 32
            + Int(data[1]) << 24
            + Int(data[2]) << 16
            + Int(data[3]) << 8
            + Int(data[4])
    }

    private static func scannableData(from data: Data) -> Data {
        return data.prefix(32)
    }

    private var scannableFingerprintVersion: UInt32 {
        if !RemoteConfig.uuidSafetyNumbers {
            return Constants.preUUIDScannableFormatVersion
        }
        return Constants.scannableFormatVersion
    }

    public enum Constants {
        static let hashingVersion: UInt32 = 0
        static let preUUIDScannableFormatVersion: UInt32 = 1
        static let scannableFormatVersion: UInt32 = 2
        public static let defaultHashIterations: UInt32 = 5200
    }
}
