// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import PromiseKit
import DifferenceKit
import Sodium
import SessionUIKit
import SignalUtilitiesKit
import SessionMessagingKit

final class ThreadPickerVC: UIViewController, UITableViewDataSource, UITableViewDelegate, AttachmentApprovalViewControllerDelegate {
    private let viewModel: ThreadPickerViewModel = ThreadPickerViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialData: Bool = false
    
    var shareVC: ShareVC?
    
    // MARK: - Intialization
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
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
        
        // Title
        navigationItem.titleView = titleLabel
        
        // Table view
        
        view.addSubview(tableView)
        view.addSubview(fadeView)
        
        setupLayout()
        
        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges()
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Stop observing database changes
        dataChangeObservable?.cancel()
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
    
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeObservable = Storage.shared.start(
            viewModel.observableViewData,
            onError:  { _ in },
            onChange: { [weak self] viewData in
                // The defaul scheduler emits changes on the main thread
                self?.handleUpdates(viewData)
            }
        )
    }
    
    private func handleUpdates(_ updatedViewData: [SessionThreadViewModel]) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialData else {
            hasLoadedInitialData = true
            UIView.performWithoutAnimation { handleUpdates(updatedViewData) }
            return
        }
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.viewData, target: updatedViewData),
            with: .automatic,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateData(updatedData)
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModel.viewData.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: SimplifiedConversationCell = tableView.dequeue(type: SimplifiedConversationCell.self, for: indexPath)
        cell.update(with: self.viewModel.viewData[indexPath.row])
        
        return cell
    }
    
    // MARK: - Interaction
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let attachments: [SignalAttachment] = ShareVC.attachmentPrepPromise?.value else { return }
        
        let approvalVC: OWSNavigationController = AttachmentApprovalViewController.wrappedInNavController(
            threadId: self.viewModel.viewData[indexPath.row].threadId,
            attachments: attachments,
            approvalDelegate: self
        )
        self.navigationController?.present(approvalVC, animated: true, completion: nil)
    }
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didApproveAttachments attachments: [SignalAttachment], forThreadId threadId: String, messageText: String?) {
        // Sharing a URL or plain text will populate the 'messageText' field so in those
        // cases we should ignore the attachments
        let isSharingUrl: Bool = (attachments.count == 1 && attachments[0].isUrl)
        let isSharingText: Bool = (attachments.count == 1 && attachments[0].isText)
        let finalAttachments: [SignalAttachment] = (isSharingUrl || isSharingText ? [] : attachments)
        let body: String? = (
            isSharingUrl && (messageText?.isEmpty == true || attachments[0].linkPreviewDraft == nil) ?
            (
                (messageText?.isEmpty == true || (attachments[0].text() == messageText) ?
                    attachments[0].text() :
                    "\(attachments[0].text() ?? "")\n\n\(messageText ?? "")"
                )
            ) :
            messageText
        )
        
        shareVC?.dismiss(animated: true, completion: nil)
        
        ModalActivityIndicatorViewController.present(fromViewController: shareVC!, canCancel: false, message: "vc_share_sending_message".localized()) { activityIndicator in
            // Resume database
            NotificationCenter.default.post(name: Database.resumeNotification, object: self)
            Storage.shared
                .writeAsync { [weak self] db -> Promise<Void> in
                    guard let thread: SessionThread = try SessionThread.fetchOne(db, id: threadId) else {
                        activityIndicator.dismiss { }
                        self?.shareVC?.shareViewFailed(error: MessageSenderError.noThread)
                        return Promise(error: MessageSenderError.noThread)
                    }
                    
                    // Create the interaction
                    let interaction: Interaction = try Interaction(
                        threadId: threadId,
                        authorId: getUserHexEncodedPublicKey(db),
                        variant: .standardOutgoing,
                        body: body,
                        timestampMs: Int64(floor(Date().timeIntervalSince1970 * 1000)),
                        hasMention: Interaction.isUserMentioned(db, threadId: threadId, body: body),
                        expiresInSeconds: try? DisappearingMessagesConfiguration
                            .select(.durationSeconds)
                            .filter(id: threadId)
                            .filter(DisappearingMessagesConfiguration.Columns.isEnabled == true)
                            .asRequest(of: TimeInterval.self)
                            .fetchOne(db),
                        linkPreviewUrl: (isSharingUrl ? attachments.first?.linkPreviewDraft?.urlString : nil)
                    ).inserted(db)

                    // If the user is sharing a Url, there is a LinkPreview and it doesn't match an existing
                    // one then add it now
                    if
                        isSharingUrl,
                        let linkPreviewDraft: LinkPreviewDraft = attachments.first?.linkPreviewDraft,
                        (try? interaction.linkPreview.isEmpty(db)) == true
                    {
                        try LinkPreview(
                            url: linkPreviewDraft.urlString,
                            title: linkPreviewDraft.title,
                            attachmentId: LinkPreview.saveAttachmentIfPossible(
                                db,
                                imageData: linkPreviewDraft.jpegImageData,
                                mimeType: OWSMimeTypeImageJpeg
                            )
                        ).insert(db)
                    }

                    return try MessageSender.sendNonDurably(
                        db,
                        interaction: interaction,
                        with: finalAttachments,
                        in: thread
                    )
                }
                .done { [weak self] _ in
                    // Suspend the database
                    NotificationCenter.default.post(name: Database.suspendNotification, object: self)
                    activityIndicator.dismiss { }
                    self?.shareVC?.shareViewWasCompleted()
                }
                .catch { [weak self] error in
                    // Suspend the database
                    NotificationCenter.default.post(name: Database.suspendNotification, object: self)
                    activityIndicator.dismiss { }
                    self?.shareVC?.shareViewFailed(error: error)
                }
        }
    }

    func attachmentApprovalDidCancel(_ attachmentApproval: AttachmentApprovalViewController) {
        dismiss(animated: true, completion: nil)
    }

    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didChangeMessageText newMessageText: String?) {
    }
    
    func attachmentApproval(_ attachmentApproval: AttachmentApprovalViewController, didRemoveAttachment attachment: SignalAttachment) {
    }
    
    func attachmentApprovalDidTapAddMore(_ attachmentApproval: AttachmentApprovalViewController) {
    }
}
