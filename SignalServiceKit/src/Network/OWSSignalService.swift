//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Notification.Name {
    public static var isCensorshipCircumventionActiveDidChange: Self {
        return .init(rawValue: OWSSignalService.isCensorshipCircumventionActiveDidChangeNotificationName)
    }
}

@objc
public class OWSSignalService: NSObject, OWSSignalServiceProtocol {

    // MARK: - Protocol Conformance

    @objc
    public let keyValueStore = SDSKeyValueStore(collection: "kTSStorageManager_OWSSignalService")

    @objc
    public static var isCensorshipCircumventionActiveDidChangeNotificationName: String {
        return "NSNotificationNameIsCensorshipCircumventionActiveDidChange"
    }

    @Atomic
    public private(set) var isCensorshipCircumventionActive: Bool = false {
        didSet {
            guard isCensorshipCircumventionActive != oldValue else {
                return
            }
            NotificationCenter.default.postNotificationNameAsync(
                .isCensorshipCircumventionActiveDidChange,
                object: nil,
                userInfo: nil
            )
        }
    }

    @objc
    @Atomic
    public private(set) var hasCensoredPhoneNumber: Bool = false

    @objc
    private let isCensorshipCircumventionManuallyActivatedLock = UnfairLock()

    @objc
    public var isCensorshipCircumventionManuallyActivated: Bool {
        get {
            isCensorshipCircumventionManuallyActivatedLock.withLock {
                readIsCensorshipCircumventionManuallyActivated()
            }
        }
        set {
            isCensorshipCircumventionManuallyActivatedLock.withLock {
                writeIsCensorshipCircumventionManuallyActivated(newValue)
            }
            updateIsCensorshipCircumventionActive()
        }
    }

    @objc
    private let isCensorshipCircumventionManuallyDisabledLock = UnfairLock()

    @objc
    public var isCensorshipCircumventionManuallyDisabled: Bool {
        get {
            isCensorshipCircumventionManuallyDisabledLock.withLock {
                readIsCensorshipCircumventionManuallyDisabled()
            }
        }
        set {
            isCensorshipCircumventionManuallyDisabledLock.withLock {
                writeIsCensorshipCircumventionManuallyDisabled(newValue)
            }
            updateIsCensorshipCircumventionActive()
        }
    }

    @objc
    private let manualCensorshipCircumventionCountryCodeLock = UnfairLock()

    @objc
    public var manualCensorshipCircumventionCountryCode: String? {
        get {
            manualCensorshipCircumventionCountryCodeLock.withLock {
                readCensorshipCircumventionCountryCode()
            }
        }
        set {
            manualCensorshipCircumventionCountryCodeLock.withLock {
                writeManualCensorshipCircumventionCountryCode(newValue)
            }
        }
    }

    @objc
    public var domainFrontBaseURL: URL {
        owsAssertDebug(self.isCensorshipCircumventionActive)
        return self.buildCensorshipConfiguration().domainFrontBaseURL
    }

    @objc
    public func buildCensorshipConfiguration() -> OWSCensorshipConfiguration {
        owsAssertDebug(self.isCensorshipCircumventionActive)

        if self.isCensorshipCircumventionManuallyActivated {
            guard
                let countryCode = self.manualCensorshipCircumventionCountryCode,
                !countryCode.isEmpty
            else {
                owsFailDebug("manualCensorshipCircumventionCountryCode was unexpectedly 0")
                return .default()
            }

            let configuration = OWSCensorshipConfiguration(countryCode: countryCode)

            return configuration
        }

        guard
            let localNumber = TSAccountManager.localNumber,
            let configuration = OWSCensorshipConfiguration(phoneNumber: localNumber)
        else {
            return .default()
        }
        return configuration
    }

