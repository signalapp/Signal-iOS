//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Handles fetching and parsing remote megaphones.
class RemoteMegaphoneFetcher {
    private let databaseStorage: SDSDatabaseStorage
    private let signalService: any OWSSignalServiceProtocol

    init(
        databaseStorage: SDSDatabaseStorage,
        signalService: any OWSSignalServiceProtocol,
    ) {
        self.databaseStorage = databaseStorage
        self.signalService = signalService
    }

    /// Fetch all remote megaphones currently on the service and persist them
    /// locally. Removes any locally-persisted remote megaphones that are no
    /// longer available remotely.
    func syncRemoteMegaphones() async throws {
        Logger.info("Beginning remote megaphone fetch.")

        let megaphones: [RemoteMegaphoneModel]
        do {
            megaphones = try await fetchRemoteMegaphones()
        } catch {
            Logger.warn("\(error)")
            throw error
        }

        Logger.info("Syncing \(megaphones.count) fetched remote megaphones with local state.")

        await self.databaseStorage.awaitableWrite { transaction in
            self.updatePersistedMegaphones(
                withFetchedMegaphones: megaphones,
                transaction: transaction,
            )
        }
    }
}

// MARK: - Persisted megaphones

private extension RemoteMegaphoneFetcher {
    /// Update our local persisted megaphone state with freshly-fetched
    /// megaphones from the service. Updates existing megaphones if present,
    /// and creates new ones if necessary. Removes any locally-persisted
    /// megaphones that no longer exist on the service.
    func updatePersistedMegaphones(
        withFetchedMegaphones serviceMegaphones: [RemoteMegaphoneModel],
        transaction: DBWriteTransaction,
    ) {
        // Get the current remote megaphones.
        var localRemoteMegaphones: [String: ExperienceUpgrade] = [:]
        ExperienceUpgrade.anyEnumerate(transaction: transaction) { upgrade, _ in
            if case .remoteMegaphone = upgrade.manifest {
                localRemoteMegaphones[upgrade.uniqueId] = upgrade
            }
        }

        // Insert all megaphones we got from the service. If we already have a
        // persisted copy of this megaphone, update it - this will ensure that
        // if anything has changed about the megaphone we have the latest state.
        // For example, if the user's locale has changed we may have updated
        // translations.
        for serviceMegaphone in serviceMegaphones {
            if let existingLocalMegaphone = localRemoteMegaphones[serviceMegaphone.id] {
                existingLocalMegaphone.updateManifestRemoteMegaphone(withRefetchedMegaphone: serviceMegaphone)
                existingLocalMegaphone.anyUpsert(transaction: transaction)

                localRemoteMegaphones.removeValue(forKey: serviceMegaphone.id)
            } else {
                ExperienceUpgrade
                    .makeNew(withManifest: .remoteMegaphone(megaphone: serviceMegaphone))
                    .anyInsert(transaction: transaction)
            }
        }

        // Remove records for any remaining local megaphones, which are no
        // longer on the service.
        for (_, experienceUpgradeToRemove) in localRemoteMegaphones {
            experienceUpgradeToRemove.anyRemove(transaction: transaction)
        }
    }
}

// MARK: - Fetching

private extension RemoteMegaphoneFetcher {
    func fetchRemoteMegaphones() async throws -> [RemoteMegaphoneModel] {
        let manifests = try await fetchManifests()
        return try await withThrowingTaskGroup(of: RemoteMegaphoneModel.self) { taskGroup in
            for manifest in manifests {
                taskGroup.addTask {
                    let translation = try await self.fetchTranslation(forMegaphoneManifest: manifest)
                    if manifest.id != translation.id {
                        // We shouldn't fail here, but this scenario is
                        // unexpected so let's keep an eye out for it.
                        owsFailDebug("Have manifest ID \(manifest.id) that does not match fetched translation ID \(translation.id)")
                    }

                    return RemoteMegaphoneModel(manifest: manifest, translation: translation)
                }
            }
            return try await taskGroup.reduce(into: [], { $0.append($1) })
        }
    }

