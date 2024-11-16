//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

/// Handles fetching and parsing remote megaphones.
public class RemoteMegaphoneFetcher {
    private let databaseStorage: SDSDatabaseStorage
    private let signalService: any OWSSignalServiceProtocol

    public init(
        databaseStorage: SDSDatabaseStorage,
        signalService: any OWSSignalServiceProtocol
    ) {
        self.databaseStorage = databaseStorage
        self.signalService = signalService
    }

    /// Fetch all remote megaphones currently on the service and persist them
    /// locally. Removes any locally-persisted remote megaphones that are no
    /// longer available remotely.
    public func syncRemoteMegaphonesIfNecessary() async throws {
        let shouldSync = databaseStorage.read { self.shouldSync(transaction: $0) }
        guard shouldSync else {
            return
        }

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
                transaction: transaction
            )

            self.recordCompletedSync(transaction: transaction)
        }
    }
}

// MARK: - Sync conditions

private extension String {
    static let fetcherStoreCollection = "RemoteMegaphoneFetcher"
    static let appVersionAtLastFetchKey = "appVersionAtLastFetch"
    static let lastFetchDateKey = "lastFetchDate"
}

private extension RemoteMegaphoneFetcher {
    private static let fetcherStore = KeyValueStore(collection: .fetcherStoreCollection)

    private static let delayBetweenSyncs: TimeInterval = 3 * kDayInterval

    func shouldSync(transaction: SDSAnyReadTransaction) -> Bool {
        guard
            let appVersionAtLastFetch = Self.fetcherStore.getString(.appVersionAtLastFetchKey, transaction: transaction.asV2Read),
            let lastFetchDate = Self.fetcherStore.getDate(.lastFetchDateKey, transaction: transaction.asV2Read)
        else {
            // If we have never recorded last-fetch data, we should sync.
            return true
        }

        let hasChangedAppVersion = appVersionAtLastFetch != AppVersionImpl.shared.currentAppVersion
        let hasWaitedEnoughSinceLastSync = Date().timeIntervalSince(lastFetchDate) > Self.delayBetweenSyncs

        return hasChangedAppVersion || hasWaitedEnoughSinceLastSync
    }

