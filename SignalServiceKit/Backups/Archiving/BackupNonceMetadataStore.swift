//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// Container for types wrapping raw data that relates to backup future secrecy nonces.
public enum BackupNonce {

    /// An imprecise upper bound on the byte length of the MetadataHeader we prepend to
    /// the backup file, plus the length of the file signature and varint length we put before it.
    /// Before we download the full backup file, we fetch the first N bytes so we can
    /// pull out the header to talk to SVR🐝 before proceeding. This is how many bytes
    /// we initially fetch. If this fails, we fetch more. It is therefore most performant
    /// if this value is a reasonably tight overestimate of the length of the header, even if that
    /// length is variable.
    static let metadataHeaderByteLengthUpperBound: UInt16 =
        UInt16(magicFileSignature.count)
        + varintLengthUpperBound
        + metadataHeaderLengthUpperBound

    /// SBACKUP\x01
    static let magicFileSignature = Data([83, 66, 65, 67, 75, 85, 80, 01])
    static let varintLengthUpperBound: UInt16 = 5
    static let metadataHeaderLengthUpperBound: UInt16 = 200

    /// The header we prepend in plaintext to every backup that clients treat as a black box
    /// but contains the necessary data to derive the encryption key for the rest of the backup
    /// file, when combined with the AEP and the nonce data recovered from SVRB.
    ///
    /// This data can be (and is) exposed to the server, as it is in plaintext at the front
    /// of the backup file we upload to CDN.
    public struct MetadataHeader: Codable {
        public let data: Data

        public init(data: Data) {
            self.data = data
        }
    }

    /// Metadata used to generate the nonce and header for the _next_ backup
    /// we create.
    /// Backup N can be decrypted using Nonce N or Nonce {N+1}. This metadata
    /// deterministically produces Nonce {N+1}. We persist it when we create
    /// Backup N and read it back later when we create Backup {N+1} so that
    /// when we upload the next nonce to SVRB is it Nonce {N+1} and can be used
    /// to decrypt the prior backup, in case the next backup's upload fails.
    public struct NextSecretMetadata: Codable {
        public let data: Data

        public init(data: Data) {
            self.data = data
        }
    }
}

extension Svr🐝.StoreBackupResponse {

    var headerMetadata: BackupNonce.MetadataHeader {
        return BackupNonce.MetadataHeader(data: self.metadata)
    }

    var nextSecretMetadata: BackupNonce.NextSecretMetadata {
        return BackupNonce.NextSecretMetadata(data: self.nextBackupSecretData)
    }
}

extension Svr🐝.RestoreBackupResponse {

    var nextSecretMetadata: BackupNonce.NextSecretMetadata {
        return BackupNonce.NextSecretMetadata(data: self.nextBackupSecretData)
    }
}

extension BackupNonce.MetadataHeader {

    public enum ParsingError: Error {
        case unrecognizedFileSignature
        case dataMissingOrEmpty
        case headerTooLarge
        // Includes min byte length needed
        case moreDataNeeded(UInt16)
    }

    /// Parse a MetadataHeader from the first N bytes of a backup file.
    /// If the provided bytes do not cover the complete header, throws a ``ParsingError/moreDataNeeded(_:)`` error
    /// with the minimum necessary bytes to try parsing again.
    public static func from(prefixBytes: Data?) throws(ParsingError) -> BackupNonce.MetadataHeader {
        guard let rawData = prefixBytes?.nilIfEmpty else {
            owsFailDebug("Missing prefix data")
            throw .dataMissingOrEmpty
        }

        // Check the file signature
        let fileSignatureLength = BackupNonce.magicFileSignature.count
        guard rawData.count > fileSignatureLength else {
            throw .moreDataNeeded(BackupNonce.metadataHeaderByteLengthUpperBound)
        }
        guard rawData.prefix(fileSignatureLength) == BackupNonce.magicFileSignature else {
            throw .unrecognizedFileSignature
        }

        // Read the varint length of the header metadata.
        let (headerLength, varintLength) = ChunkedInputStreamTransform.decodeVariableLengthInteger(
            buffer: rawData,
            start: fileSignatureLength
        )
        guard
            headerLength > 0,
            varintLength >= 0,
            let varintLength = UInt64(exactly: varintLength)
        else {
            throw .moreDataNeeded(BackupNonce.metadataHeaderByteLengthUpperBound)
        }
        guard let minLength = UInt16(exactly: UInt64(fileSignatureLength) + headerLength + varintLength) else {
            // We enforce via swift compiler that the header fits in 2^16 bytes, which is
            // way overkill and should always be enough. This should never happen.
            owsFailDebug("Header larger than 2^16 bytes!")
            throw .headerTooLarge
        }
        if minLength > rawData.count {
            throw .moreDataNeeded(minLength)
        }
        let rawHeader = rawData
            .suffix(from: fileSignatureLength + Int(varintLength))
            .prefix(Int(headerLength))
        return BackupNonce.MetadataHeader(data: rawHeader)
    }

    /// Produce the full serialized prefix we should add to the backup file, including the file signature,
    /// varint header length, and header itself.
    public func serializedBackupFilePrefix() -> Data {
        let headerData = self.data
        let varint = ChunkedOutputStreamTransform.writeVariableLengthUInt32(UInt32(headerData.count))
        return BackupNonce.magicFileSignature + varint + headerData
    }
}

public class BackupNonceMetadataStore {

    private let kvStore = KeyValueStore(collection: "BackupNonceMetadataStore")

    public init() {}

    public func getLastForwardSecrecyToken(tx: DBReadTransaction) throws -> BackupForwardSecrecyToken? {
        return try kvStore.getData(Keys.lastForwardSecrecyToken, transaction: tx).map(BackupForwardSecrecyToken.init(contents:))
    }

    /// We should only call this method in one place only:
    /// Immediately after successfuly uploading a backup file to CDN using the MetadataHeader from the same
    /// StoreBackupResponse as this BackupForwardSecrecyToken.
    public func setLastForwardSecrecyToken(_ token: BackupForwardSecrecyToken, tx: DBWriteTransaction) {
        kvStore.setData(token.serialize(), key: Keys.lastForwardSecrecyToken, transaction: tx)
    }

    public func getNextSecretMetadata(tx: DBReadTransaction) -> BackupNonce.NextSecretMetadata? {
        return kvStore.getData(Keys.nextSecretMetadata, transaction: tx).map(BackupNonce.NextSecretMetadata.init(data:))
    }

    /// We should only call this method in two places:
    /// 1. Immediately after successfuly uploading a backup file to CDN using the MetadataHeader from the same
    ///  StoreBackupResponse as this NextSecretMetadata.
    /// 2. As an initialization step the very first time we create a backup, since there was no prior backup to pull
    ///  the "next" metadata from.
    /// 3. After restoring a backup on a new device, with the nextSecretMetadata we got from the SVR🐝 response,
    /// to continue the chain on this device when it makes a backup for the first time.
    public func setNextSecretMetadata(_ metadata: BackupNonce.NextSecretMetadata, tx: DBWriteTransaction) {
        kvStore.setData(metadata.data, key: Keys.nextSecretMetadata, transaction: tx)
    }

    private enum Keys {
        static let lastForwardSecrecyToken = "lastForwardSecrecyToken"
        static let nextSecretMetadata = "nextSecretMetadata"
    }
}
