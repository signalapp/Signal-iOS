// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

@objc
class MessageRequestsViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    private var threads: YapDatabaseViewMappings! =  {
        let result = YapDatabaseViewMappings(groups: [ TSMessageRequestGroup ], view: TSThreadDatabaseViewExtensionName)
        result.setIsReversed(true, forGroup: TSMessageRequestGroup)
        return result
    }()
    private var threadViewModelCache: [String: ThreadViewModel] = [:] // Thread ID to ThreadViewModel
    private var tableViewTopConstraint: NSLayoutConstraint!
    
    private var messageRequestCount: UInt {
        threads.numberOfItems(inGroup: TSMessageRequestGroup)
    }
    
    private lazy var dbConnection: YapDatabaseConnection = {
        let result = OWSPrimaryStorage.shared().newDatabaseConnection()
        result.objectCacheLimit = 500
        
        return result
    }()
    
    // MARK: - UI
        
    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(MessageRequestsCell.self, forCellReuseIdentifier: MessageRequestsCell.reuseIdentifier)
        result.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        result.dataSource = self
        result.delegate = self
        
        let bottomInset = Values.newConversationButtonBottomOffset + NewConversationButtonSet.expandedButtonSize + Values.largeSpacing + NewConversationButtonSet.collapsedButtonSize
        result.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        result.showsVerticalScrollIndicator = false
        
        return result
    }()
    
    private lazy var emptyStateLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = UIFont.systemFont(ofSize: Values.smallFontSize)
        result.text = NSLocalizedString("MESSAGE_REQUESTS_EMPTY_TEXT", comment: "")
        result.textColor = Colors.text
        result.textAlignment = .center
        result.numberOfLines = 0
        result.isHidden = true
        
        return result
    }()
    
    private lazy var fadeView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.setGradient(Gradients.homeVCFade)
        
        return result
    }()
    
    private lazy var clearAllButton: Button = {
        let result: Button = Button(style: .destructiveOutline, size: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle(NSLocalizedString("MESSAGE_REQUESTS_CLEAR_ALL", comment: ""), for: .normal)
        result.setBackgroundImage(
            Colors.destructive
                .withAlphaComponent(isDarkMode ? 0.2 : 0.06)
                .toImage(isDarkMode: isDarkMode),
            for: .highlighted
        )
        result.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ViewControllerUtilities.setUpDefaultSessionStyle(for: self, title: NSLocalizedString("MESSAGE_REQUESTS_TITLE", comment: ""), hasCustomBackButton: false)
        
        // Add the UI (MUST be done after the thread freeze so the 'tableView' creation and setting
        // the dataSource has the correct data)
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(fadeView)
        view.addSubview(clearAllButton)
        setupLayout()
        
        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleYapDatabaseModifiedNotification(_:)),
            name: .YapDatabaseModified,
            object: OWSPrimaryStorage.shared().dbNotificationObject
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileDidChangeNotification(_:)),
            name: NSNotification.Name(rawValue: kNSNotificationName_OtherUsersProfileDidChange),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBlockedContactsUpdatedNotification(_:)),
            name: .blockedContactsUpdated,
            object: nil
        )
        
        reload()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reload()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Layout
    
    private func setupLayout() {
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: Values.smallSpacing),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            emptyStateLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Values.massiveSpacing),
            emptyStateLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: Values.mediumSpacing),
            emptyStateLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -Values.mediumSpacing),
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            fadeView.topAnchor.constraint(equalTo: view.topAnchor, constant: (0.15 * view.bounds.height)),
            fadeView.leftAnchor.constraint(equalTo: view.leftAnchor),
            fadeView.rightAnchor.constraint(equalTo: view.rightAnchor),
            fadeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            clearAllButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            clearAllButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Values.largeSpacing
            ),
            // Note: The '182' is to match the 'Next' button on the New DM page (which doesn't have a fixed width)
            clearAllButton.widthAnchor.constraint(equalToConstant: 182),
            clearAllButton.heightAnchor.constraint(equalToConstant: NewConversationButtonSet.collapsedButtonSize)
        ])
    }
    
    // MARK: - UITableViewDataSource
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Int(messageRequestCount)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
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
        clearAllButton.isHidden = (messageRequestCount == 0)
        emptyStateLabel.isHidden = (messageRequestCount != 0)
    }
    
    @objc private func handleYapDatabaseModifiedNotification(_ yapDatabase: YapDatabase) {
        // NOTE: This code is very finicky and crashes easily. Modify with care.
        AssertIsOnMainThread()
        
        // If we don't capture `threads` here, a race condition can occur where the
        // `thread.snapshotOfLastUpdate != firstSnapshot - 1` check below evaluates to
        // `false`, but `threads` then changes between that check and the
        // `ext.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notifications, with: threads)`
        // line. This causes `tableView.endUpdates()` to crash with an `NSInternalInconsistencyException`.
        let threads = threads!
        
        // Create a stable state for the connection and jump to the latest commit
        let notifications = dbConnection.beginLongLivedReadTransaction()
        
        guard !notifications.isEmpty else { return }
        
        let ext = dbConnection.ext(TSThreadDatabaseViewExtensionName) as! YapDatabaseViewConnection
        let hasChanges = ext.hasChanges(forGroup: TSMessageRequestGroup, in: notifications)
        
        guard hasChanges else { return }
        
        if let firstChangeSet = notifications[0].userInfo {
            let firstSnapshot = firstChangeSet[YapDatabaseSnapshotKey] as! UInt64
            
            if threads.snapshotOfLastUpdate != firstSnapshot - 1 {
                return reload() // The code below will crash if we try to process multiple commits at once
            }
        }
        
        var sectionChanges = NSArray()
        var rowChanges = NSArray()
        ext.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notifications, with: threads)
        
        guard sectionChanges.count > 0 || rowChanges.count > 0 else { return }
        
        tableView.beginUpdates()
        
        rowChanges.forEach { rowChange in
            let rowChange = rowChange as! YapDatabaseViewRowChange
            let key = rowChange.collectionKey.key
            threadViewModelCache[key] = nil
            switch rowChange.type {
                case .delete: tableView.deleteRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.automatic)
                case .insert: tableView.insertRows(at: [ rowChange.newIndexPath! ], with: UITableView.RowAnimation.automatic)
                case .update: tableView.reloadRows(at: [ rowChange.indexPath! ], with: UITableView.RowAnimation.automatic)
                default: break
            }
        }
        tableView.endUpdates()
        
        // HACK: Moves can have conflicts with the other 3 types of change.
        // Just batch perform all the moves separately to prevent crashing.
        // Since all the changes are from the original state to the final state,
        // it will still be correct if we pick the moves out.
        
        tableView.beginUpdates()
        
        rowChanges.forEach { rowChange in
            let rowChange = rowChange as! YapDatabaseViewRowChange
            let key = rowChange.collectionKey.key
            threadViewModelCache[key] = nil
            
            switch rowChange.type {
                case .move: tableView.moveRow(at: rowChange.indexPath!, to: rowChange.newIndexPath!)
                default: break
            }
        }
        
        tableView.endUpdates()
        clearAllButton.isHidden = (messageRequestCount == 0)
        emptyStateLabel.isHidden = (messageRequestCount != 0)
    }
    
    @objc private func handleProfileDidChangeNotification(_ notification: Notification) {
        tableView.reloadData() // TODO: Just reload the affected cell
    }
    
    @objc private func handleBlockedContactsUpdatedNotification(_ notification: Notification) {
        tableView.reloadData() // TODO: Just reload the affected cell
    }

    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)
        
        let gradient = Gradients.homeVCFade
        fadeView.setGradient(gradient) // Re-do the gradient
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        guard let thread = self.thread(at: indexPath.row) else { return }
        
        let conversationVC = ConversationVC(thread: thread)
        self.navigationController?.pushViewController(conversationVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard let thread = self.thread(at: indexPath.row) else { return [] }
        
        let delete = UITableViewRowAction(style: .destructive, title: NSLocalizedString("TXT_DELETE_TITLE", comment: "")) { [weak self] _, _ in
            self?.delete(thread)
        }
        delete.backgroundColor = Colors.destructive
        
        return [ delete ]
    }
    
    // MARK: - Interaction
    
    private func updateContactAndThread(thread: TSThread, with transaction: YapDatabaseReadWriteTransaction, onComplete: ((Bool) -> ())? = nil) {
        guard let contactThread: TSContactThread = thread as? TSContactThread else {
            onComplete?(false)
            return
        }
        
        var needsSync: Bool = false
        
        // Update the contact
        let sessionId: String = contactThread.contactSessionID()
        
        if let contact: Contact = Storage.shared.getContact(with: sessionId), (contact.isApproved || !contact.isBlocked) {
            contact.isApproved = false
            contact.isBlocked = true
            
            Storage.shared.setContact(contact, using: transaction)
            needsSync = true
        }
        
        // Delete all thread content
        thread.removeAllThreadInteractions(with: transaction)
        thread.remove(with: transaction)
        
        onComplete?(needsSync)
    }
    
    @objc private func clearAllTapped() {
        let threadCount: Int = Int(messageRequestCount)
        let threads: [TSThread] = (0..<threadCount).compactMap { self.thread(at: $0) }
        var needsSync: Bool = false
        
        let alertVC: UIAlertController = UIAlertController(title: NSLocalizedString("MESSAGE_REQUESTS_CLEAR_ALL_CONFIRMATION_TITLE", comment: ""), message: nil, preferredStyle: .actionSheet)
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("MESSAGE_REQUESTS_CLEAR_ALL_CONFIRMATION_ACTON", comment: ""), style: .destructive) { _ in
            // Clear the requests
            Storage.write(
                with: { [weak self] transaction in
                    threads.forEach { thread in
                        if let uniqueId: String = thread.uniqueId {
                            Storage.shared.cancelPendingMessageSendJobs(for: uniqueId, using: transaction)
                        }
                        
                        self?.updateContactAndThread(thread: thread, with: transaction) { threadNeedsSync in
                            if threadNeedsSync {
                                needsSync = true
                            }
                        }
                        
                        // Block the contact
                        if
                            let sessionId: String = (thread as? TSContactThread)?.contactSessionID(),
                            !thread.isBlocked(),
                            let contact: Contact = Storage.shared.getContact(with: sessionId, using: transaction)
                        {
                            contact.isBlocked = true
                            Storage.shared.setContact(contact, using: transaction)
                            needsSync = true
                        }
                    }
                },
                completion: {
                    // Force a config sync
                    if needsSync {
                        MessageSender.syncConfiguration(forceSyncNow: true).retainUntilComplete()
                    }
                }
            )
        })
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .cancel, handler: nil))
        self.present(alertVC, animated: true, completion: nil)
    }
    
    private func delete(_ thread: TSThread) {
        guard let uniqueId: String = thread.uniqueId else { return }
        
        let alertVC: UIAlertController = UIAlertController(title: NSLocalizedString("MESSAGE_REQUESTS_DELETE_CONFIRMATION_ACTON", comment: ""), message: nil, preferredStyle: .actionSheet)
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("TXT_DELETE_TITLE", comment: ""), style: .destructive) { _ in
            Storage.write(
                with: { [weak self] transaction in
                    Storage.shared.cancelPendingMessageSendJobs(for: uniqueId, using: transaction)
                    self?.updateContactAndThread(thread: thread, with: transaction)
                    
                    // Block the contact
                    if
                        let sessionId: String = (thread as? TSContactThread)?.contactSessionID(),
                        !thread.isBlocked(),
                        let contact: Contact = Storage.shared.getContact(with: sessionId, using: transaction)
                    {
                        contact.isBlocked = true
                        Storage.shared.setContact(contact, using: transaction)
                    }
                },
                completion: {
                    // Force a config sync
                    MessageSender.syncConfiguration(forceSyncNow: true).retainUntilComplete()
                }
            )
        })
        alertVC.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""), style: .cancel, handler: nil))
        self.present(alertVC, animated: true, completion: nil)
    }
    
    // MARK: - Convenience

    private func thread(at index: Int) -> TSThread? {
        var thread: TSThread? = nil
        
        dbConnection.read { transaction in
            let ext: YapDatabaseViewTransaction? = transaction.ext(TSThreadDatabaseViewExtensionName) as? YapDatabaseViewTransaction
            thread = ext?.object(atRow: UInt(index), inSection: 0, with: self.threads) as? TSThread
        }
        
        return thread
    }
    
    private func threadViewModel(at index: Int) -> ThreadViewModel? {
        guard let thread = thread(at: index), let uniqueId: String = thread.uniqueId else { return nil }
        
        if let cachedThreadViewModel = threadViewModelCache[uniqueId] {
            return cachedThreadViewModel
        }
        else {
            var threadViewModel: ThreadViewModel? = nil
            dbConnection.read { transaction in
                threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            threadViewModelCache[uniqueId] = threadViewModel
            
            return threadViewModel
        }
    }
}
