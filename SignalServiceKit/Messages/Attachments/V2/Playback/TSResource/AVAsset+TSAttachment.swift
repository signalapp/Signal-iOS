//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AVFoundation
import Foundation

extension AVAsset {

    public static func from(
        _ attachment: TSAttachmentStream
    ) throws -> AVAsset {
        guard let filePath = attachment.originalFilePath else {
            throw OWSAssertionError("Missing local file")
        }
        let fileURL = URL(fileURLWithPath: filePath)

        func createAsset(mimeTypeOverride: String? = nil) throws -> AVAsset {
            return try AVAsset._fromDecryptedFile(
                at: fileURL,
                mimeType: mimeTypeOverride ?? attachment.mimeType
            )
        }

        guard let mimeTypeOverride = MimeTypeUtil.alternativeAudioMimeType(mimeType: attachment.mimeType) else {
            // If we have no override just return the first thing we get.
            return try createAsset()
        }

        if let asset = try? createAsset(), asset.isReadable {
            return asset
        }

        // Give it a second try with the overriden mimeType
        return try createAsset(mimeTypeOverride: mimeTypeOverride)
    }

    private static func _fromDecryptedFile(
        at fileURL: URL,
        mimeType: String
    ) throws -> AVAsset {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)

        let fileLength = OWSFileSystem.fileSize(of: fileURL)?.int64Value ?? 0

        guard let utiType = MimeTypeUtil.utiTypeForMimeType(mimeType) else {
            throw OWSAssertionError("Invalid mime type")
        }

        let resourceLoader = DecryptedFileResourceLoader(
            utiType: utiType,
            fileHandle: fileHandle,
            fileLength: fileLength
        )

        guard let redirectURL = fileURL.convertToAVAssetRedirectURL(prefix: Self.customScheme) else {
            throw OWSAssertionError("Failed to prefix URL!")
        }
        let asset = AVURLAsset(url: redirectURL)
        asset.resourceLoader.setDelegate(resourceLoader, queue: .global())

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
    private static let customScheme = "signalTSAttachment"

    private class DecryptedFileResourceLoader: NSObject, AVAssetResourceLoaderDelegate {

        private let utiType: String
        private let fileHandle: FileHandle
        private let fileLength: Int64

        init(utiType: String, fileHandle: FileHandle, fileLength: Int64) {
            self.utiType = utiType
            self.fileHandle = fileHandle
            self.fileLength = fileLength
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
            infoRequest.contentLength = fileLength
            infoRequest.isByteRangeAccessSupported = true
            loadingRequest.finishLoading()
            return true
        }

        private func handleDataRequest(for loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
            guard
                let dataRequest = loadingRequest.dataRequest
            else {
                return false
            }

            let requestedOffset = dataRequest.requestedOffset
            var requestedLength = dataRequest.requestedLength
            if dataRequest.requestsAllDataToEndOfResource {
                requestedLength = Int(exactly: fileLength - requestedOffset) ?? 0
            }

            let data: Data
            do {
                let currentOffset = try fileHandle.offset()
                if requestedOffset != currentOffset {
                    try fileHandle.seek(toOffset: UInt64(exactly: requestedOffset) ?? 0)
                }
                data = try fileHandle.read(upToCount: requestedLength) ?? Data()
            } catch let error {
                loadingRequest.finishLoading(with: error)
                return true
            }

            dataRequest.respond(with: data)
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
