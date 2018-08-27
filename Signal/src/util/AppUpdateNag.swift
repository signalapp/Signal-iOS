//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
class AppUpdateNag: NSObject {

    // MARK: Public

    @objc(sharedInstance)
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
        }.then { appStoreRecord -> Void in
            guard appStoreRecord.version.compare(currentVersion, options: .numeric) == ComparisonResult.orderedDescending else {
                Logger.debug("remote version: \(appStoreRecord) is not newer than currentVersion: \(currentVersion)")
                return
            }

            Logger.info("new version available: \(appStoreRecord)")
            self.showUpdateNagIfEnoughTimeHasPassed(appStoreRecord: appStoreRecord)
        }.catch { error in
            Logger.error("failed with error: \(error)")
        }.retainUntilComplete()
    }

    // MARK: - Internal

    let kUpgradeNagCollection = "TSStorageManagerAppUpgradeNagCollection"
    let kLastNagDateKey = "TSStorageManagerAppUpgradeNagDate"
    let kFirstHeardOfNewVersionDateKey = "TSStorageManagerAppUpgradeFirstHeardOfNewVersionDate"

    var dbConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadWriteConnection
    }

    // MARK: Bundle accessors

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

        // Only show nag if we are "at rest" in the home view or registration view without any
        // alerts or dialogs showing.
        guard let frontmostViewController = UIApplication.shared.frontmostViewController else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }

        switch frontmostViewController {
        case is HomeViewController, is RegistrationViewController:
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

        let alert = UIAlertController(title: title, message: bodyText, preferredStyle: .alert)

        let updateAction = UIAlertAction(title: updateButtonText, style: .default) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.showAppStore(appStoreURL: appStoreRecord.appStoreURL)
        }

        alert.addAction(updateAction)
        alert.addAction(UIAlertAction(title: dismissButtonText, style: .cancel, handler: nil))

        OWSAlerts.showAlert(alert)
    }

    func showAppStore(appStoreURL: URL) {
        Logger.debug("")
        UIApplication.shared.openURL(appStoreURL)
    }

    // MARK: Storage

    var firstHeardOfNewVersionDate: Date? {
        return self.dbConnection.date(forKey: kFirstHeardOfNewVersionDateKey, inCollection: kUpgradeNagCollection)
    }

    func setFirstHeardOfNewVersionDate(_ date: Date) {
        self.dbConnection.setDate(date, forKey: kFirstHeardOfNewVersionDateKey, inCollection: kUpgradeNagCollection)
    }

    func clearFirstHeardOfNewVersionDate() {
        self.dbConnection.removeObject(forKey: kFirstHeardOfNewVersionDateKey, inCollection: kUpgradeNagCollection)
    }

    var lastNagDate: Date? {
        return self.dbConnection.date(forKey: kLastNagDateKey, inCollection: kUpgradeNagCollection)
    }

    func setLastNagDate(_ date: Date) {
        self.dbConnection.setDate(date, forKey: kLastNagDateKey, inCollection: kUpgradeNagCollection)
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

        let (promise, fulfill, reject) = Promise<AppStoreRecord>.pending()

        let task = URLSession.ephemeral.dataTask(with: lookupURL) { (data, _, error) in
            guard let data = data else {
                Logger.warn("data was unexpectedly nil")
                reject(OWSErrorMakeUnableToProcessServerResponseError())
                return
            }

            do {
                let decoder = JSONDecoder()
                let resultSet = try decoder.decode(AppStoreLookupResultSet.self, from: data)
                guard let appStoreRecord = resultSet.results.first else {
                    Logger.warn("record was unexpectedly nil")
                    reject(OWSErrorMakeUnableToProcessServerResponseError())
                    return
                }

                fulfill(appStoreRecord)
            } catch {
                reject(error)
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