    private func getUrlSession() -> OWSURLSessionProtocol {
        signalService.urlSessionForUpdates2()
    }

    /// Fetch the manifests for the currently-active remote megaphones.
    /// Manifests contain metadata about a megaphone, such as when it should be
    /// shown and what actions it should expose. They do not contain any
    /// user-visible content, such as strings.
    private func fetchManifests() async throws -> [RemoteMegaphoneModel.Manifest] {
        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                Logger.info("Fetching remote megaphone manifests")
                let response = try await getUrlSession().performRequest(
                    .manifestUrlPath,
                    method: .get,
                )

                guard let parser = response.responseBodyParamParser else {
                    throw OWSAssertionError("Missing or invalid body JSON for manifest!")
                }

                return try RemoteMegaphoneModel.Manifest.parseFrom(parser: parser)
            },
        )
    }

    /// Fetch user-displayable localized strings for the given manifest. Will
    /// attempt to fetch a translation matching the user's current locale,
    /// falling back to English otherwise.
    private func fetchTranslation(
        forMegaphoneManifest manifest: RemoteMegaphoneModel.Manifest,
    ) async throws -> RemoteMegaphoneModel.Translation {
        let localeStrings: [String] = .possibleTranslationLocaleStrings

        for (index, localeString) in localeStrings.enumerated() {
            do {
                var translation = try await fetchTranslation(forMegaphoneManifest: manifest, withLocaleString: localeString)
                translation.setHasImage(try await self.downloadImageIfNecessary(forTranslation: translation))
                return translation
            } catch let error as OWSHTTPError where error.responseStatusCode == 404 && (index + 1) != localeStrings.endIndex {
                // If this isn't the last locale & it's not found, try the next one.
                continue
            }
            // If we hit a non-404 error, propagate it out immediately.
        }

        // We either return a value or throw an error in the loop as long as there
        // is at least one locale.
        throw OWSAssertionError("Unexpectedly found no locale strings!")
    }

    /// Fetch a translation for the given manifest, using the given locale
    /// string. Retries automatically on network failure, if possible. May
    /// fail with a 404, if no translation exists for the given locale string.
    private func fetchTranslation(
        forMegaphoneManifest manifest: RemoteMegaphoneModel.Manifest,
        withLocaleString localeString: String,
    ) async throws -> RemoteMegaphoneModel.Translation {
        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                guard
                    let translationUrlPath: String = .translationUrlPath(
                        forManifest: manifest,
                        withLocaleString: localeString,
                    )
                else {
                    throw OWSAssertionError("Failed to create translation URL path for manifest \(manifest.id)")
                }
                Logger.info("Fetching remote megaphone translation")
                let response = try await getUrlSession().performRequest(translationUrlPath, method: .get)
                guard let parser = response.responseBodyParamParser else {
                    throw OWSAssertionError("Missing or invalid body JSON for translation!")
                }
                return try RemoteMegaphoneModel.Translation.parseFrom(parser: parser)
            },
        )
    }

    /// Downloads the image if necessary.
    ///
    /// Doesn't perform any network requests if the image has already been
    /// downloaded.
    ///
    /// - Throws: If the image should be downloaded but can't be downloaded.
    /// - Returns: Whether or not `translation` has an image.
    private func downloadImageIfNecessary(
        forTranslation translation: RemoteMegaphoneModel.Translation,
    ) async throws -> Bool {
        guard let imageRemoteUrlPath = translation.imageRemoteUrlPath else {
            return false
        }

        guard let imageFileUrl: URL = .imageFilePath(forFetchedTranslation: translation) else {
            throw OWSAssertionError("Failed to get image file path for translation with ID \(translation.id)")
        }

        return try await Retry.performWithBackoff(
            maxAttempts: 3,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: {
                do {
                    if !FileManager.default.fileExists(atPath: imageFileUrl.path) {
                        Logger.info("Fetching remote megaphone image")
                        let response = try await getUrlSession().performDownload(
                            imageRemoteUrlPath,
                            method: .get,
                        )

                        do {
                            try FileManager.default.moveItem(
                                at: response.downloadUrl,
                                to: imageFileUrl,
                            )
                        } catch let error {
                            throw OWSAssertionError("Failed to move downloaded image! \(error)")
                        }
                    }
                    return true
                } catch where error.httpStatusCode == 404 {
                    owsFailDebug("Unexpectedly got 404 while fetching remote megaphone image for ID \(translation.id)!")
                    return false
                } catch let error as OWSHTTPError {
                    owsFailDebug("Unexpectedly got error status code \(error.responseStatusCode) while fetching remote megaphone image for ID \(translation.id)!")
                    throw error
                }
            },
        )
    }
}

