//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public class SUIEnvironment: NSObject {

    private static var _shared: SUIEnvironment = SUIEnvironment()

    public class var shared: SUIEnvironment {
        get {
            return _shared
        }
        set {
            guard CurrentAppContext().isRunningTests else {
                owsFailDebug("Can only switch environments in tests.")
                return
            }

            _shared = newValue
        }
    }

    public var audioSessionRef: AudioSession = AudioSession()

    public var contactsViewHelperRef: ContactsViewHelper = ContactsViewHelper()

    public var paymentsRef: Payments!
    /// This should be deprecated.
    public var paymentsSwiftRef: PaymentsSwift { paymentsRef as! PaymentsSwift }
    public var paymentsImplRef: PaymentsImpl { paymentsRef as! PaymentsImpl }

    private(set) public var linkPreviewFetcher: (any LinkPreviewFetcher)!

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    @MainActor
    public func setUp(
        appReadiness: AppReadiness,
        authCredentialManager: any AuthCredentialManager
    ) {
        registerCustomFonts()

        Theme.performInitialSetup(appReadiness: appReadiness)

        self.linkPreviewFetcher = LinkPreviewFetcherImpl(
            authCredentialManager: authCredentialManager,
            db: DependenciesBridge.shared.db,
            groupsV2: SSKEnvironment.shared.groupsV2Ref,
            linkPreviewSettingStore: DependenciesBridge.shared.linkPreviewSettingStore,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.paymentsRef = PaymentsImpl(appReadiness: appReadiness)

        contactsViewHelperRef.performInitialSetup(appReadiness: appReadiness)
        audioSessionRef.performInitialSetup(appReadiness: appReadiness)
    }

    private func registerCustomFonts() {
        let bundle = Bundle(for: type(of: self))
        guard
            let ttfFontURLs = bundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
            let otfFontURLs = bundle.urls(forResourcesWithExtension: "otf", subdirectory: nil)
        else {
            return owsFailDebug("Failed to load fonts from bundle.")
        }
        for url in ttfFontURLs + otfFontURLs {
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                let errorMessage = (error?.takeRetainedValue()).map { String(describing: $0) } ?? "(unknown error)"
                owsFailDebug("Could not register font with url \(url): \(errorMessage)")
                continue
            }
        }
    }
}
