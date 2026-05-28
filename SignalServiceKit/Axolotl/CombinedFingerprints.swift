//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import LibSignalClient

public struct CombinedFingerprints {
    public let local: Fingerprint
    public let remote: Fingerprint

    public init(
        local: Fingerprint,
        remote: Fingerprint,
    ) {
        self.local = local
        self.remote = remote
    }

    public enum MatchError: Error {
        case theyHaveOldVersion
        case weHaveOldVersion
        case theyHaveWrongKeyForUs
        case weHaveWrongKeyForThem
    }

    public func checkAgainst(combinedFingerprints: Textsecure_CombinedFingerprints) throws(MatchError) {
        if combinedFingerprints.version < self.scannableFingerprintVersion {
            throw .theyHaveOldVersion
        }

        if combinedFingerprints.version > self.scannableFingerprintVersion {
            throw .weHaveOldVersion
        }

        // Their local is *our* remote.
        let localFingerprint = combinedFingerprints.remoteFingerprint
        let remoteFingerprint = combinedFingerprints.localFingerprint
        if remoteFingerprint.content != self.remote.dataRepresentation() {
            throw .weHaveWrongKeyForThem
        }
        if localFingerprint.content != self.local.dataRepresentation() {
            throw .theyHaveWrongKeyForUs
        }
    }

    // MARK: - Text Representation

    private func stringRepresentation() -> String {
        let localStringRepresentation = self.local.stringRepresentation()
        let remoteStringRepresentation = self.remote.stringRepresentation()

        if remoteStringRepresentation < localStringRepresentation {
            return remoteStringRepresentation + localStringRepresentation
        } else {
            return localStringRepresentation + remoteStringRepresentation
        }
    }

    /// Formats numeric fingerprint, 3 lines in groups of 5 digits.
    public func displayableText() -> String {
        var remainingCharacters = self.stringRepresentation()[...]
        var digitGroups = [Substring]()
        while !remainingCharacters.isEmpty {
            digitGroups.append(remainingCharacters.prefix(5))
            remainingCharacters.removeFirst(5)
        }
        var remainingDigitGroups = digitGroups[...]
        var lineGroups = [ArraySlice<Substring>]()
        while !remainingDigitGroups.isEmpty {
            lineGroups.append(remainingDigitGroups.prefix(4))
            remainingDigitGroups.removeFirst(4)
        }
        return lineGroups.map({ $0.joined(separator: " ") }).joined(separator: "\n")
    }

    // MARK: - Image Representation

    public func image() -> UIImage? {
        var combinedFingerprints = Textsecure_CombinedFingerprints()
        combinedFingerprints.version = self.scannableFingerprintVersion
        combinedFingerprints.localFingerprint.content = self.local.dataRepresentation()
        combinedFingerprints.remoteFingerprint.content = self.remote.dataRepresentation()

        let fingerprintData: Data
        do {
            // Build ByteMode QR (Latin-1 encodable data)
            fingerprintData = try combinedFingerprints.serializedData()
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

    private var scannableFingerprintVersion: UInt32 {
        return Constants.aciScannableFormatVersion
    }

    public enum Constants {
        static let aciScannableFormatVersion: UInt32 = 2
    }
}
