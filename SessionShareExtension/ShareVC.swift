import SessionUIKit

final class ShareVC : UIViewController, UITableViewDataSource, AppModeManagerDelegate {
    @IBOutlet private var logoImageView: UIImageView!
    private var areVersionMigrationsComplete = false
    private var threads: YapDatabaseViewMappings!
    private var threadViewModelCache: [String:ThreadViewModel] = [:] // Thread ID to ThreadViewModel
    
    private var threadCount: UInt {
        threads.numberOfItems(inGroup: TSInboxGroup)
    }
    
    private lazy var dbConnection: YapDatabaseConnection = {
        let result = OWSPrimaryStorage.shared().newDatabaseConnection()
        result.objectCacheLimit = 500
        return result
    }()

    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(SimplifiedConversationCell.self, forCellReuseIdentifier: SimplifiedConversationCell.reuseIdentifier)
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
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
        // Gradient
        view.backgroundColor = .clear
        let gradient = Gradients.defaultBackground
        view.setGradient(gradient)
        // Threads
        dbConnection.beginLongLivedReadTransaction() // Freeze the connection for use on the main thread (this gives us a stable data source that doesn't change until we tell it to)
        threads = YapDatabaseViewMappings(groups: [ TSInboxGroup ], view: TSThreadDatabaseViewExtensionName) // The extension should be registered at this point
        threads.setIsReversed(true, forGroup: TSInboxGroup)
        dbConnection.read { transaction in
            self.threads.update(with: transaction) // Perform the initial update
        }
        // Logo
        logoImageView.alpha = 0
        // Fake nav bar
        let fakeNavBar = UIView()
        fakeNavBar.set(.height, to: 64)
        view.addSubview(fakeNavBar)
        fakeNavBar.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: view)
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("share", comment: "")
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        fakeNavBar.addSubview(titleLabel)
        titleLabel.center(in: fakeNavBar)
        // Table view
        tableView.dataSource = self
        view.addSubview(tableView)
        tableView.pin(.top, to: .bottom, of: fakeNavBar)
        tableView.pin([ UIView.HorizontalEdge.left, UIView.HorizontalEdge.right, UIView.VerticalEdge.bottom ], to: view)
        // Reload
        reload()
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
    
    // MARK: Table View Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(threadCount)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SimplifiedConversationCell.reuseIdentifier) as! SimplifiedConversationCell
        cell.threadViewModel = threadViewModel(at: indexPath.row)
        return cell
    }
    
    // MARK: Updating
    private func reload() {
        AssertIsOnMainThread()
        dbConnection.beginLongLivedReadTransaction() // Jump to the latest commit
        dbConnection.read { transaction in
            self.threads.update(with: transaction)
        }
        threadViewModelCache.removeAll()
        tableView.reloadData()
    }
    
    // MARK: Convenience
    private func thread(at index: Int) -> TSThread? {
        var thread: TSThread? = nil
        dbConnection.read { transaction in
            let ext = transaction.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewTransaction
            thread = ext.object(atRow: UInt(index), inSection: 0, with: self.threads) as! TSThread?
        }
        return thread
    }
    
    private func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard let thread = thread(at: index) else { return nil }
        if let cachedThreadViewModel = threadViewModelCache[thread.uniqueId!] {
            return cachedThreadViewModel
        } else {
            var threadViewModel: ThreadViewModel? = nil
            dbConnection.read { transaction in
                threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            threadViewModelCache[thread.uniqueId!] = threadViewModel
            return threadViewModel
        }
    }
}
