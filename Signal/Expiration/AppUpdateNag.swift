//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class AppUpdateNag {

    // MARK: Public

    public static let shared = AppUpdateNag(databaseStorage: SSKEnvironment.shared.databaseStorageRef)

    public func showAppUpgradeNagIfNecessary() {
        let currentVersion = AppVersionImpl.shared.currentAppVersion

        guard let bundleIdentifier = self.bundleIdentifier else {
            owsFailDebug("bundleIdentifier was unexpectedly nil")
            return
        }

        guard let lookupURL = lookupURL(bundleIdentifier: bundleIdentifier) else {
            owsFailDebug("appStoreURL was unexpectedly nil")
            return
        }

        Task {
            do {
                let appStoreRecord = try await Self.fetchLatestVersion(lookupURL: lookupURL)
                let appStoreVersion = AppVersionNumber(appStoreRecord.version)
                let currentVersion = AppVersionNumber(currentVersion)
                guard appStoreVersion > currentVersion else {
                    await self.clearFirstHeardOfNewVersionDate()
                    return
                }
                Logger.info("new version available: \(appStoreRecord)")
                await self.showUpdateNagIfEnoughTimeHasPassed(appStoreRecord: appStoreRecord)
            } catch {
                // Only failDebug if we're looking up the true org.whispersystems.signal app store record
                // If someone is building Signal with their own bundleID, it's less important that this succeeds.
                if error.isNetworkFailureOrTimeout || !bundleIdentifier.hasPrefix("org.whispersystems.") {
                    Logger.warn("failed with error: \(error)")
                } else {
                    owsFailDebug("Failed to find Signal app store record")
                }
            }
        }
    }

    private static func fetchLatestVersion(lookupURL: URL) async throws -> AppStoreRecord {
        let (data, _) = try await URLSession(configuration: .ephemeral).data(from: lookupURL)
        let decoder = JSONDecoder()
        let resultSet = try decoder.decode(AppStoreLookupResultSet.self, from: data)
        guard let appStoreRecord = resultSet.results.first else {
            throw OWSGenericError("Missing or invalid record.")
        }

        return appStoreRecord
    }

    // MARK: - Internal

    private static let kLastNagDateKey = "TSStorageManagerAppUpgradeNagDate"
    private static let kFirstHeardOfNewVersionDateKey = "TSStorageManagerAppUpgradeFirstHeardOfNewVersionDate"

    // MARK: - KV Store

    private let keyValueStore = KeyValueStore(collection: "TSStorageManagerAppUpgradeNagCollection")

    // MARK: - Bundle accessors

    private var bundle: Bundle {
        return Bundle.main
    }

    private var bundleIdentifier: String? {
        return bundle.bundleIdentifier
    }

    private func lookupURL(bundleIdentifier: String) -> URL? {
        var result = URLComponents(string: "https://itunes.apple.com/lookup")
        result?.queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        return result?.url
    }

    private let databaseStorage: SDSDatabaseStorage

    private init(databaseStorage: SDSDatabaseStorage) {
        self.databaseStorage = databaseStorage
        SwiftSingletons.register(self)
    }

    @MainActor
    private func showUpdateNagIfEnoughTimeHasPassed(appStoreRecord: AppStoreRecord) async {
        guard let firstHeardOfNewVersionDate = self.firstHeardOfNewVersionDate else {
            await setFirstHeardOfNewVersionDate(Date())
            return
        }

        let intervalBeforeNag = 21 * kDayInterval
        guard Date() > Date.init(timeInterval: intervalBeforeNag, since: firstHeardOfNewVersionDate) else {
            Logger.info("firstHeardOfNewVersionDate: \(firstHeardOfNewVersionDate) not nagging for new release yet.")
            return
        }

        if let lastNagDate = self.lastNagDate {
            let intervalBetweenNags = 14 * kDayInterval
            guard Date() > Date.init(timeInterval: intervalBetweenNags, since: lastNagDate) else {
                Logger.info("lastNagDate: \(lastNagDate) not nagging again so soon.")
                return
            }
        }

        // Only show nag if we are "at rest" in the conversation split or registration view without any
        // alerts or dialogs showing.
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }

        switch frontmostViewController {
        case is ConversationSplitViewController, is ProvisioningSplashViewController, is RegistrationSplashViewController:
            await setLastNagDate(Date())
            await clearFirstHeardOfNewVersionDate()
            presentUpgradeNag(appStoreRecord: appStoreRecord)
        default:
            Logger.debug("not presenting alert due to frontmostViewController: \(frontmostViewController)")
        }
    }

    @MainActor
    private func presentUpgradeNag(appStoreRecord: AppStoreRecord) {
        let title = OWSLocalizedString("APP_UPDATE_NAG_ALERT_TITLE", comment: "Title for the 'new app version available' alert.")

        let bodyFormat = OWSLocalizedString("APP_UPDATE_NAG_ALERT_MESSAGE_FORMAT", comment: "Message format for the 'new app version available' alert. Embeds: {{The latest app version number}}")
        let bodyText = String(format: bodyFormat, appStoreRecord.version)
        let updateButtonText = OWSLocalizedString("APP_UPDATE_NAG_ALERT_UPDATE_BUTTON", comment: "Label for the 'update' button in the 'new app version available' alert.")
        let dismissButtonText = OWSLocalizedString("APP_UPDATE_NAG_ALERT_DISMISS_BUTTON", comment: "Label for the 'dismiss' button in the 'new app version available' alert.")

        let alert = ActionSheetController(title: title, message: bodyText)

        let updateAction = ActionSheetAction(title: updateButtonText, style: .default) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.showAppStore(appStoreURL: appStoreRecord.appStoreURL)
        }

        alert.addAction(updateAction)
        alert.addAction(ActionSheetAction(title: dismissButtonText, style: .cancel) { _ in
            Logger.info("dismissed upgrade notice")
        })

        OWSActionSheets.showActionSheet(alert)
    }

    private func showAppStore(appStoreURL: URL) {
        assert(CurrentAppContext().isMainApp)

        Logger.debug("")

        UIApplication.shared.open(appStoreURL, options: [:])
    }

    // MARK: Storage

    private var firstHeardOfNewVersionDate: Date? {
        return databaseStorage.read { transaction in
            return self.keyValueStore.getDate(AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction.asV2Read)
        }
    }

    private func setFirstHeardOfNewVersionDate(_ date: Date) async {
        await databaseStorage.awaitableWrite { transaction in
            self.keyValueStore.setDate(date, key: AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction.asV2Write)
        }
    }

    private func clearFirstHeardOfNewVersionDate() async {
        await databaseStorage.awaitableWrite { transaction in
            self.keyValueStore.removeValue(forKey: AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction.asV2Write)
        }
    }

    private var lastNagDate: Date? {
        return databaseStorage.read { transaction in
            return self.keyValueStore.getDate(AppUpdateNag.kLastNagDateKey, transaction: transaction.asV2Read)
        }
    }

    private func setLastNagDate(_ date: Date) async {
        await databaseStorage.awaitableWrite { transaction in
            self.keyValueStore.setDate(date, key: AppUpdateNag.kLastNagDateKey, transaction: transaction.asV2Write)
        }
    }
}

// MARK: Parsing Structs

private struct AppStoreLookupResultSet: Codable {
    let resultCount: UInt
    let results: [AppStoreRecord]
}

private struct AppStoreRecord: Codable {
    let appStoreURL: URL
    let version: String

    private enum CodingKeys: String, CodingKey {
        case appStoreURL = "trackViewUrl"
        case version
    }
}
