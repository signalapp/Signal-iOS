import SessionUIKit

final class ShareVC : UIViewController, AppModeManagerDelegate {
    private var areVersionMigrationsComplete = false

    // MARK: Lifecycle
    override func loadView() {
        super.loadView()

        // This should be the first thing we do.
        let appContext = ShareAppExtensionContext(rootViewController: self)
        SetCurrentAppContext(appContext)

        AppModeManager.configure(delegate: self)

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.sharedInstance()

        Cryptography.seedRandom()

        // We don't need to use DeviceSleepManager in the SAE.

        // We don't need to use applySignalAppearence in the SAE.

        if CurrentAppContext().isRunningTests {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        AppSetup.setupEnvironment(appSpecificSingletonBlock: {
            SSKEnvironment.shared.notificationsManager = NoopNotificationsManager()
        }, migrationCompletion: { [weak self] in
            AssertIsOnMainThread()

            guard let strongSelf = self else { return }

            // performUpdateCheck must be invoked after Environment has been initialized because
            // upgrade process may depend on Environment.
            strongSelf.versionMigrationsDidComplete()
        })

        // We don't need to use "screen protection" in the SAE.

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storageIsReady),
                                               name: .StorageIsReady,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
    }

    @objc
    func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        Logger.debug("")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    func storageIsReady() {
        AssertIsOnMainThread()

        Logger.debug("")

        checkIsAppReady()
    }

    @objc
    func checkIsAppReady() {
        AssertIsOnMainThread()

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard areVersionMigrationsComplete else {
            return
        }
        guard OWSStorage.isStorageReady() else {
            return
        }
        guard !AppReadiness.isAppReady() else {
            // Only mark the app as ready once.
            return
        }

        SignalUtilitiesKit.Configuration.performMainSetup()

        Logger.debug("")

        // TODO: Once "app ready" logic is moved into AppSetup, move this line there.
        OWSProfileManager.shared().ensureLocalProfileCached()

        // Note that this does much more than set a flag;
        // it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        // We don't need to use messageFetcherJob in the SAE.

        // We don't need to use SyncPushTokensJob in the SAE.

        // We don't need to use DeviceSleepManager in the SAE.

        AppVersion.sharedInstance().saeLaunchDidComplete()

        setUpViewHierarchy()

        // We don't need to use OWSMessageReceiver in the SAE.
        // We don't need to use OWSBatchMessageProcessor in the SAE.

        OWSProfileManager.shared().ensureLocalProfileCached()

        // We don't need to use OWSOrphanDataCleaner in the SAE.

        // We don't need to fetch the local profile in the SAE

        OWSReadReceiptManager.shared().prepareCachedValues()
    }

    private func setUpViewHierarchy() {
        
    }

    @objc
    public func applicationDidEnterBackground() {
        AssertIsOnMainThread()

        Logger.info("")

        if OWSScreenLock.shared.isScreenLockEnabled() {

            self.dismiss(animated: false) { [weak self] in
                AssertIsOnMainThread()
                guard let strongSelf = self else { return }
                strongSelf.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)

        // Share extensions reside in a process that may be reused between usages.
        // That isn't safe; the codebase is full of statics (e.g. singletons) which
        // we can't easily clean up.
        ExitShareExtension()
    }

    // MARK: App Mode

    public func getCurrentAppMode() -> AppMode {
        guard let window = self.view.window else { return .light }
        let userInterfaceStyle = window.traitCollection.userInterfaceStyle
        let isLightMode = (userInterfaceStyle == .light || userInterfaceStyle == .unspecified)
        return isLightMode ? .light : .dark
    }

    public func setCurrentAppMode(to appMode: AppMode) {
        return // Not applicable to share extensions
    }
}
