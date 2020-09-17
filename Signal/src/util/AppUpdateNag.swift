//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
class AppUpdateNag: NSObject {

    // MARK: Public

    @objc(shared)
    public static let shared: AppUpdateNag = {
        let versionService = AppStoreVersionService()
        let nagManager = AppUpdateNag(versionService: versionService)
        return nagManager
    }()

    @objc
    public func showAppUpgradeNagIfNecessary() {

        guard let currentVersion = self.currentVersion else {
            owsFailDebug("currentVersion was unexpectedly nil")
            return
        }

        guard let bundleIdentifier = self.bundleIdentifier else {
            owsFailDebug("bundleIdentifier was unexpectedly nil")
            return
        }

        guard let lookupURL = lookupURL(bundleIdentifier: bundleIdentifier) else {
            owsFailDebug("appStoreURL was unexpectedly nil")
            return
        }

        firstly {
            self.versionService.fetchLatestVersion(lookupURL: lookupURL)
        }.done { appStoreRecord in
            guard appStoreRecord.version.compare(currentVersion, options: .numeric) == ComparisonResult.orderedDescending else {
                Logger.debug("remote version: \(appStoreRecord) is not newer than currentVersion: \(currentVersion)")
                return
            }

            Logger.info("new version available: \(appStoreRecord)")
            self.showUpdateNagIfEnoughTimeHasPassed(appStoreRecord: appStoreRecord)
        }.catch { error in
            Logger.warn("failed with error: \(error)")
        }
    }

    // MARK: - Internal

    static let kLastNagDateKey = "TSStorageManagerAppUpgradeNagDate"
    static let kFirstHeardOfNewVersionDateKey = "TSStorageManagerAppUpgradeFirstHeardOfNewVersionDate"

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - KV Store

    @objc
    public let keyValueStore = SDSKeyValueStore(collection: "TSStorageManagerAppUpgradeNagCollection")

    // MARK: - Bundle accessors

    var bundle: Bundle {
        return Bundle.main
    }

    var currentVersion: String? {
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var bundleIdentifier: String? {
        return bundle.bundleIdentifier
    }

    func lookupURL(bundleIdentifier: String) -> URL? {
        return URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleIdentifier)")
    }

    let versionService: AppStoreVersionService

    required init(versionService: AppStoreVersionService) {
        self.versionService = versionService
        super.init()

        SwiftSingletons.register(self)
    }

    func showUpdateNagIfEnoughTimeHasPassed(appStoreRecord: AppStoreRecord) {
        guard let firstHeardOfNewVersionDate = self.firstHeardOfNewVersionDate else {
            self.setFirstHeardOfNewVersionDate(Date())
            return
        }

        let intervalBeforeNag = 7 * kDayInterval
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
        case is ConversationSplitViewController, is OnboardingSplashViewController:
            self.setLastNagDate(Date())
            self.clearFirstHeardOfNewVersionDate()
            presentUpgradeNag(appStoreRecord: appStoreRecord)
        default:
            Logger.debug("not presenting alert due to frontmostViewController: \(frontmostViewController)")
            break
        }
    }

    func presentUpgradeNag(appStoreRecord: AppStoreRecord) {
        let title = NSLocalizedString("APP_UPDATE_NAG_ALERT_TITLE", comment: "Title for the 'new app version available' alert.")

        let bodyFormat = NSLocalizedString("APP_UPDATE_NAG_ALERT_MESSAGE_FORMAT", comment: "Message format for the 'new app version available' alert. Embeds: {{The latest app version number}}")
        let bodyText = String(format: bodyFormat, appStoreRecord.version)
        let updateButtonText = NSLocalizedString("APP_UPDATE_NAG_ALERT_UPDATE_BUTTON", comment: "Label for the 'update' button in the 'new app version available' alert.")
        let dismissButtonText = NSLocalizedString("APP_UPDATE_NAG_ALERT_DISMISS_BUTTON", comment: "Label for the 'dismiss' button in the 'new app version available' alert.")

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

    func showAppStore(appStoreURL: URL) {
        assert(CurrentAppContext().isMainApp)

        Logger.debug("")

        UIApplication.shared.open(appStoreURL, options: [:])
    }

    // MARK: Storage

    var firstHeardOfNewVersionDate: Date? {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getDate(AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction)
        }
    }

    func setFirstHeardOfNewVersionDate(_ date: Date) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setDate(date, key: AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction)
        }
    }

    func clearFirstHeardOfNewVersionDate() {
        self.databaseStorage.write { transaction in
            self.keyValueStore.removeValue(forKey: AppUpdateNag.kFirstHeardOfNewVersionDateKey, transaction: transaction)
        }
    }

    var lastNagDate: Date? {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getDate(AppUpdateNag.kLastNagDateKey, transaction: transaction)
        }
    }

    func setLastNagDate(_ date: Date) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setDate(date, key: AppUpdateNag.kLastNagDateKey, transaction: transaction)
        }
    }
}

// MARK: Parsing Structs

struct AppStoreLookupResultSet: Codable {
    let resultCount: UInt
    let results: [AppStoreRecord]
}

struct AppStoreRecord: Codable {
    let appStoreURL: URL
    let version: String

    private enum CodingKeys: String, CodingKey {
        case appStoreURL = "trackViewUrl"
        case version
    }
}

class AppStoreVersionService: NSObject {

    // MARK: 

    func fetchLatestVersion(lookupURL: URL) -> Promise<AppStoreRecord> {
        Logger.debug("lookupURL:\(lookupURL)")

        let (promise, resolver) = Promise<AppStoreRecord>.pending()

        let task = URLSession.ephemeral.dataTask(with: lookupURL) { (data, _, networkError) in
            if let networkError = networkError {
                return resolver.reject(networkError)
            }

            guard let data = data else {
                Logger.warn("data was unexpectedly nil")
                resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                return
            }

            do {
                let decoder = JSONDecoder()
                let resultSet = try decoder.decode(AppStoreLookupResultSet.self, from: data)
                guard let appStoreRecord = resultSet.results.first else {
                    Logger.warn("record was unexpectedly nil")
                    resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                    return
                }

                resolver.fulfill(appStoreRecord)
            } catch {
                resolver.reject(error)
            }
        }

        task.resume()

        return promise
    }
}

extension URLSession {
    static var ephemeral: URLSession {
        return URLSession(configuration: .ephemeral)
    }
}
