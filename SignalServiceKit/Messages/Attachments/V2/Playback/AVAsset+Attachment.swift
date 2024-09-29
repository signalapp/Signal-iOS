//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation

extension AVAsset {

    public static func from(
        _ attachment: AttachmentStream
    ) throws -> AVAsset {
        return try .fromEncryptedFile(
            at: attachment.fileURL,
            encryptionKey: attachment.attachment.encryptionKey,
            plaintextLength: attachment.info.unencryptedByteCount,
            mimeType: attachment.mimeType
        )
    }

    public static func fromEncryptedFile(
        at fileURL: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> AVAsset {
        func createAsset(mimeTypeOverride: String? = nil) throws -> AVAsset {
            return try AVAsset._fromEncryptedFile(
                at: fileURL,
                encryptionKey: encryptionKey,
                plaintextLength: plaintextLength,
                mimeType: mimeTypeOverride ?? mimeType
            )
        }

        guard let mimeTypeOverride = MimeTypeUtil.alternativeAudioMimeType(mimeType: mimeType) else {
            // If we have no override just return the first thing we get.
            return try createAsset()
        }

        if let asset = try? createAsset(), asset.isReadable {
            return asset
        }

        // Give it a second try with the overriden mimeType
        return try createAsset(mimeTypeOverride: mimeTypeOverride)
    }

    private static let videoDecryptionQueue = DispatchQueue(label: "Decrypt AVAsset")

    private static func _fromEncryptedFile(
        at fileURL: URL,
        encryptionKey: Data,
        plaintextLength: UInt32,
        mimeType: String
    ) throws -> AVAsset {
        let fileHandle = try Cryptography.encryptedAttachmentFileHandle(
            at: fileURL,
            plaintextLength: plaintextLength,
            encryptionKey: encryptionKey
        )

        guard let utiType = MimeTypeUtil.utiTypeForMimeType(mimeType) else {
            throw OWSAssertionError("Invalid mime type")
        }

        let resourceLoader = EncryptedFileResourceLoader(
            utiType: utiType,
            fileHandle: fileHandle
        )

        // AVAsset cares about the file extension. It shouldn't, but it does.
        // If we can map the mime type to a file extension, do so for the
        // url we give the AVAsset so it reads things correctly.
        let fileURLWithFakeExtension: URL
        if
            let pathExtension =
                // Prioritize audio extensions; note these mappings differ from the
                // generic "fileExtensionForMimeType" because reasons.
                MimeTypeUtil.getSupportedExtensionFromAudioMimeType(mimeType)
                ?? MimeTypeUtil.fileExtensionForMimeType(mimeType) {
            fileURLWithFakeExtension = fileURL.appendingPathExtension(pathExtension)
        } else {
            fileURLWithFakeExtension = fileURL
        }
        guard let redirectURL = fileURLWithFakeExtension.convertToAVAssetRedirectURL(prefix: Self.customScheme) else {
            throw OWSAssertionError("Failed to prefix URL!")
        }
        let asset = AVURLAsset(url: redirectURL)
        asset.resourceLoader.preloadsEligibleContentKeys = true
        asset.resourceLoader.setDelegate(resourceLoader, queue: Self.videoDecryptionQueue)

        // The resource loader delegate is held via weak reference, but:
        // 1. it doesn't hold a reference to the AVAsset
        // 2. we dont want to impose on the caller to hold a strong reference to it
        // so we create a strong reference from the asset.
        objc_setAssociatedObject(
            asset,
            &Self.resourceLoaderKey,
            resourceLoader,
            objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN
        )

        return asset
    }

    private static var resourceLoaderKey: UInt8 = 0

    /// In order to get AVAsset to use the custom resource loader, we have to give it a URL scheme it doesn't
    /// understand how to load by itself. To do that, we prefix the url scheme with this string before handing
    /// it to AVAsset, and then strip the prefix in our own code.
    private static let customScheme = "signal"

    private class EncryptedFileResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

        private let utiType: String
        private let fileHandle: EncryptedFileHandle

        init(utiType: String, fileHandle: EncryptedFileHandle) {
            self.utiType = utiType
            self.fileHandle = fileHandle
        }

        func resourceLoader(
            _ resourceLoader: AVAssetResourceLoader,
            shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
        ) -> Bool {
            if let _ = loadingRequest.contentInformationRequest {
                return handleContentInfoRequest(for: loadingRequest)
            } else if let _ = loadingRequest.dataRequest {
                return handleDataRequest(for: loadingRequest)
            } else {
                return false
            }
        }

        private func handleContentInfoRequest(for loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard let infoRequest = loadingRequest.contentInformationRequest else { return false }

            infoRequest.contentType = utiType
            infoRequest.contentLength = Int64(exactly: fileHandle.plaintextLength) ?? 0
            if #available(iOSApplicationExtension 16.0, *) {
                infoRequest.isEntireLengthAvailableOnDemand = true
            }
            infoRequest.isByteRangeAccessSupported = true
            loadingRequest.finishLoading()
            return true
        }

        private static let chunkSize: UInt32 = 4096

        private func handleDataRequest(for loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard
                let dataRequest = loadingRequest.dataRequest
            else {
                return false
            }

            let requestedOffset = UInt32(dataRequest.requestedOffset)
            var requestedLength = UInt32(dataRequest.requestedLength)
            if dataRequest.requestsAllDataToEndOfResource {
                requestedLength = fileHandle.plaintextLength - requestedOffset
            }

            do {
                if requestedOffset != fileHandle.offset() {
                    try fileHandle.seek(toOffset: requestedOffset)
                }
            } catch let error {
                loadingRequest.finishLoading(with: error)
                return true
            }

            var bytesReadSoFar: UInt32 = 0
            do {
                while bytesReadSoFar < requestedLength {
                    let lengthToRead = min(Self.chunkSize, requestedLength - bytesReadSoFar)
                    let data = try fileHandle.read(upToCount: lengthToRead)
                    bytesReadSoFar += UInt32(data.byteLength)
                    dataRequest.respond(with: data)
                }
            } catch let error {
                loadingRequest.finishLoading(with: error)
                return true
            }

            loadingRequest.finishLoading()

            return true
        }
    }
}

private extension URL {
    func convertToAVAssetRedirectURL(prefix: String) -> URL? {
        guard
            var components = URLComponents(
                url: self,
                resolvingAgainstBaseURL: false
            ),
            let scheme = components.scheme
        else {
            return nil
        }
        components.scheme = prefix + scheme
        return components.url
    }
}
