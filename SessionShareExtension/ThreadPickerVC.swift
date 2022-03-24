import UIKit
import SignalUtilitiesKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class ThreadPickerVC: UIViewController, UITableViewDataSource, UITableViewDelegate, AttachmentApprovalViewControllerDelegate {
    private var threads: YapDatabaseViewMappings!
    private var threadViewModelCache: [String: ThreadViewModel] = [:] // Thread ID to ThreadViewModel
    private var selectedThread: TSThread?
    var shareVC: ShareVC?
    
    private var threadCount: UInt {
        threads.numberOfItems(inGroup: TSShareExtensionGroup)
    }
    
    private lazy var dbConnection: YapDatabaseConnection = {
        let result = OWSPrimaryStorage.shared().newDatabaseConnection()
        result.objectCacheLimit = 500
        return result
    }()
    
    // MARK: - UI
    
    private lazy var titleLabel: UILabel = {
        let titleLabel: UILabel = UILabel()
        titleLabel.text = "vc_share_title".localized()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        
        return titleLabel
    }()

    private lazy var tableView: UITableView = {
        let tableView: UITableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.register(view: SimplifiedConversationCell.self)
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        
        return tableView
    }()
    
    private lazy var fadeView: UIView = {
        let view = UIView()
        let gradient = Gradients.homeVCFade
        view.setGradient(gradient)
        view.isUserInteractionEnabled = false
        
        return view
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupNavBar()
        
        // Gradient
        view.backgroundColor = .clear
        view.setGradient(Gradients.defaultBackground)
        
        // Threads
        dbConnection.beginLongLivedReadTransaction() // Freeze the connection for use on the main thread (this gives us a stable data source that doesn't change until we tell it to)
        threads = YapDatabaseViewMappings(groups: [ TSShareExtensionGroup ], view: TSThreadShareExtensionDatabaseViewExtensionName) // The extension should be registered at this point
        threads.setIsReversed(true, forGroup: TSShareExtensionGroup)
        dbConnection.read { transaction in
            self.threads.update(with: transaction) // Perform the initial update
        }
        
        // Title
        navigationItem.titleView = titleLabel
        
        // Table view
        
        view.addSubview(tableView)
        view.addSubview(fadeView)
        
        setupLayout()
        // Reload
        reload()
    }
    
    private func setupNavBar() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Colors.navigationBarBackground
            navigationBar.standardAppearance = appearance;
            navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        view.setGradient(Gradients.defaultBackground)
        fadeView.setGradient(Gradients.homeVCFade)
    }
    
    // MARK: Layout
    
    private func setupLayout() {
        let topInset = 0.15 * view.height()
        
        tableView.pin(to: view)
        fadeView.pin(.leading, to: .leading, of: view)
        fadeView.pin(.top, to: .top, of: view, withInset: topInset)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
    }
    
    // MARK: Table View Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(threadCount)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: SimplifiedConversationCell = tableView.dequeue(type: SimplifiedConversationCell.self, for: indexPath)
        cell.threadViewModel = threadViewModel(at: indexPath.row)
        
        return cell
    }
    
    // MARK: - Updating
    
    private func reload() {
        AssertIsOnMainThread()
        dbConnection.beginLongLivedReadTransaction() // Jump to the latest commit
        dbConnection.read { transaction in
            self.threads.update(with: transaction)
        }
        threadViewModelCache.removeAll()
        tableView.reloadData()
    }
    
    // MARK: - Interaction
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let thread = self.thread(at: indexPath.row), let attachments = ShareVC.attachmentPrepPromise?.value else {
            return
        }
        
        self.selectedThread = thread
        
        let approvalVC = AttachmentApprovalViewController.wrappedInNavController(attachments: attachments, approvalDelegate: self)
        navigationController!.present(approvalVC, animated: true, completion: nil)
    }
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], messageText: String?) {
        // Sharing a URL or plain text will populate the 'messageText' field so in those
        // cases we should ignore the attachments
        let isSharingUrl: Bool = (attachments.count == 1 && attachments[0].isUrl)
        let isSharingText: Bool = (attachments.count == 1 && attachments[0].isText)
        let finalAttachments: [SignalAttachment] = (isSharingUrl || isSharingText ? [] : attachments)
        
        let message = VisibleMessage()
        message.sentTimestamp = NSDate.millisecondTimestamp()
        message.text = (isSharingUrl && (messageText?.isEmpty == true || attachments[0].linkPreviewDraft == nil) ?
            (
                (messageText?.isEmpty == true || (attachments[0].text() == messageText) ?
                    attachments[0].text() :
                    "\(attachments[0].text() ?? "")\n\n\(messageText ?? "")"
                )
            ) :
            messageText
        )

        let tsMessage = TSOutgoingMessage.from(message, associatedWith: selectedThread!)
        Storage.write(
            with: { transaction in
                if isSharingUrl {
                    message.linkPreview = VisibleMessage.LinkPreview.from(
                        attachments[0].linkPreviewDraft,
                        using: transaction
                    )
                }
                else {
                    tsMessage.save(with: transaction)
                }
            },
            completion: {
                if isSharingUrl {
                    tsMessage.linkPreview = OWSLinkPreview.from(message.linkPreview)
                    
                    Storage.write { transaction in
                        tsMessage.save(with: transaction)
                    }
                }
            }
        )
        
        shareVC!.dismiss(animated: true, completion: nil)
        
        ModalActivityIndicatorViewController.present(fromViewController: shareVC!, canCancel: false, message: "vc_share_sending_message".localized()) { activityIndicator in
            MessageSender.sendNonDurably(message, with: finalAttachments, in: self.selectedThread!)
                .done { [weak self] _ in
                    activityIndicator.dismiss { }
                    self?.shareVC?.shareViewWasCompleted()
                }
                .catch { [weak self] error in
                    activityIndicator.dismiss { }
                    self?.shareVC?.shareViewFailed(error: error)
                }
        }
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        dismiss(animated: true, completion: nil)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
        // Do nothing
    }
    
    // MARK: - Convenience
    
    private func thread(at index: Int) -> TSThread? {
        var thread: TSThread? = nil
        dbConnection.read { transaction in
            let ext = transaction.ext(TSThreadShareExtensionDatabaseViewExtensionName) as! YapDatabaseViewTransaction
            thread = ext.object(atRow: UInt(index), inSection: 0, with: self.threads) as! TSThread?
        }
        return thread
    }
    
    private func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard let thread = thread(at: index) else { return nil }
        
        if let cachedThreadViewModel = threadViewModelCache[thread.uniqueId!] {
            return cachedThreadViewModel
        }
        else {
            var threadViewModel: ThreadViewModel? = nil
            dbConnection.read { transaction in
                threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            threadViewModelCache[thread.uniqueId!] = threadViewModel
            return threadViewModel
        }
    }
}