// MARK: URLs

private extension URL {
    static func imageFilePath(forFetchedTranslation translation: RemoteMegaphoneModel.Translation) -> URL? {
        let dirUrl = RemoteMegaphoneModel.imagesDirectory

        guard OWSFileSystem.ensureDirectoryExists(dirUrl.path) else {
            return nil
        }

        return dirUrl.appendingPathComponent(translation.imageLocalRelativePath)
    }
}

private extension Array<String> {
    /// A list of possible locale strings for which a translation may be
    /// available, based on the user's current locale. Includes a fallback to
    /// English.
    static var possibleTranslationLocaleStrings: [String] {
        var locales: [String] = []

        if let langCode = Locale.current.languageCode {
            locales.append(langCode)

            if let regionCode = Locale.current.regionCode {
                locales.append("\(langCode)_\(regionCode)")
            }
        }

        // Always include English at the end, as a fallback. This translation
        // should always exist.
        return locales + ["en"]
    }
}

private extension String {
    /// The path at which remote megaphone manifests are listed.
    static let manifestUrlPath = "dynamic/release-notes/release-notes-v2.json"

    /// The path at which a translation may be found, for the given manifest
    /// and locale string.
    static func translationUrlPath(
        forManifest manifest: RemoteMegaphoneModel.Manifest,
        withLocaleString localeString: String,
    ) -> String? {
        "static/release-notes/\(manifest.id)/\(localeString).json"
            .percentEncodedAsUrlPath
    }
}

// MARK: - Parsing manifests

private extension RemoteMegaphoneModel.Manifest {
    private static let megaphonesKey = "megaphones"
    private static let uuidKey = "uuid"
    private static let priorityKey = "priority"
    private static let iosMinVersionKey = "iosMinVersion"
    private static let countriesKey = "countries"
    private static let dontShowBeforeEpochSecondsKey = "dontShowBeforeEpochSeconds"
    private static let dontShowAfterEpochSecondsKey = "dontShowAfterEpochSeconds"
    private static let showForNumberOfDaysKey = "showForNumberOfDays"
    private static let conditionalIdKey = "conditionalId"
    private static let primaryCtaIdKey = "primaryCtaId"
    private static let primaryCtaDataKey = "primaryCtaData"
    private static let secondaryCtaIdKey = "secondaryCtaId"
    private static let secondaryCtaDataKey = "secondaryCtaData"

