// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

class MessageRequestsViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    private let viewModel: MessageRequestsViewModel = MessageRequestsViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialData: Bool = false
    
    // MARK: - UI

    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(view: ConversationCell.Full.self)
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

        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
               title: "MESSAGE_REQUESTS_TITLE".localized(),
               hasCustomBackButton: false
        )

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
    
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeObservable = GRDBStorage.shared.start(
            viewModel.observableViewData,
            onError:  { error in
                print("Update error \(error)!!!!")
            },
            onChange: { [weak self] viewData in
                // The defaul scheduler emits changes on the main thread
                self?.handleUpdates(viewData)
            }
        )
    }
    
    private func handleUpdates(_ updatedViewData: [ConversationCell.ViewModel]) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialData else {
            hasLoadedInitialData = true
            UIView.performWithoutAnimation { handleUpdates(updatedViewData) }
            return
        }
        
        // Show the empty state if there is no data
        clearAllButton.isHidden = updatedViewData.isEmpty
        emptyStateLabel.isHidden = !updatedViewData.isEmpty
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.viewData, target: updatedViewData),
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .bottom,
            insertRowsAnimation: .top,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateData(updatedData)
        }
    }

    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)

        let gradient = Gradients.homeVCFade
        fadeView.setGradient(gradient) // Re-do the gradient
        tableView.reloadData()
    }
    
    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.viewData.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: ConversationCell.Full = tableView.dequeue(type: ConversationCell.Full.self, for: indexPath)
        cell.update(with: viewModel.viewData[indexPath.row])
        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let conversationVC: ConversationVC = ConversationVC(threadId: viewModel.viewData[indexPath.row].threadId) else {
            return
        }
        
        self.navigationController?.pushViewController(conversationVC, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let threadId: String = viewModel.viewData[indexPath.row].threadId
        let delete = UITableViewRowAction(
            style: .destructive,
            title: "TXT_DELETE_TITLE".localized()
        ) { [weak self] _, _ in
            self?.delete(threadId)
        }
        delete.backgroundColor = Colors.destructive

        return [ delete ]
    }

    // MARK: - Interaction

    @objc private func clearAllTapped() {
        guard !viewModel.viewData.isEmpty else { return }
        
        let threadIds: [String] = viewModel.viewData.map { $0.threadId }
        let alertVC: UIAlertController = UIAlertController(
            title: "MESSAGE_REQUESTS_CLEAR_ALL_CONFIRMATION_TITLE".localized(),
            message: nil,
            preferredStyle: .actionSheet
        )
        alertVC.addAction(UIAlertAction(
            title: "MESSAGE_REQUESTS_CLEAR_ALL_CONFIRMATION_ACTON".localized(),
            style: .destructive
        ) { _ in
            // Clear the requests
            GRDBStorage.shared.write { db in
                _ = try SessionThread
                    .filter(ids: threadIds)
                    .deleteAll(db)
                
                try threadIds.forEach { threadId in
                    _ = try Contact
                        .fetchOrCreate(db, id: threadId)
                        .with(
                            isApproved: false,
                            isBlocked: true
                        )
                        .saved(db)
                }
                
                // Force a config sync
                try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
            }
        })
        alertVC.addAction(UIAlertAction(title: "TXT_CANCEL_TITLE".localized(), style: .cancel, handler: nil))
        self.present(alertVC, animated: true, completion: nil)
    }

    private func delete(_ threadId: String) {
        let alertVC: UIAlertController = UIAlertController(
            title: "MESSAGE_REQUESTS_DELETE_CONFIRMATION_ACTON".localized(),
            message: nil,
            preferredStyle: .actionSheet
        )
        alertVC.addAction(UIAlertAction(
            title: "TXT_DELETE_TITLE".localized(),
            style: .destructive
        ) { _ in
            GRDBStorage.shared.write { db in
                _ = try SessionThread
                    .filter(id: threadId)
                    .deleteAll(db)
                _ = try Contact
                    .fetchOrCreate(db, id: threadId)
                    .with(
                        isApproved: false,
                        isBlocked: true
                    )
                    .saved(db)
                
                // Force a config sync
                try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
            }
        })
        
        alertVC.addAction(UIAlertAction(title: "TXT_CANCEL_TITLE".localized(), style: .cancel, handler: nil))
        self.present(alertVC, animated: true, completion: nil)
    }
}