    @objc
    public func typeUnsafe_buildUrlSession(for signalServiceType: Any) -> Any {
        let signalServiceInfo = (signalServiceType as! SignalServiceType).signalServiceInfo()
        let isCensorshipCircumventionActive = self.isCensorshipCircumventionActive
        let urlSession: OWSURLSessionProtocol
        if isCensorshipCircumventionActive {
            let censorshipConfiguration = buildCensorshipConfiguration()
            let frontingURLWithoutPathPrefix = censorshipConfiguration.domainFrontBaseURL
            let frontingPathPrefix = signalServiceInfo.censorshipCircumventionPathPrefix
            let frontingURLWithPathPrefix = frontingURLWithoutPathPrefix.appendingPathComponent(frontingPathPrefix)
            let unfrontedBaseUrl = signalServiceInfo.baseUrl
            let frontingInfo = OWSUrlFrontingInfo(
                frontingURLWithoutPathPrefix: frontingURLWithoutPathPrefix,
                frontingURLWithPathPrefix: frontingURLWithPathPrefix,
                unfrontedBaseUrl: unfrontedBaseUrl
            )
            let baseUrl = frontingURLWithPathPrefix
            let securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            let extraHeaders = ["Host": TSConstants.censorshipReflectorHost]
            urlSession = OWSURLSession(
                baseUrl: baseUrl,
                frontingInfo: frontingInfo,
                securityPolicy: securityPolicy,
                configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                extraHeaders: extraHeaders
            )
        } else {
            let baseUrl = signalServiceInfo.baseUrl
            let securityPolicy: OWSHTTPSecurityPolicy
            switch signalServiceType as! SignalServiceType {
            case .updates:
                securityPolicy = OWSURLSession.defaultSecurityPolicy
            default:
                securityPolicy = OWSURLSession.signalServiceSecurityPolicy
            }

            urlSession = OWSURLSession(
                baseUrl: baseUrl,
                securityPolicy: securityPolicy,
                configuration: OWSURLSession.defaultConfigurationWithoutCaching,
                extraHeaders: [:],
                canUseSignalProxy: true
            )
        }
        urlSession.shouldHandleRemoteDeprecation = signalServiceInfo.shouldHandleRemoteDeprecation
        return urlSession
    }

    // MARK: - Internal Implementation

    public override init() {
        super.init()

        observeNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Setup

    @objc
    public func warmCaches() {
        updateHasCensoredPhoneNumber()
        updateIsCensorshipCircumventionActive()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange(_:)),
            name: .registrationStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localNumberDidChange(_:)),
            name: .localNumberDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(isSignalProxyReadyDidChange),
            name: .isSignalProxyReadyDidChange,
            object: nil
        )
    }

    private func updateHasCensoredPhoneNumber() {
        let localNumber = TSAccountManager.localNumber

        if let localNumber = localNumber {
            self.hasCensoredPhoneNumber = OWSCensorshipConfiguration.isCensoredPhoneNumber(localNumber)
        } else {
            OWSLogger.error("no known phone number to check for censorship.")
            self.hasCensoredPhoneNumber = false
        }

        updateIsCensorshipCircumventionActive()
    }

    private func updateIsCensorshipCircumventionActive() {
        if SignalProxy.isEnabled {
            self.isCensorshipCircumventionActive = false
        } else if self.isCensorshipCircumventionManuallyDisabled {
            self.isCensorshipCircumventionActive = false
        } else if self.isCensorshipCircumventionManuallyActivated {
            self.isCensorshipCircumventionActive = true
        } else if self.hasCensoredPhoneNumber {
            self.isCensorshipCircumventionActive = true
        } else {
            self.isCensorshipCircumventionActive = false
        }
    }

    // MARK: - Database operations

    private func readIsCensorshipCircumventionManuallyActivated() -> Bool {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyActivatedKey,
                defaultValue: false,
                transaction: transaction
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyActivated(_ value: Bool) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyActivatedKey,
                transaction: transaction
            )
        }
    }

    private func readIsCensorshipCircumventionManuallyDisabled() -> Bool {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyDisabledKey,
                defaultValue: false,
                transaction: transaction
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyDisabled(_ value: Bool) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyDisabledKey,
                transaction: transaction
            )
        }
    }

    private func readCensorshipCircumventionCountryCode() -> String? {
        return self.databaseStorage.read { transaction in
            return self.keyValueStore.getString(
                Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction
            )
        }
    }

    private func writeManualCensorshipCircumventionCountryCode(_ value: String?) {
        self.databaseStorage.write { transaction in
            self.keyValueStore.setString(
                value,
                key: Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction
            )
        }
    }

    // MARK: - Events

    @objc
    private func registrationStateDidChange(_ notification: NSNotification) {
        self.updateHasCensoredPhoneNumber()
    }

    @objc
    private func localNumberDidChange(_ notification: NSNotification) {
        self.updateHasCensoredPhoneNumber()
    }

    @objc
    private func isSignalProxyReadyDidChange() {
        updateHasCensoredPhoneNumber()
    }

    // MARK: - Constants

    private enum Constants {
        static let isCensorshipCircumventionManuallyActivatedKey = "kTSStorageManager_isCensorshipCircumventionManuallyActivated"
        static let isCensorshipCircumventionManuallyDisabledKey = "kTSStorageManager_isCensorshipCircumventionManuallyDisabled"
        static let manualCensorshipCircumventionCountryCodeKey = "kTSStorageManager_ManualCensorshipCircumventionCountryCode"
    }
}

private enum SerializerType {
    case json
    case binary
}