    static func parseFrom(parser megaphonesArrayParser: ParamParser) throws -> [Self] {
        let individualMegaphones: [[String: Any]] = try megaphonesArrayParser.required(key: Self.megaphonesKey)

        return try individualMegaphones.compactMap { megaphoneObject throws -> Self? in
            let megaphoneParser = ParamParser(megaphoneObject)

            guard let iosMinVersion: String = try megaphoneParser.optional(key: Self.iosMinVersionKey) else {
                return nil
            }

            let uuid: String = try megaphoneParser.required(key: Self.uuidKey)
            let priority: Int = try megaphoneParser.required(key: Self.priorityKey)
            let countries: String = try megaphoneParser.required(key: Self.countriesKey)
            let dontShowBeforeEpochSeconds: UInt64 = try megaphoneParser.required(key: Self.dontShowBeforeEpochSecondsKey)
            let dontShowAfterEpochSeconds: UInt64 = try megaphoneParser.required(key: Self.dontShowAfterEpochSecondsKey)
            let showForNumberOfDays: Int = try megaphoneParser.required(key: Self.showForNumberOfDaysKey)

            let conditionalId: String? = try megaphoneParser.optional(key: Self.conditionalIdKey)
            let primaryCtaId: String? = try megaphoneParser.optional(key: Self.primaryCtaIdKey)
            let primaryCtaDataJson: [String: Any]? = try megaphoneParser.optional(key: Self.primaryCtaDataKey)
            let secondaryCtaId: String? = try megaphoneParser.optional(key: Self.secondaryCtaIdKey)
            let secondaryCtaDataJson: [String: Any]? = try megaphoneParser.optional(key: Self.secondaryCtaDataKey)

            var conditionalCheck: ConditionalCheck?
            if let conditionalId {
                conditionalCheck = ConditionalCheck(fromConditionalId: conditionalId)
            }

            var primaryAction: Action?
            if let primaryCtaId {
                primaryAction = Action(fromActionId: primaryCtaId)
            }

            var primaryActionData: ActionData?
            if let primaryCtaDataJson {
                primaryActionData = try ActionData.parse(fromJson: primaryCtaDataJson)
            }

            var secondaryAction: Action?
            if let secondaryCtaId {
                secondaryAction = Action(fromActionId: secondaryCtaId)
            }

            var secondaryActionData: ActionData?
            if let secondaryCtaDataJson {
                secondaryActionData = try ActionData.parse(fromJson: secondaryCtaDataJson)
            }

            return RemoteMegaphoneModel.Manifest(
                id: uuid,
                priority: priority,
                minAppVersion: iosMinVersion,
                countries: countries,
                dontShowBefore: dontShowBeforeEpochSeconds,
                dontShowAfter: dontShowAfterEpochSeconds,
                showForNumberOfDays: showForNumberOfDays,
                conditionalCheck: conditionalCheck,
                primaryAction: primaryAction,
                primaryActionData: primaryActionData,
                secondaryAction: secondaryAction,
                secondaryActionData: secondaryActionData,
            )
        }
    }
}

// MARK: - Parsing translations

private extension RemoteMegaphoneModel.Translation {
    private static let uuidKey = "uuid"
    private static let imageUrlKey = "image"
    private static let titleKey = "title"
    private static let bodyKey = "body"
    private static let primaryCtaTextKey = "primaryCtaText"
    private static let secondaryCtaTextKey = "secondaryCtaText"

    static func parseFrom(parser: ParamParser) throws -> Self {
        let uuid: String = try parser.required(key: Self.uuidKey)
        let imageUrl: String? = try parser.optional(key: Self.imageUrlKey)
        let title: String = try parser.required(key: Self.titleKey)
        let body: String = try parser.required(key: Self.bodyKey)
        let primaryCtaText: String? = try parser.optional(key: Self.primaryCtaTextKey)
        let secondaryCtaText: String? = try parser.optional(key: Self.secondaryCtaTextKey)

        guard uuid.isPermissibleAsFilename else {
            throw OWSAssertionError("Translation had UUID that is illegal filename: \(uuid)")
        }

        return RemoteMegaphoneModel.Translation.makeWithoutLocalImage(
            id: uuid,
            title: title,
            body: body,
            imageRemoteUrlPath: imageUrl,
            primaryActionText: primaryCtaText,
            secondaryActionText: secondaryCtaText,
        )
    }
}
