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
            self.isSyncInFlight.set(false)

            Logger.info("Syncing \(megaphones.count) fetched remote megaphones with local state.")

            self.databaseStorage.write { transaction in
                self.updatePersistedMegaphones(
                    withFetchedMegaphones: megaphones,
                    transaction: transaction
                )

                self.recordCompletedSync(transaction: transaction)
            }
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
            guard let bodyData = response.responseBodyData else {
                throw OWSAssertionError("Missing body data for manifest!")
            }

            return try RemoteMegaphoneModel.Manifest.parseFrom(jsonData: bodyData)
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
            guard let bodyData = response.responseBodyData else {
                throw OWSAssertionError("Missing body data for translation!")
            }

            return try RemoteMegaphoneModel.Translation.parseFrom(jsonData: bodyData)
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
        }.recover(on: .global()) { error in
            guard
                error.isNetworkFailureOrTimeout,
                remainingRetries > 0
            else {
                throw error
            }

            return self.downloadImageIfNecessary(
                forTranslation: translation,
                remainingRetries: remainingRetries - 1
            )
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
    private struct JsonRepresentationFromService: Decodable {
        struct IndividualManifestRepresentationFromService: Decodable {
            /// Generated UUID for this manifest.
            let uuid: String
            /// Integer representing the priority of this manifest.
            let priority: Int
            /// CSV string of format `country\_code:PPM` like in remote config, using the manifest's ID as the key.
            let countries: String
            /// Minimum app version on which this megaphone should be shown.
            let iosMinVersion: String?
            /// Unix timestamp after which this megaphone can be shown.
            let dontShowBeforeEpochSeconds: UInt64
            /// Unix timestamp after which this megaphone can no longer be shown.
            let dontShowAfterEpochSeconds: UInt64
            /// Number of days for which to show this megaphone.
            let showForNumberOfDays: Int
            /// Known identifier to perform some conditional check before showing this megaphone.
            let conditionalId: String?
            /// Known identifier to perform some action on the megaphone's primary button.
            let primaryCtaId: String?
            /// Known identifier to perform some action on the megaphone's secondary button.
            let secondaryCtaId: String?
        }

        let megaphones: [IndividualManifestRepresentationFromService]
    }

    static func parseFrom(jsonData: Data) throws -> [Self] {
        let megaphones: [JsonRepresentationFromService.IndividualManifestRepresentationFromService]
        do {
            megaphones = try JSONDecoder().decode(JsonRepresentationFromService.self, from: jsonData).megaphones
        } catch let error {
            throw OWSAssertionError("Failed to decode remote megaphone manifest JSON: \(error)")
        }

        return megaphones.compactMap { representation in
            guard let iosMinVersion = representation.iosMinVersion else {
                return nil
            }

            var conditionalCheck: ConditionalCheck?
            if let conditionalId = representation.conditionalId {
                conditionalCheck = ConditionalCheck(fromConditionalId: conditionalId)
            }

            var primaryAction: Action?
            if let primaryCtaId = representation.primaryCtaId {
                primaryAction = Action(fromActionId: primaryCtaId)
            }

            var secondaryAction: Action?
            if let secondaryCtaId = representation.secondaryCtaId {
                secondaryAction = Action(fromActionId: secondaryCtaId)
            }

            return RemoteMegaphoneModel.Manifest(
                id: representation.uuid,
                priority: representation.priority,
                minAppVersion: iosMinVersion,
                countries: representation.countries,
                dontShowBefore: representation.dontShowBeforeEpochSeconds,
                dontShowAfter: representation.dontShowAfterEpochSeconds,
                showForNumberOfDays: representation.showForNumberOfDays,
                conditionalCheck: conditionalCheck,
                primaryAction: primaryAction,
                secondaryAction: secondaryAction
            )
        }
    }
}

// MARK: - Parsing translations

private extension RemoteMegaphoneModel.Translation {
    private struct JsonRepresentationFromService: Decodable {
        /// UUID, corresponding to the manifest.
        let uuid: String
        /// URL to image asset.
        let imageUrl: String?
        /// Title of announcement
        let title: String
        /// Body of announcement
        let body: String
        /// Text for primary action
        let primaryCtaText: String?
        /// Text for secondary action
        let secondaryCtaText: String?
    }

    static func parseFrom(jsonData: Data) throws -> Self {
        let representation: JsonRepresentationFromService
        do {
            representation = try JSONDecoder().decode(JsonRepresentationFromService.self, from: jsonData)
        } catch let error {
            throw OWSAssertionError("Failed to decode remote megaphone translation JSON: \(error)")
        }

        guard representation.uuid.isPermissibleAsFilename else {
            throw OWSAssertionError("Translation had UUID that is illegal filename: \(representation.uuid)")
        }

        return RemoteMegaphoneModel.Translation(
            id: representation.uuid,
            title: representation.title,
            body: representation.body,
            imageRemoteUrlPath: representation.imageUrl,
            imageLocalUrl: nil,
            primaryActionText: representation.primaryCtaText,
            secondaryActionText: representation.primaryCtaText
        )
    }
}
