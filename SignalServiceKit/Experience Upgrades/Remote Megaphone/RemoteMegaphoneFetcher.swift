//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Handles fetching and parsing remote megaphones.
@objc
public class RemoteMegaphoneFetcher: NSObject, Dependencies {
    private let isSyncInFlight = AtomicBool(false)

    override public init() {
        super.init()

        guard
            CurrentAppContext().isMainApp,
            !CurrentAppContext().isRunningTests
        else {
            return
        }

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            self.databaseStorage.read { transaction in
                self.syncRemoteMegaphonesIfNecessary(transaction: transaction)
            }
        }
    }

    /// Fetch all remote megaphones currently on the service and persist them
    /// locally. Removes any locally-persisted remote megaphones that are no
    /// longer available remotely.
    @discardableResult
    public func syncRemoteMegaphonesIfNecessary(transaction: SDSAnyReadTransaction) -> Promise<Void> {
        guard self.shouldSync(transaction: transaction) else {
            Logger.info("Skipping remote megaphone fetch - not necessary!")
            return Promise.value(())
        }

        guard !isSyncInFlight.get() else {
            Logger.info("Skipping remote megaphone fetch - sync is already in-flight!")
            return Promise.value(())
        }

        isSyncInFlight.set(true)

        Logger.info("Beginning remote megaphone fetch.")

        return fetchRemoteMegaphones().map(on: .global()) { megaphones -> Void in
            Logger.info("Syncing \(megaphones.count) fetched remote megaphones with local state.")

            self.databaseStorage.write { transaction in
                self.updatePersistedMegaphones(
                    withFetchedMegaphones: megaphones,
                    transaction: transaction
                )

                self.recordCompletedSync(transaction: transaction)
            }
        }.ensure {
            self.isSyncInFlight.set(false)
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
    private static let fetcherStore = SDSKeyValueStore(collection: .fetcherStoreCollection)

    private static let delayBetweenSyncs: TimeInterval = 3 * kDayInterval

    func shouldSync(transaction: SDSAnyReadTransaction) -> Bool {
        guard
            let appVersionAtLastFetch = Self.fetcherStore.getString(.appVersionAtLastFetchKey, transaction: transaction),
            let lastFetchDate = Self.fetcherStore.getDate(.lastFetchDateKey, transaction: transaction)
        else {
            // If we have never recorded last-fetch data, we should sync.
            return true
        }

        let hasUpgradedAppVerison = AppVersion.compare(appVersionAtLastFetch, with: appVersion.currentAppVersion4) == .orderedAscending
        let hasWaitedEnoughSinceLastSync = Date().timeIntervalSince(lastFetchDate) > Self.delayBetweenSyncs

        return hasUpgradedAppVerison || hasWaitedEnoughSinceLastSync
    }

    func recordCompletedSync(transaction: SDSAnyWriteTransaction) {
        Self.fetcherStore.setString(
            appVersion.currentAppVersion4,
            key: .appVersionAtLastFetchKey,
            transaction: transaction
        )

        Self.fetcherStore.setDate(
            Date(),
            key: .lastFetchDateKey,
            transaction: transaction
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
    func fetchRemoteMegaphones() -> Promise<[RemoteMegaphoneModel]> {
        fetchManifests().then(on: .global()) { manifests -> Promise<[RemoteMegaphoneModel]> in
            Promise.when(fulfilled: manifests.map { manifest in
                self.fetchTranslation(forMegaphoneManifest: manifest).map(on: .global()) { translation in
                    if manifest.id != translation.id {
                        // We shouldn't fail here, but this scenario is
                        // unexpected so let's keep an eye out for it.
                        owsFailDebug("Have manifest ID \(manifest.id) that does not match fetched translation ID \(translation.id)")
                    }

                    return RemoteMegaphoneModel(manifest: manifest, translation: translation)
                }
            })
        }
    }

    private func getUrlSession() -> OWSURLSessionProtocol {
        signalService.urlSessionForUpdates2()
    }

    /// Fetch the manifests for the currently-active remote megaphones.
    /// Manifests contain metadata about a megaphone, such as when it should be
    /// shown and what actions it should expose. They do not contain any
    /// user-visible content, such as strings.
    private func fetchManifests(remainingRetries: UInt = 2) -> Promise<[RemoteMegaphoneModel.Manifest]> {
        firstly { () -> Promise<HTTPResponse> in
            getUrlSession().dataTaskPromise(
                .manifestUrlPath,
                method: .get
            )
        }.map(on: .global()) { response throws -> [RemoteMegaphoneModel.Manifest] in
            guard let responseJson = response.responseBodyJson else {
                throw OWSAssertionError("Missing body JSON for manifest!")
            }

            return try RemoteMegaphoneModel.Manifest.parseFrom(responseJson: responseJson)
        }.recover(on: .global()) { error in
            guard
                error.isNetworkFailureOrTimeout,
                remainingRetries > 0
            else {
                throw error
            }

            return self.fetchManifests(remainingRetries: remainingRetries - 1)
        }
    }

    /// Fetch user-displayable localized strings for the given manifest. Will
    /// attempt to fetch a translation matching the user's current locale,
    /// falling back to English otherwise.
    private func fetchTranslation(
        forMegaphoneManifest manifest: RemoteMegaphoneModel.Manifest
    ) -> Promise<RemoteMegaphoneModel.Translation> {
        let localeStrings: [String] = .possibleTranslationLocaleStrings

        guard let firstLocaleString = localeStrings.first else {
            return Promise(error: OWSAssertionError("Unexpectedly found no locale strings!"))
        }

        // Try and fetch using the first returned locale string...
        var fetchPromise: Promise<RemoteMegaphoneModel.Translation> = fetchTranslation(
            forMegaphoneManifest: manifest,
            withLocaleString: firstLocaleString
        )

        // ...and for each subsequent locale string, if the previous fetch
        // returned a 404 try the next one.
        for localeString in localeStrings.dropFirst() {
            fetchPromise = fetchPromise.recover(on: .global(), { error in
                guard
                    let httpStatus = error.httpStatusCode,
                    httpStatus == 404
                else {
                    // If we hit a non-404 error, propagate it out immediately.
                    throw error
                }

                return self.fetchTranslation(
                    forMegaphoneManifest: manifest,
                    withLocaleString: localeString
                )
            })
        }

        return fetchPromise.then(on: .global()) { translation -> Promise<RemoteMegaphoneModel.Translation> in
            self.downloadImageIfNecessary(forTranslation: translation).map(on: .global()) { url in
                guard let url = url else {
                    return translation
                }

                var translation = translation
                translation.setImageLocalUrl(url)
                return translation
            }
        }
    }

    /// Fetch a translation for the given manifest, using the given locale
    /// string. Retries automatically on network failure, if possible. May
    /// fail with a 404, if no translation exists for the given locale string.
    private func fetchTranslation(
        forMegaphoneManifest manifest: RemoteMegaphoneModel.Manifest,
        withLocaleString localeString: String,
        remainingRetries: UInt = 2
    ) -> Promise<RemoteMegaphoneModel.Translation> {
        return firstly { () -> Promise<HTTPResponse> in
            guard let translationUrlPath: String = .translationUrlPath(
                forManifest: manifest,
                withLocaleString: localeString
            ) else {
                return .init(error: OWSAssertionError("Failed to create translation URL path for manifest \(manifest.id)"))
            }

            return getUrlSession().dataTaskPromise(translationUrlPath, method: .get)
        }.map(on: .global()) { response throws in
            guard let responseJson = response.responseBodyJson else {
                throw OWSAssertionError("Missing body JSON for translation!")
            }

            return try RemoteMegaphoneModel.Translation.parseFrom(responseJson: responseJson)
        }.recover(on: .global()) { error in
            guard
                error.isNetworkFailureOrTimeout,
                remainingRetries > 0
            else {
                throw error
            }

            return self.fetchTranslation(
                forMegaphoneManifest: manifest,
                withLocaleString: localeString,
                remainingRetries: remainingRetries - 1
            )
        }
    }

    /// Get a path to the local image file for this translation. Fetches the
    /// image if necessary. Returns ``nil`` if this translation has no image.
    private func downloadImageIfNecessary(
        forTranslation translation: RemoteMegaphoneModel.Translation,
        remainingRetries: UInt = 2
    ) -> Promise<URL?> {
        guard let imageRemoteUrlPath = translation.imageRemoteUrlPath else {
            return .value(nil)
        }

        guard let imageFileUrl: URL = .imageFilePath(forFetchedTranslation: translation) else {
            return .init(error: OWSAssertionError("Failed to get image file path for translation with ID \(translation.id)"))
        }

        guard !FileManager.default.fileExists(atPath: imageFileUrl.path) else {
            return .value(imageFileUrl)
        }

        return firstly {
            getUrlSession().downloadTaskPromise(
                imageRemoteUrlPath,
                method: .get
            )
        }.map(on: .global()) { (response: OWSUrlDownloadResponse) -> URL in
            do {
                try FileManager.default.moveItem(
                    at: response.downloadUrl,
                    to: imageFileUrl
                )
            } catch let error {
                throw OWSAssertionError("Failed to move downloaded image! \(error)")
            }

            return imageFileUrl
        }.recover(on: .global()) { error -> Promise<URL?> in
            if
                error.isNetworkFailureOrTimeout,
                remainingRetries > 0
            {
                return self.downloadImageIfNecessary(
                    forTranslation: translation,
                    remainingRetries: remainingRetries - 1
                )
            } else if let httpStatusCode = error.httpStatusCode {
                switch httpStatusCode {
                case 404:
                    owsFailDebug("Unexpectedly got 404 while fetching remote megaphone image for ID \(translation.id)!")
                    return .value(nil)
                case 500..<600:
                    owsFailDebug("Encountered server error with status \(httpStatusCode) while fetching remote megaphone image!")
                    return .value(nil)
                default:
                    owsFailDebug("Unexpectedly got error status code \(httpStatusCode) while fetching remote megaphone image for ID \(translation.id)!")
                }
            }

            throw error
        }
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
    private static let imageUrlKey = "imageUrl"
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
