import SessionUIKit

final class ThreadPickerVC : UIViewController, UITableViewDataSource, UITableViewDelegate, AttachmentApprovalViewControllerDelegate {
    private var threads: YapDatabaseViewMappings!
    private var threadViewModelCache: [String:ThreadViewModel] = [:] // Thread ID to ThreadViewModel
    private var selectedThread: TSThread?
    var shareVC: ShareVC?
    
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
    
    private lazy var fadeView: UIView = {
        let result = UIView()
        let gradient = Gradients.homeVCFade
        result.setGradient(gradient)
        result.isUserInteractionEnabled = false
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
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
        // Title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("vc_share_title", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Table view
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.pin(to: view)
        view.addSubview(fadeView)
        fadeView.pin(.leading, to: .leading, of: view)
        let topInset = 0.15 * view.height()
        fadeView.pin(.top, to: .top, of: view, withInset: topInset)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
        // Reload
        reload()
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
    
    // MARK: Interaction
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let thread = self.thread(at: indexPath.row), let attachments = ShareVC.attachmentPrepPromise?.value else { return }
        self.selectedThread = thread
        tableView.deselectRow(at: indexPath, animated: true)
        let approvalVC = AttachmentApprovalViewController.wrappedInNavController(attachments: attachments, approvalDelegate: self)
        navigationController!.present(approvalVC, animated: true, completion: nil)
    }
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        shareVC?.showLoader()
        let message = VisibleMessage()
        message.sentTimestamp = NSDate.millisecondTimestamp()
        message.text = messageText
        let tsMessage = TSOutgoingMessage.from(message, associatedWith: selectedThread!)
        Storage.write { transaction in
            tsMessage.save(with: transaction)
        }
        Storage.write { transaction in
            MessageSender.sendNonDurably(message, with: attachments, in: self.selectedThread!, using: transaction).done { [weak self] _ in
                guard let self = self else { return }
                self.shareVC?.hideLoader()
                self.shareVC?.shareViewWasCompleted()
            }.catch { [weak self] error in
                guard let self = self else { return }
                self.shareVC?.hideLoader()
                self.shareVC?.shareViewFailed(error: error)
            }
        }
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        // Do nothing
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        // Do nothing
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
