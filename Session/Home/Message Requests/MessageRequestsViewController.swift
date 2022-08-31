// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

class MessageRequestsViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    private static let loadingHeaderHeight: CGFloat = 20
    
    private let viewModel: MessageRequestsViewModel = MessageRequestsViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialThreadData: Bool = false
    private var isLoadingMore: Bool = false
    private var isAutoLoadingNextPage: Bool = false
    private var viewHasAppeared: Bool = false
    
    // MARK: - Intialization
    
    init() {
        Storage.shared.addObserver(viewModel.pagedDataObserver)
        
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init() instead.")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI

    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.backgroundColor = .clear
        result.separatorStyle = .none
        result.register(view: FullConversationCell.self)
        result.dataSource = self
        result.delegate = self

        let bottomInset = Values.newConversationButtonBottomOffset + NewConversationButtonSet.expandedButtonSize + Values.largeSpacing + NewConversationButtonSet.collapsedButtonSize
        result.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        result.showsVerticalScrollIndicator = false
        
        if #available(iOS 15.0, *) {
            result.sectionHeaderTopPadding = 0
        }

        return result
    }()

    private lazy var emptyStateLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "MESSAGE_REQUESTS_EMPTY_TEXT".localized()
        result.themeTextColor = .textSecondary
        result.textAlignment = .center
        result.numberOfLines = 0
        result.isHidden = true

        return result
    }()

    private lazy var clearAllButton: OutlineButton = {
        let result: OutlineButton = OutlineButton(style: .destructive, size: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle("MESSAGE_REQUESTS_CLEAR_ALL".localized(), for: .normal)
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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.viewHasAppeared = true
        self.autoLoadNextPageIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges(didReturnFromBackground: true)
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        // Stop observing database changes
        dataChangeObservable?.cancel()
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
            
            clearAllButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            clearAllButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Values.largeSpacing
            ),
            clearAllButton.widthAnchor.constraint(equalToConstant: Values.iPadButtonWidth),
            clearAllButton.heightAnchor.constraint(equalToConstant: NewConversationButtonSet.collapsedButtonSize)
        ])
    }
    
    // MARK: - Updating
    
    private func startObservingChanges(didReturnFromBackground: Bool = false) {
        self.viewModel.onThreadChange = { [weak self] updatedThreadData in
            self?.handleThreadUpdates(updatedThreadData)
        }
        
        // Note: When returning from the background we could have received notifications but the
        // PagedDatabaseObserver won't have them so we need to force a re-fetch of the current
        // data to ensure everything is up to date
        if didReturnFromBackground {
            self.viewModel.pagedDataObserver?.reload()
        }
    }
    
    private func handleThreadUpdates(_ updatedData: [MessageRequestsViewModel.SectionModel], initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialThreadData else {
            hasLoadedInitialThreadData = true
            UIView.performWithoutAnimation { handleThreadUpdates(updatedData, initialLoad: true) }
            return
        }
        
        // Show the empty state if there is no data
        clearAllButton.isHidden = updatedData.isEmpty
        emptyStateLabel.isHidden = !updatedData.isEmpty
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Complete page loading
            self?.isLoadingMore = false
            self?.autoLoadNextPageIfNeeded()
        }
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.threadData, target: updatedData),
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .bottom,
            insertRowsAnimation: .top,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateThreadData(updatedData)
        }
        
        CATransaction.commit()
    }
    
    private func autoLoadNextPageIfNeeded() {
        guard !self.isAutoLoadingNextPage && !self.isLoadingMore else { return }
        
        self.isAutoLoadingNextPage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + PagedData.autoLoadNextPageDelay) { [weak self] in
            self?.isAutoLoadingNextPage = false
            
            // Note: We sort the headers as we want to prioritise loading newer pages over older ones
            let sections: [(MessageRequestsViewModel.Section, CGRect)] = (self?.viewModel.threadData
                .enumerated()
                .map { index, section in (section.model, (self?.tableView.rectForHeader(inSection: index) ?? .zero)) })
                .defaulting(to: [])
            let shouldLoadMore: Bool = sections
                .contains { section, headerRect in
                    section == .loadMore &&
                    headerRect != .zero &&
                    (self?.tableView.bounds.contains(headerRect) == true)
                }
            
            guard shouldLoadMore else { return }
            
            self?.isLoadingMore = true
            
            DispatchQueue.global(qos: .default).async { [weak self] in
                self?.viewModel.pagedDataObserver?.load(.pageAfter)
            }
        }
    }
    
    // MARK: - UITableViewDataSource

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.threadData.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section: MessageRequestsViewModel.SectionModel = viewModel.threadData[section]
        
        return section.elements.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: MessageRequestsViewModel.SectionModel = viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .threads:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                let cell: FullConversationCell = tableView.dequeue(type: FullConversationCell.self, for: indexPath)
                cell.update(with: threadViewModel)
                return cell
                
            default: preconditionFailure("Other sections should have no content")
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section: MessageRequestsViewModel.SectionModel = viewModel.threadData[section]
        
        switch section.model {
            case .loadMore:
                let loadingIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .medium)
                loadingIndicator.tintColor = Colors.text
                loadingIndicator.alpha = 0.5
                loadingIndicator.startAnimating()
                
                let view: UIView = UIView()
                view.addSubview(loadingIndicator)
                loadingIndicator.center(in: view)
                
                return view
            
            default: return nil
        }
    }

    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section: MessageRequestsViewModel.SectionModel = viewModel.threadData[section]
        
        switch section.model {
            case .loadMore: return MessageRequestsViewController.loadingHeaderHeight
            default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard self.hasLoadedInitialThreadData && self.viewHasAppeared && !self.isLoadingMore else { return }
        
        let section: MessageRequestsViewModel.SectionModel = self.viewModel.threadData[section]
        
        switch section.model {
            case .loadMore:
                self.isLoadingMore = true
                
                DispatchQueue.global(qos: .default).async { [weak self] in
                    self?.viewModel.pagedDataObserver?.load(.pageAfter)
                }
                
            default: break
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section: MessageRequestsViewModel.SectionModel = self.viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .threads:
                let threadViewModel: SessionThreadViewModel = section.elements[indexPath.row]
                let conversationVC: ConversationVC = ConversationVC(
                    threadId: threadViewModel.threadId,
                    threadVariant: threadViewModel.threadVariant
                )
                self.navigationController?.pushViewController(conversationVC, animated: true)
                
            default: break
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let section: MessageRequestsViewModel.SectionModel = self.viewModel.threadData[indexPath.section]
        
        switch section.model {
            case .threads:
                let threadId: String = section.elements[indexPath.row].threadId
                let delete = UIContextualAction(
                    style: .destructive,
                    title: "TXT_DELETE_TITLE".localized()
                ) { [weak self] _, _, completionHandler in
                    self?.delete(threadId)
                    completionHandler(true)
                }
                delete.themeBackgroundColor = .conversationButton_swipeDestructive

                return UISwipeActionsConfiguration(actions: [ delete ])
                
            default: return nil
        }
    }

    // MARK: - Interaction
    
    @objc private func clearAllTapped() {
        guard viewModel.threadData.first(where: { $0.model == .threads })?.elements.isEmpty == false else {
            return
        }
        
        let threadIds: [String] = (viewModel.threadData
            .first { $0.model == .threads }?
            .elements
            .map { $0.threadId })
            .defaulting(to: [])
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
            Storage.shared.write { db in
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
            Storage.shared.write { db in
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
