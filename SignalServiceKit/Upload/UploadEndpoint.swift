//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// UploadEndpoint encapsulates the logic required to initiate and/or resume an upload to a particular upload backend.
protocol UploadEndpoint {

    typealias UploadEndpointProgress = ((URLSessionTask, Progress) -> Void)

    /// Map the data in the retrieved upload form to a backend specific upload location.
    ///
    /// - Returns: A `Url` representing the destination for the upload task.
    func fetchResumableUploadLocation() async throws -> URL

    /// Given an existing upload state, check the currently agreed upon uploaded bytes.
    ///
    /// - Parameter state: The current upload state, containing the form, target URL and progress
    /// - Returns: `Upload.ResumeProgress` representing the currently upload progress, as known by the server.
    func getResumableUploadProgress(attempt: Upload.Attempt) async throws -> Upload.ResumeProgress

    /// Upload bytes to the endpoing backend. This may be a fresh upload, or this may be resuming an
    /// upload from `startPoint`
    ///
    /// - Parameters:
    ///   - startPoint: The current byte range to start uploading at.
    ///   - attempt: The current upload attempt, containing the local file metadata, upload endpoint, and target location.
    ///   - progress: Callback called with progress data as reported by the internal upload implementation
    func performUpload(startPoint: Int, attempt: Upload.Attempt, progress progressBlock: @escaping UploadEndpointProgress) async throws -> Upload.Result
}

extension Upload {
    typealias Endpoint = UploadEndpoint
}
