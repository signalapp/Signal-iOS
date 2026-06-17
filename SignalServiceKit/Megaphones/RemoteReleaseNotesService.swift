//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

private extension String {
    /// The path at which remote megaphone manifests are listed.
    static let manifestUrlPath = "dynamic/release-notes/release-notes-v2.json"
}

public protocol RemoteReleaseNotesServiceProtocol {
    /// Fetches release-notes manifest from manifestUrlPath
    func fetchManifests() async throws -> ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest])

    /// Fetches megaphone for a specific translation and manifest Id
    func fetchMegaphoneTranslation(translationUrlPath: String) async throws -> RemoteMegaphoneModel.Translation

    /// Fetches announcements for a specific translation and manifest Id
    func fetchAnnouncementTranslation(translationUrlPath: String) async throws -> RemoteAnnouncementModel.Translation

    /// Downloads media included in a release notes manifest
    func downloadMedia(
        mediaRemoteUrlPath: String,
        mediaFileUrl: URL,
        translationId: String,
    ) async throws -> Bool
}

class RemoteReleaseNotesService: RemoteReleaseNotesServiceProtocol {
    let signalService: any OWSSignalServiceProtocol

    init(signalService: any OWSSignalServiceProtocol) {
        self.signalService = signalService
    }

    func getUrlSession() -> OWSURLSessionProtocol {
        signalService.urlSessionForUpdates2()
    }

    func fetchManifests() async throws -> ([RemoteMegaphoneModel.Manifest], [RemoteAnnouncementModel.Manifest]) {
        let manifestUrlPath: String
        if FeatureBuild.current <= .internal {
            manifestUrlPath = "dynamic/release-notes/release-notes-internal.json"
        } else {
            manifestUrlPath = .manifestUrlPath
        }

        let response = try await getUrlSession().performRequest(
            manifestUrlPath,
            method: .get,
            maxResponseSize: .max,
        )

        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid body JSON for manifest!")
        }

        return try (RemoteMegaphoneModel.Manifest.parseFrom(parser: parser), RemoteAnnouncementModel.Manifest.parseFrom(parser: parser))
    }

    func fetchMegaphoneTranslation(translationUrlPath: String) async throws -> RemoteMegaphoneModel.Translation {
        let paramParser = try await fetchTranslationParser(translationUrlPath: translationUrlPath)
        return try RemoteMegaphoneModel.Translation.parseFrom(parser: paramParser)
    }

    func fetchAnnouncementTranslation(translationUrlPath: String) async throws -> RemoteAnnouncementModel.Translation {
        let paramParser = try await fetchTranslationParser(translationUrlPath: translationUrlPath)
        return try RemoteAnnouncementModel.Translation.parseFrom(parser: paramParser)
    }

    private func fetchTranslationParser(translationUrlPath: String) async throws -> ParamParser {

        Logger.info("Fetching remote release notes translation")
        let response = try await getUrlSession().performRequest(translationUrlPath, method: .get, maxResponseSize: .max)
        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid body JSON for translation!")
        }
        return parser
    }

    func downloadMedia(
        mediaRemoteUrlPath: String,
        mediaFileUrl: URL,
        translationId: String,
    ) async throws -> Bool {
        do {
            if !FileManager.default.fileExists(atPath: mediaFileUrl.path) {
                Logger.info("Fetching remote release notes image")
                let response = try await getUrlSession().performDownload(
                    mediaRemoteUrlPath,
                    method: .get,
                    maxResponseSize: .max,
                )

                do {
                    try FileManager.default.moveItem(
                        at: response.downloadUrl,
                        to: mediaFileUrl,
                    )
                } catch let error {
                    throw OWSAssertionError("Failed to move downloaded image! \(error)")
                }
            }
            return true
        } catch where error.httpStatusCode == 404 {
            owsFailDebug("Unexpectedly got 404 while fetching remote megaphone image for ID \(translationId)!")
            return false
        } catch let error as OWSHTTPError {
            owsFailDebug("Unexpectedly got error status code \(error.responseStatusCode) while fetching remote megaphone image for ID \(translationId)!")
            throw error
        }
    }
}
