//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension Notification.Name {
    public static let isCensorshipCircumventionActiveDidChange = Notification.Name("NSNotificationNameIsCensorshipCircumventionActiveDidChange")
}

public class OWSSignalService: OWSSignalServiceProtocol {
    private let keyValueStore = KeyValueStore(collection: "kTSStorageManager_OWSSignalService")
    private let libsignalNet: Net?

    @Atomic public private(set) var isCensorshipCircumventionActive: Bool = false {
        didSet {
            guard isCensorshipCircumventionActive != oldValue else {
                return
            }

            // Update libsignal's Net instance first, so that connections can be recreated by notification observers.
            libsignalNet?.setCensorshipCircumventionEnabled(isCensorshipCircumventionActive)

            NotificationCenter.default.postOnMainThread(
                name: .isCensorshipCircumventionActiveDidChange,
                object: nil,
                userInfo: nil,
            )
        }
    }

    @Atomic public private(set) var hasCensoredPhoneNumber: Bool = false

    private let isCensorshipCircumventionManuallyActivatedLock = UnfairLock()

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

    private let isCensorshipCircumventionManuallyDisabledLock = UnfairLock()

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

    private let manualCensorshipCircumventionCountryCodeLock = UnfairLock()

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

    private struct CensorshipConfigurationParams: Hashable {
        enum CountryId: Hashable {
            case manualCountryCode(String)
            case localE164(String)
        }

        // Nil means use default configuration
        let countryId: CountryId?

        static var `default`: Self {
            .init(countryId: nil)
        }

        func build() -> OWSCensorshipConfiguration {
            switch countryId {
            case nil:
                return .defaultConfiguration
            case .manualCountryCode(let countryCode):
                return OWSCensorshipConfiguration.censorshipConfiguration(countryCode: countryCode)
            case .localE164(let localNumber):
                return OWSCensorshipConfiguration.censorshipConfiguration(e164: localNumber)
                    ?? .defaultConfiguration
            }
        }
    }

    // Returns nil if CC not active
    private func censorshipConfigurationParamsWithMaybeSneakyTransaction(
        censorshipCircumventionSupportedForService: Bool,
    ) -> CensorshipConfigurationParams? {
        guard self.isCensorshipCircumventionActive, censorshipCircumventionSupportedForService else {
            return nil
        }
        if self.isCensorshipCircumventionManuallyActivated {
            guard
                let countryCode = self.manualCensorshipCircumventionCountryCode,
                !countryCode.isEmpty
            else {
                owsFailDebug("manualCensorshipCircumventionCountryCode was unexpectedly 0")
                return .default
            }
            return CensorshipConfigurationParams(countryId: .manualCountryCode(countryCode))
        }
        guard
            let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
        else {
            return .default
        }
        return CensorshipConfigurationParams(countryId: .localE164(localNumber))
    }

    public func buildUrlEndpoint(for signalServiceInfo: SignalServiceInfo) -> OWSURLSessionEndpoint {
        return buildUrlEndpoint(
            censorshipConfigurationParams: self.censorshipConfigurationParamsWithMaybeSneakyTransaction(
                censorshipCircumventionSupportedForService: signalServiceInfo.censorshipCircumventionSupported,
            ),
            baseUrl: signalServiceInfo.baseUrl,
            censorshipCircumventionPathPrefix: signalServiceInfo.censorshipCircumventionPathPrefix,
            shouldUseSignalCertificate: signalServiceInfo.shouldUseSignalCertificate,
        )
    }

