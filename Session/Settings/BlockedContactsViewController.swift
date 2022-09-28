// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

class BlockedContactsViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    private static let loadingHeaderHeight: CGFloat = 40
    
    private let viewModel: BlockedContactsViewModel = BlockedContactsViewModel()
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialContactData: Bool = false
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
        result.clipsToBounds = true
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.register(view: SessionCell.self)
        result.dataSource = self
        result.delegate = self
        result.layer.cornerRadius = SessionCell.cornerRadius
        
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
        result.text = "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_EMPTY_STATE".localized()
        result.themeTextColor = .textSecondary
        result.textAlignment = .center
        result.numberOfLines = 0
        result.isHidden = true

        return result
    }()
    
    private lazy var fadeView: GradientView = {
        let result: GradientView = GradientView()
        result.themeBackgroundGradient = [
            .value(.backgroundPrimary, alpha: 0), // Want this to take up 20% (~25pt)
            .backgroundPrimary,
            .backgroundPrimary,
            .backgroundPrimary,
            .backgroundPrimary
        ]
        result.set(.height, to: Values.footerGradientHeight(window: UIApplication.shared.keyWindow))
        
        return result
    }()
    
    private lazy var unblockButton: SessionButton = {
        let result: SessionButton = SessionButton(style: .destructive, size: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle("CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK".localized(), for: .normal)
        result.addTarget(self, action: #selector(unblockTapped), for: .touchUpInside)

        return result
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundPrimary

        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
               title: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_TITLE".localized(),
               hasCustomBackButton: false
        )

        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(fadeView)
        view.addSubview(unblockButton)
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
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor, constant: Values.largeSpacing),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -Values.largeSpacing),
            tableView.bottomAnchor.constraint(
                equalTo: unblockButton.topAnchor,
                constant: -Values.largeSpacing
            ),

            emptyStateLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: Values.massiveSpacing),
            emptyStateLabel.leftAnchor.constraint(equalTo: view.leftAnchor, constant: Values.mediumSpacing),
            emptyStateLabel.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -Values.mediumSpacing),
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            fadeView.leftAnchor.constraint(equalTo: view.leftAnchor),
            fadeView.rightAnchor.constraint(equalTo: view.rightAnchor),
            fadeView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            unblockButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            unblockButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -Values.smallSpacing
            ),
            unblockButton.widthAnchor.constraint(equalToConstant: Values.iPadButtonWidth)
        ])
    }
    
    // MARK: - Updating
    
    private func startObservingChanges(didReturnFromBackground: Bool = false) {
        self.viewModel.onContactChange = { [weak self] updatedContactData in
            self?.handleContactUpdates(updatedContactData)
        }
        
        // Note: When returning from the background we could have received notifications but the
        // PagedDatabaseObserver won't have them so we need to force a re-fetch of the current
        // data to ensure everything is up to date
        if didReturnFromBackground {
            self.viewModel.pagedDataObserver?.reload()
        }
    }
    
    private func handleContactUpdates(_ updatedData: [BlockedContactsViewModel.SectionModel], initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialContactData else {
            hasLoadedInitialContactData = true
            UIView.performWithoutAnimation { handleContactUpdates(updatedData, initialLoad: true) }
            return
        }
        
        // Show the empty state if there is no data
        let hasContactsData: Bool = (updatedData
            .first(where: { $0.model == .contacts })?
            .elements
            .isEmpty == false)
        unblockButton.isEnabled = !viewModel.selectedContactIds.isEmpty
        unblockButton.isHidden = !hasContactsData
        emptyStateLabel.isHidden = hasContactsData
        
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            // Complete page loading
            self?.isLoadingMore = false
            self?.autoLoadNextPageIfNeeded()
        }
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.contactData, target: updatedData),
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .bottom,
            insertRowsAnimation: .top,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateContactData(updatedData)
        }
        
        CATransaction.commit()
    }
    
    private func autoLoadNextPageIfNeeded() {
        guard !self.isAutoLoadingNextPage && !self.isLoadingMore else { return }
        
        self.isAutoLoadingNextPage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + PagedData.autoLoadNextPageDelay) { [weak self] in
            self?.isAutoLoadingNextPage = false
            
            // Note: We sort the headers as we want to prioritise loading newer pages over older ones
            let sections: [(BlockedContactsViewModel.Section, CGRect)] = (self?.viewModel.contactData
                .enumerated()
                .map { index, section in
                    (section.model, (self?.tableView.rectForHeader(inSection: index) ?? .zero))
                })
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
        return viewModel.contactData.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section: BlockedContactsViewModel.SectionModel = viewModel.contactData[section]
        
        return section.elements.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: BlockedContactsViewModel.SectionModel = viewModel.contactData[indexPath.section]
        
        switch section.model {
            case .contacts:
                let info: SessionCell.Info<Profile> = section.elements[indexPath.row]
                let cell: SessionCell = tableView.dequeue(type: SessionCell.self, for: indexPath)
                cell.update(
                    with: info,
                    style: .roundedEdgeToEdge,
                    position: Position.with(indexPath.row, count: section.elements.count)
                )
                
                return cell

            default: preconditionFailure("Other sections should have no content")
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section: BlockedContactsViewModel.SectionModel = viewModel.contactData[section]
        
        switch section.model {
            case .loadMore:
                let loadingIndicator: UIActivityIndicatorView = UIActivityIndicatorView(style: .medium)
                loadingIndicator.themeTintColor = .textPrimary
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
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section: BlockedContactsViewModel.SectionModel = viewModel.contactData[section]
        
        switch section.model {
            case .loadMore: return BlockedContactsViewController.loadingHeaderHeight
            default: return 0
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard self.hasLoadedInitialContactData && self.viewHasAppeared && !self.isLoadingMore else { return }
        
        let section: BlockedContactsViewModel.SectionModel = self.viewModel.contactData[section]
        
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
        
        let section: BlockedContactsViewModel.SectionModel = self.viewModel.contactData[indexPath.section]
        
        switch section.model {
            case .contacts:
                let info: SessionCell.Info<Profile> = section.elements[indexPath.row]
                
                // Do nothing if the item is disabled
                guard info.isEnabled else { return }
                
                // Get the view that was tapped (for presenting on iPad)
                let tappedView: UIView? = tableView.cellForRow(at: indexPath)
                let maybeOldSelection: (Int, SessionCell.Info<Profile>)? = section.elements
                    .enumerated()
                    .first(where: { index, info in
                        switch (info.leftAccessory, info.rightAccessory) {
                            case (_, .radio(_, let isSelected, _)): return isSelected()
                            case (.radio(_, let isSelected, _), _): return isSelected()
                            default: return false
                        }
                    })
                
                info.onTap?(tappedView)
                self.manuallyReload(indexPath: indexPath, section: section, info: info)
                self.unblockButton.isEnabled = !self.viewModel.selectedContactIds.isEmpty
                
                // Update the old selection as well
                if let oldSelection: (index: Int, info: SessionCell.Info<Profile>) = maybeOldSelection {
                    self.manuallyReload(
                        indexPath: IndexPath(
                            row: oldSelection.index,
                            section: indexPath.section
                        ),
                        section: section,
                        info: oldSelection.info
                    )
                }
                
            default: break
        }
    }
    
    private func manuallyReload(
        indexPath: IndexPath,
        section: BlockedContactsViewModel.SectionModel,
        info: SessionCell.Info<Profile>
    ) {
        // Try update the existing cell to have a nice animation instead of reloading the cell
        if let existingCell: SessionCell = tableView.cellForRow(at: indexPath) as? SessionCell {
            existingCell.update(
                with: info,
                style: .roundedEdgeToEdge,
                position: Position.with(indexPath.row, count: section.elements.count)
            )
        }
        else {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }

    // MARK: - Interaction
    
    @objc private func unblockTapped() {
        guard !viewModel.selectedContactIds.isEmpty else { return }
        
        let contactIds: Set<String> = viewModel.selectedContactIds
        let contactNames: [String] = contactIds
            .map { contactId in
                guard
                    let section: BlockedContactsViewModel.SectionModel = self.viewModel.contactData
                        .first(where: { section in section.model == .contacts }),
                    let info: SessionCell.Info<Profile> = section.elements
                        .first(where: { info in info.id.id == contactId })
                else { return contactId }
                
                return info.title
            }
        let confirmationTitle: String = {
            guard contactNames.count > 1 else {
                // Show a single users name
                return String(
                    format: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_SINGLE".localized(),
                    (
                        contactNames.first ??
                        "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_FALLBACK".localized()
                    )
                )
            }
            guard contactNames.count > 3 else {
                // Show up to three users names
                let initialNames: [String] = Array(contactNames.prefix(upTo: (contactNames.count - 1)))
                let lastName: String = contactNames[contactNames.count - 1]
                
                return [
                    String(
                        format: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_MULTIPLE_1".localized(),
                        initialNames.joined(separator: ", ")
                    ),
                    String(
                        format: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_MULTIPLE_2_SINGLE".localized(),
                        lastName
                    ),
                ].joined(separator: " ")
            }
            
            // If we have exactly 4 users, show the first two names followed by 'and X others', for
            // more than 4 users, show the first 3 names followed by 'and X others'
            let numNamesToShow: Int = (contactNames.count == 4 ? 2 : 3)
            let initialNames: [String] = Array(contactNames.prefix(upTo: numNamesToShow))
            
            return [
                String(
                    format: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_MULTIPLE_1".localized(),
                    initialNames.joined(separator: ", ")
                ),
                String(
                    format: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_TITLE_MULTIPLE_3".localized(),
                    (contactNames.count - numNamesToShow)
                ),
            ].joined(separator: " ")
        }()
        let confirmationModal: ConfirmationModal = ConfirmationModal(
            info: ConfirmationModal.Info(
                title: confirmationTitle,
                confirmTitle: "CONVERSATION_SETTINGS_BLOCKED_CONTACTS_UNBLOCK_CONFIRMATION_ACTON".localized(),
                confirmStyle: .danger,
                cancelStyle: .alert_text
            ) { _ in
                // Unblock the contacts
                Storage.shared.write { db in
                    _ = try Contact
                        .filter(ids: contactIds)
                        .updateAll(db, Contact.Columns.isBlocked.set(to: false))
                    
                    // Force a config sync
                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                }
            }
        )
        self.present(confirmationModal, animated: true, completion: nil)
    }
}
