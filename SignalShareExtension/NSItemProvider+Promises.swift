//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension NSItemProvider {
    @MainActor
    func loadUrl(forTypeIdentifier typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.ows_loadUrl(forTypeIdentifier: typeIdentifier, options: nil) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let url = url else {
                    continuation.resume(throwing: OWSAssertionError("url was unexpectedly nil"))
                    return
                }

                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    func loadData(forTypeIdentifier typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.ows_loadData(forTypeIdentifier: typeIdentifier, options: nil) { data, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: OWSAssertionError("data was unexpectedly nil"))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    @MainActor
    func loadText(forTypeIdentifier typeIdentifier: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.ows_loadText(forTypeIdentifier: typeIdentifier, options: nil) { text, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let text = text else {
                    continuation.resume(throwing: OWSAssertionError("text was unexpectedly nil"))
                    return
                }

                continuation.resume(returning: text)
            }
        }
    }

    @MainActor
    func loadImage(forTypeIdentifier typeIdentifier: String) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            self.ows_loadImage(forTypeIdentifier: typeIdentifier, options: nil) { image, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image = image else {
                    continuation.resume(throwing: OWSAssertionError("image was unexpectedly nil"))
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}