    private func buildUrlEndpoint(
        censorshipConfigurationParams: CensorshipConfigurationParams?,
        baseUrl: URL,
        censorshipCircumventionPathPrefix: String,
        shouldUseSignalCertificate: Bool,
    ) -> OWSURLSessionEndpoint {
        // If there's an open transaction when this is called, and if censorship
        // circumvention is enabled, `buildCensorshipConfiguration()` will crash.
        // Add a database read here so that we crash in both `if` branches.
        assert({
            SSKEnvironment.shared.databaseStorageRef.read { _ in }
            return true
        }(), "Must not have open transaction.")

        if let censorshipConfigurationParams {
            let censorshipConfiguration = censorshipConfigurationParams.build()
            let frontingURLWithoutPathPrefix = censorshipConfiguration.domainFrontBaseUrl
            let frontingURLWithPathPrefix = frontingURLWithoutPathPrefix.appendingPathComponent(censorshipCircumventionPathPrefix)
            let frontingInfo = OWSUrlFrontingInfo(
                frontingURLWithoutPathPrefix: frontingURLWithoutPathPrefix,
                frontingURLWithPathPrefix: frontingURLWithPathPrefix,
            )
            let baseUrl = frontingURLWithPathPrefix
            let securityPolicy = censorshipConfiguration.domainFrontSecurityPolicy
            let extraHeaders: HttpHeaders = ["Host": censorshipConfiguration.reflectorHost()]
            return OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: frontingInfo,
                securityPolicy: securityPolicy,
                extraHeaders: extraHeaders,
            )
        } else {
            let baseUrl = baseUrl
            let securityPolicy: HttpSecurityPolicy
            if shouldUseSignalCertificate {
                securityPolicy = OWSURLSession.signalServiceSecurityPolicy
            } else {
                securityPolicy = OWSURLSession.defaultSecurityPolicy
            }
            return OWSURLSessionEndpoint(
                baseUrl: baseUrl,
                frontingInfo: nil,
                securityPolicy: securityPolicy,
                extraHeaders: [:],
            )
        }
    }

    public func buildUrlSession(
        for signalServiceInfo: SignalServiceInfo,
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?,
    ) -> OWSURLSessionProtocol {
        return buildUrlSession(
            endpoint: endpoint,
            configuration: configuration,
            maxResponseSize: maxResponseSize,
            shouldHandleRemoteDeprecation: signalServiceInfo.shouldHandleRemoteDeprecation,
            onFailureCallback: nil,
        )
    }

    private func buildUrlSession(
        endpoint: OWSURLSessionEndpoint,
        configuration: URLSessionConfiguration?,
        maxResponseSize: Int?,
        shouldHandleRemoteDeprecation: Bool,
        onFailureCallback: ((any Error) -> Void)?,
    ) -> OWSURLSessionProtocol {
        let urlSession = OWSURLSession(
            endpoint: endpoint,
            configuration: configuration ?? OWSURLSession.defaultConfigurationWithoutCaching,
            maxResponseSize: maxResponseSize,
            canUseSignalProxy: endpoint.frontingInfo == nil,
            onFailureCallback: onFailureCallback,
        )
        urlSession.shouldHandleRemoteDeprecation = shouldHandleRemoteDeprecation
        return urlSession
    }

    // MARK: - CDN

    private actor CDNSessionCache {
        struct Key: Hashable {
            let cdnNumber: UInt32
            let maxResponseSize: UInt?
            let ccParams: CensorshipConfigurationParams?
        }

        private var cache = [Key: OWSURLSessionProtocol]()

        func getOrBuildSession(
            key: Key,
            buildFn: () -> OWSURLSessionProtocol,
        ) -> OWSURLSessionProtocol {
            if let cached = cache[key] {
                return cached
            }
            let session = buildFn()
            cache[key] = session
            return session
        }

        func invalidate(key: Key) {
            cache[key] = nil
        }

        func reset() {
            cache.removeAll()
        }
    }

    private let cdnSessionCache = CDNSessionCache()

    public func sharedUrlSessionForCdn(
        cdnNumber: UInt32,
        maxResponseSize: UInt?,
    ) async -> OWSURLSessionProtocol {
        let ccParams = self.censorshipConfigurationParamsWithMaybeSneakyTransaction(
            censorshipCircumventionSupportedForService: true,
        )
        let cacheKey = CDNSessionCache.Key(
            cdnNumber: cdnNumber,
            maxResponseSize: maxResponseSize,
            ccParams: ccParams,
        )
        return await cdnSessionCache.getOrBuildSession(
            key: cacheKey,
            buildFn: {
                let urlSessionConfiguration = OWSURLSession.defaultConfigurationWithoutCaching
                urlSessionConfiguration.timeoutIntervalForRequest = 600

                let baseUrl: URL
                let censorshipCircumventionPathPrefix: String
                switch cdnNumber {
                case 0:
                    baseUrl = URL(string: TSConstants.textSecureCDN0ServerURL)!
                    censorshipCircumventionPathPrefix = TSConstants.cdn0CensorshipPrefix
                case 2:
                    baseUrl = URL(string: TSConstants.textSecureCDN2ServerURL)!
                    censorshipCircumventionPathPrefix = TSConstants.cdn2CensorshipPrefix
                case 3:
                    baseUrl = URL(string: TSConstants.textSecureCDN3ServerURL)!
                    censorshipCircumventionPathPrefix = TSConstants.cdn3CensorshipPrefix
                default:
                    owsFailDebug("Unrecognized CDN number configuration requested: \(cdnNumber)")
                    // Fallback to cdn2
                    baseUrl = URL(string: TSConstants.textSecureCDN2ServerURL)!
                    censorshipCircumventionPathPrefix = TSConstants.cdn2CensorshipPrefix
                }

                return self.buildUrlSession(
                    endpoint: self.buildUrlEndpoint(
                        censorshipConfigurationParams: ccParams,
                        baseUrl: baseUrl,
                        censorshipCircumventionPathPrefix: censorshipCircumventionPathPrefix,
                        shouldUseSignalCertificate: true,
                    ),
                    configuration: urlSessionConfiguration,
                    maxResponseSize: maxResponseSize.map(Int.init(clamping:)),
                    shouldHandleRemoteDeprecation: false,
                    onFailureCallback: { [weak self] error in
                        Task {
                            if error.isNetworkFailure {
                                // Invalidate the cache on any network failure so
                                // that next time we create a new session which will
                                // re-randomize SNI headers.
                                await self?.cdnSessionCache.invalidate(key: cacheKey)
                            }
                        }
                    },
                )
            },
        )
    }

    // MARK: - Internal Implementation

    public init(libsignalNet: Net?) {
        self.libsignalNet = libsignalNet
        observeNotifications()
    }

    // MARK: Setup

    public func warmCaches() {
        updateHasCensoredPhoneNumber()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange(_:)),
            name: .registrationStateDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(localNumberDidChange(_:)),
            name: .localNumberDidChange,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(isSignalProxyReadyDidChange),
            name: .isSignalProxyReadyDidChange,
            object: nil,
        )
    }

    private func updateHasCensoredPhoneNumber() {
        updateHasCensoredPhoneNumber(DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber)
    }

    public func updateHasCensoredPhoneNumberDuringProvisioning(_ e164: E164) {
        updateHasCensoredPhoneNumber(e164.stringValue)
    }

    public func resetHasCensoredPhoneNumberFromProvisioning() {
        self.hasCensoredPhoneNumber = false
        updateIsCensorshipCircumventionActive()
    }

    private func updateHasCensoredPhoneNumber(_ localNumber: String?) {
        if let localNumber {
            self.hasCensoredPhoneNumber = OWSCensorshipConfiguration.isCensored(e164: localNumber)
        } else {
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
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyActivatedKey,
                defaultValue: false,
                transaction: transaction,
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyActivated(_ value: Bool) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyActivatedKey,
                transaction: transaction,
            )
        }
    }

    private func readIsCensorshipCircumventionManuallyDisabled() -> Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getBool(
                Constants.isCensorshipCircumventionManuallyDisabledKey,
                defaultValue: false,
                transaction: transaction,
            )
        }
    }

    private func writeIsCensorshipCircumventionManuallyDisabled(_ value: Bool) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setBool(
                value,
                key: Constants.isCensorshipCircumventionManuallyDisabledKey,
                transaction: transaction,
            )
        }
    }

    private func readCensorshipCircumventionCountryCode() -> String? {
        return SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return self.keyValueStore.getString(
                Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction,
            )
        }
    }

    private func writeManualCensorshipCircumventionCountryCode(_ value: String?) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.keyValueStore.setString(
                value,
                key: Constants.manualCensorshipCircumventionCountryCodeKey,
                transaction: transaction,
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
        self.updateIsCensorshipCircumventionActive()
        Task {
            await cdnSessionCache.reset()
        }
    }

    // MARK: - Constants

    private enum Constants {
        static let isCensorshipCircumventionManuallyActivatedKey = "kTSStorageManager_isCensorshipCircumventionManuallyActivated"
        static let isCensorshipCircumventionManuallyDisabledKey = "kTSStorageManager_isCensorshipCircumventionManuallyDisabled"
        static let manualCensorshipCircumventionCountryCodeKey = "kTSStorageManager_ManualCensorshipCircumventionCountryCode"
    }
}