    func recordCompletedSync(transaction: SDSAnyWriteTransaction) {
        Self.fetcherStore.setString(
            AppVersionImpl.shared.currentAppVersion,
            key: .appVersionAtLastFetchKey,
            transaction: transaction.asV2Write
        )

        Self.fetcherStore.setDate(
            Date(),
            key: .lastFetchDateKey,
            transaction: transaction.asV2Write
        )
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
        transaction: SDSAnyWriteTransaction
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
    private func fetchManifests(remainingRetries: UInt = 2) async throws -> [RemoteMegaphoneModel.Manifest] {
        var remainingRetries = remainingRetries
        while true {
            do {
                let response = try await getUrlSession().performRequest(
                    .manifestUrlPath,
                    method: .get
                )

                guard let responseJson = response.responseBodyJson else {
                    throw OWSAssertionError("Missing body JSON for manifest!")
                }

                return try RemoteMegaphoneModel.Manifest.parseFrom(responseJson: responseJson)
            } catch where remainingRetries > 0 && error.isNetworkFailureOrTimeout {
                Logger.warn("Retrying after failure: \(error)")
                remainingRetries -= 1
                continue
            }
        }
    }

    /// Fetch user-displayable localized strings for the given manifest. Will
    /// attempt to fetch a translation matching the user's current locale,
    /// falling back to English otherwise.
    private func fetchTranslation(
        forMegaphoneManifest manifest: RemoteMegaphoneModel.Manifest
    ) async throws -> RemoteMegaphoneModel.Translation {
        let localeStrings: [String] = .possibleTranslationLocaleStrings

        for (index, localeString) in localeStrings.enumerated() {
            do {
                var translation = try await fetchTranslation(forMegaphoneManifest: manifest, withLocaleString: localeString)
                if let url = try await self.downloadImageIfNecessary(forTranslation: translation) {
                    translation.setImageLocalUrl(url)
                }
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
        remainingRetries: UInt = 2
    ) async throws -> RemoteMegaphoneModel.Translation {
        var remainingRetries = remainingRetries
        while true {
            do {
                guard let translationUrlPath: String = .translationUrlPath(
                    forManifest: manifest,
                    withLocaleString: localeString
                ) else {
                    throw OWSAssertionError("Failed to create translation URL path for manifest \(manifest.id)")
                }
                let response = try await getUrlSession().performRequest(translationUrlPath, method: .get)
                guard let responseJson = response.responseBodyJson else {
                    throw OWSAssertionError("Missing body JSON for translation!")
                }
                return try RemoteMegaphoneModel.Translation.parseFrom(responseJson: responseJson)
            } catch where remainingRetries > 0 && error.isNetworkFailureOrTimeout {
                Logger.warn("Retrying after failure: \(error)")
                remainingRetries -= 1
                continue
            }
        }
    }

    /// Get a path to the local image file for this translation. Fetches the
    /// image if necessary. Returns ``nil`` if this translation has no image.
    private func downloadImageIfNecessary(
        forTranslation translation: RemoteMegaphoneModel.Translation,
        remainingRetries: UInt = 2
    ) async throws -> URL? {
        guard let imageRemoteUrlPath = translation.imageRemoteUrlPath else {
            return nil
        }

        guard let imageFileUrl: URL = .imageFilePath(forFetchedTranslation: translation) else {
            throw OWSAssertionError("Failed to get image file path for translation with ID \(translation.id)")
        }

        var remainingRetries = remainingRetries
        while !FileManager.default.fileExists(atPath: imageFileUrl.path) {
            do {
                let response = try await getUrlSession().performDownload(
                    imageRemoteUrlPath,
                    method: .get
                )

                do {
                    try FileManager.default.moveItem(
                        at: response.downloadUrl,
                        to: imageFileUrl
                    )
                } catch let error {
                    throw OWSAssertionError("Failed to move downloaded image! \(error)")
                }
                break
            } catch where remainingRetries > 0 && error.isNetworkFailureOrTimeout {
                remainingRetries -= 1
                continue
            } catch let error as OWSHTTPError {
                switch error.responseStatusCode {
                case 404:
                    owsFailDebug("Unexpectedly got 404 while fetching remote megaphone image for ID \(translation.id)!")
                    return nil
                case 500..<600:
                    owsFailDebug("Encountered server error with status \(error.responseStatusCode) while fetching remote megaphone image!")
                    return nil
                default:
                    owsFailDebug("Unexpectedly got error status code \(error.responseStatusCode) while fetching remote megaphone image for ID \(translation.id)!")
                    throw error
                }
            }
        }

        return imageFileUrl
    }
}

// MARK: URLs

private extension URL {
    private static let imagesSubdirectory: String = "MegaphoneImages"

    static func imageFilePath(forFetchedTranslation translation: RemoteMegaphoneModel.Translation) -> URL? {
        let dirUrl = OWSFileSystem.appSharedDataDirectoryURL()
            .appendingPathComponent(Self.imagesSubdirectory)

        guard OWSFileSystem.ensureDirectoryExists(dirUrl.path) else {
            return nil
        }

        return dirUrl.appendingPathComponent(translation.id)
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
        withLocaleString localeString: String
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

    static func parseFrom(responseJson: Any?) throws -> [Self] {
        guard let megaphonesArrayParser = ParamParser(responseObject: responseJson) else {
            throw OWSAssertionError("Failed to create parser from response JSON!")
        }

        let individualMegaphones: [[String: Any]] = try megaphonesArrayParser.required(key: Self.megaphonesKey)

        return try individualMegaphones.compactMap { megaphoneObject throws -> Self? in
            guard let megaphoneParser = ParamParser(responseObject: megaphoneObject) else {
                throw OWSAssertionError("Failed to create parser from individual megaphone JSON!")
            }

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
            if let conditionalId = conditionalId {
                conditionalCheck = ConditionalCheck(fromConditionalId: conditionalId)
            }

            var primaryAction: Action?
            if let primaryCtaId = primaryCtaId {
                primaryAction = Action(fromActionId: primaryCtaId)
            }

            var primaryActionData: ActionData?
            if let primaryCtaDataJson = primaryCtaDataJson {
                primaryActionData = try ActionData.parse(fromJson: primaryCtaDataJson)
            }

            var secondaryAction: Action?
            if let secondaryCtaId = secondaryCtaId {
                secondaryAction = Action(fromActionId: secondaryCtaId)
            }

            var secondaryActionData: ActionData?
            if let secondaryCtaDataJson = secondaryCtaDataJson {
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
                secondaryActionData: secondaryActionData
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

    static func parseFrom(responseJson: Any?) throws -> Self {
        guard let parser = ParamParser(responseObject: responseJson) else {
            throw OWSAssertionError("Failed to create parser from response JSON!")
        }

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
            secondaryActionText: secondaryCtaText
        )
    }
}
