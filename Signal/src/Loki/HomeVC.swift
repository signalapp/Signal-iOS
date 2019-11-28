
public final class HomeVC : UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var threadViewModelCache: [String:ThreadViewModel] = [:]
    
    private var threads: YapDatabaseViewMappings = {
        let result = YapDatabaseViewMappings(groups: [ TSInboxGroup ], view: TSThreadDatabaseViewExtensionName)
        result.setIsReversed(true, forGroup: TSInboxGroup)
        return result
    }()
    
    private let uiDatabaseConnection: YapDatabaseConnection = {
        let result = OWSPrimaryStorage.shared().newDatabaseConnection()
        result.objectCacheLimit = 500
        return result
    }()
    
    // MARK: Settings
    public override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Components
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        return result
    }()
    
    // MARK: Lifecycle
    public override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Customize title
        navigationItem.title = NSLocalizedString("Messages", comment: "")
        navigationController?.navigationBar.titleTextAttributes = [ .foregroundColor : Colors.text, .font : UIFont.boldSystemFont(ofSize: Values.veryLargeFontSize) ]
        // Set up table view
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.pin(to: view)
        // Do initial update
        uiDatabaseConnection.beginLongLivedReadTransaction()
        uiDatabaseConnection.read { transaction in
            self.threads.update(with: transaction)
        }
        tableView.reloadData()
    }
    
    // MARK: Data
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(threads.numberOfItems(inGroup: TSInboxGroup))
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
        cell.threadViewModel = threadViewModel(at: indexPath.row)
        return cell
    }
    
    // MARK: Convenience
    private func thread(at index: Int) -> TSThread? {
        var thread: TSThread? = nil
        uiDatabaseConnection.read { transaction in
            thread = ((transaction as YapDatabaseReadTransaction).ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewTransaction).object(atRow: UInt(index), inSection: 0, with: self.threads) as! TSThread?
        }
        return thread
    }
    
    private func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard let thread = thread(at: index) else { return nil }
        if let cachedThreadViewModel = threadViewModelCache[thread.uniqueId!] {
            return cachedThreadViewModel
        } else {
            var threadViewModel: ThreadViewModel? = nil
            uiDatabaseConnection.read { transaction in
                threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            threadViewModelCache[thread.uniqueId!] = threadViewModel
            return threadViewModel
        }
    }
}
