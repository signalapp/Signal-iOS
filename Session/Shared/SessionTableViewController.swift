// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionUtilitiesKit
import SignalUtilitiesKit

protocol SessionViewModelAccessible {
    var viewModelType: AnyObject.Type { get }
}

class SessionTableViewController<NavItemId: Equatable, Section: SessionTableSection, SettingItem: Hashable & Differentiable>: BaseVC, UITableViewDataSource, UITableViewDelegate, SessionViewModelAccessible {
    typealias SectionModel = SessionTableViewModel<NavItemId, Section, SettingItem>.SectionModel
    
    private let viewModel: SessionTableViewModel<NavItemId, Section, SettingItem>
    private var hasLoadedInitialSettingsData: Bool = false
    private var dataStreamJustFailed: Bool = false
    private var dataChangeCancellable: AnyCancellable?
    private var disposables: Set<AnyCancellable> = Set()
    
    public var viewModelType: AnyObject.Type { return type(of: viewModel) }
    
    // MARK: - Components
    
    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.showsHorizontalScrollIndicator = false
        result.register(view: SessionAvatarCell.self)
        result.register(view: SessionCell.self)
        result.registerHeaderFooterView(view: SessionHeaderView.self)
        result.dataSource = self
        result.delegate = self
        
        if #available(iOS 15.0, *) {
            result.sectionHeaderTopPadding = 0
        }
        
        return result
    }()
    
    // MARK: - Initialization
    
    init(viewModel: SessionTableViewModel<NavItemId, Section, SettingItem>) {
        self.viewModel = viewModel
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
            title: viewModel.title,
            hasCustomBackButton: false
        )
        
        view.themeBackgroundColor = .backgroundPrimary
        view.addSubview(tableView)
        
        setupLayout()
        setupBinding()
        
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
        
        stopObservingChanges()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges()
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        stopObservingChanges()
    }
    
    private func setupLayout() {
        tableView.pin(to: view)
    }
    
    // MARK: - Updating
    
    private func startObservingChanges() {
        // Start observing for data changes
        dataChangeCancellable = viewModel.observableSettingsData
            .receiveOnMain(
                // If we haven't done the initial load the trigger it immediately (blocking the main
                // thread so we remain on the launch screen until it completes to be consistent with
                // the old behaviour)
                immediately: !hasLoadedInitialSettingsData
            )
            .sink(
                receiveCompletion: { [weak self] result in
                    switch result {
                        case .failure(let error):
                            let title: String = (self?.viewModel.title ?? "unknown")
                            
                            // If we got an error then try to restart the stream once, otherwise log the error
                            guard self?.dataStreamJustFailed == false else {
                                SNLog("Unable to recover database stream in '\(title)' settings with error: \(error)")
                                return
                            }
                            
                            SNLog("Atempting recovery for database stream in '\(title)' settings with error: \(error)")
                            self?.dataStreamJustFailed = true
                            self?.startObservingChanges()
                            
                        case .finished: break
                    }
                },
                receiveValue: { [weak self] settingsData in
                    self?.dataStreamJustFailed = false
                    self?.handleSettingsUpdates(settingsData)
                }
            )
    }
    
    private func stopObservingChanges() {
        // Stop observing database changes
        dataChangeCancellable?.cancel()
    }
    
    private func handleSettingsUpdates(_ updatedData: [SectionModel], initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialSettingsData else {
            hasLoadedInitialSettingsData = true
            UIView.performWithoutAnimation { handleSettingsUpdates(updatedData, initialLoad: true) }
            return
        }
        
        // Reload the table content (animate changes after the first load)
        tableView.reload(
            using: StagedChangeset(source: viewModel.settingsData, target: updatedData),
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .bottom,
            insertRowsAnimation: .none,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }    // Prevent too many changes from causing performance issues
        ) { [weak self] updatedData in
            self?.viewModel.updateSettings(updatedData)
        }
    }
    
    // MARK: - Binding

    private func setupBinding() {
        viewModel.isEditing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEditing in
                self?.setEditing(isEditing, animated: true)
                
                self?.tableView.visibleCells.forEach { cell in
                    switch cell {
                        case let cell as SessionCell:
                            cell.update(isEditing: isEditing, animated: true)
                            
                        case let avatarCell as SessionAvatarCell:
                            avatarCell.update(isEditing: isEditing, animated: true)
                            
                        default: break
                    }
                }
            }
            .store(in: &disposables)
        
        viewModel.leftNavItems
            .receiveOnMain(immediately: true)
            .sink { [weak self] maybeItems in
                self?.navigationItem.setLeftBarButtonItems(
                    maybeItems.map { items in
                        items.map { item -> DisposableBarButtonItem in
                            let buttonItem: DisposableBarButtonItem = item.createBarButtonItem()
                            buttonItem.themeTintColor = .textPrimary

                            buttonItem.tapPublisher
                                .map { _ in item.id }
                                .handleEvents(receiveOutput: { _ in item.action?() })
                                .sink(into: self?.viewModel.navItemTapped)
                                .store(in: &buttonItem.disposables)

                            return buttonItem
                        }
                    },
                    animated: true
                )
            }
            .store(in: &disposables)

        viewModel.rightNavItems
            .receiveOnMain(immediately: true)
            .sink { [weak self] maybeItems in
                self?.navigationItem.setRightBarButtonItems(
                    maybeItems.map { items in
                        items.map { item -> DisposableBarButtonItem in
                            let buttonItem: DisposableBarButtonItem = item.createBarButtonItem()
                            buttonItem.themeTintColor = .textPrimary

                            buttonItem.tapPublisher
                                .map { _ in item.id }
                                .handleEvents(receiveOutput: { _ in item.action?() })
                                .sink(into: self?.viewModel.navItemTapped)
                                .store(in: &buttonItem.disposables)

                            return buttonItem
                        }
                    },
                    animated: true
                )
            }
            .store(in: &disposables)
        
        viewModel.showToast
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text, color in
                guard let view: UIView = self?.view else { return }
                
                let toastController: ToastController = ToastController(text: text, background: color)
                toastController.presentToastView(fromBottomOfView: view, inset: Values.largeSpacing)
            }
            .store(in: &disposables)
        
        viewModel.transitionToScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] viewController, transitionType in
                switch transitionType {
                    case .push:
                        self?.navigationController?.pushViewController(viewController, animated: true)
                    
                    case .present:
                        if UIDevice.current.isIPad {
                            viewController.popoverPresentationController?.permittedArrowDirections = []
                            viewController.popoverPresentationController?.sourceView = self?.view
                            viewController.popoverPresentationController?.sourceRect = (self?.view.bounds ?? UIScreen.main.bounds)
                        }
                        
                        self?.present(viewController, animated: true)
                }
            }
            .store(in: &disposables)
        
        viewModel.dismissScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dismissType in
                switch dismissType {
                    case .auto:
                        guard
                            let viewController: UIViewController = self,
                            (self?.navigationController?.viewControllers
                                .firstIndex(of: viewController))
                                .defaulting(to: 0) > 0
                        else {
                            self?.dismiss(animated: true)
                            return
                        }
                        
                        self?.navigationController?.popViewController(animated: true)
                        
                    case .dismiss: self?.dismiss(animated: true)
                    case .pop: self?.navigationController?.popViewController(animated: true)
                }
            }
            .store(in: &disposables)
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.viewModel.settingsData.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.viewModel.settingsData[section].elements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: SectionModel = viewModel.settingsData[indexPath.section]
        let info: SessionCell.Info<SettingItem> = section.elements[indexPath.row]
        
        switch info.leftAccessory {
            case .threadInfo(let threadViewModel, let style, let avatarTapped, let titleTapped, let titleChanged):
                let cell: SessionAvatarCell = tableView.dequeue(type: SessionAvatarCell.self, for: indexPath)
                cell.update(
                    threadViewModel: threadViewModel,
                    style: style,
                    viewController: self
                )
                cell.update(isEditing: self.isEditing, animated: false)
                
                cell.profilePictureTapPublisher
                    .filter { _ in threadViewModel.threadVariant == .contact }
                    .sink(receiveValue: { _ in avatarTapped?() })
                    .store(in: &cell.disposables)
                
                cell.displayNameTapPublisher
                    .filter { _ in threadViewModel.threadVariant == .contact }
                    .sink(receiveValue: { _ in titleTapped?() })
                    .store(in: &cell.disposables)
                
                cell.textPublisher
                    .sink(receiveValue: { text in titleChanged?(text) })
                    .store(in: &cell.disposables)
                
                return cell
                
            default:
                let cell: SessionCell = tableView.dequeue(type: SessionCell.self, for: indexPath)
                cell.update(
                    with: info,
                    style: .rounded,
                    position: Position.with(indexPath.row, count: section.elements.count)
                )
                cell.update(isEditing: self.isEditing, animated: false)
                
                return cell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section: SectionModel = viewModel.settingsData[section]
        
        switch section.model.style {
            case .none:
                return UIView()
            
            case .padding, .title:
                let result: SessionHeaderView = tableView.dequeueHeaderFooterView(type: SessionHeaderView.self)
                result.update(
                    title: section.model.title,
                    hasSeparator: (section.elements.first?.shouldHaveBackground != false)
                )
                
                return result
        }
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let section: SectionModel = viewModel.settingsData[section]
        
        switch section.model.style {
            case .none: return 0
            case .padding, .title: return UITableView.automaticDimension
        }
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let section: SectionModel = self.viewModel.settingsData[indexPath.section]
        let info: SessionCell.Info<SettingItem> = section.elements[indexPath.row]
        
        // Do nothing if the item is disabled
        guard info.isEnabled else { return }
        
        // Get the view that was tapped (for presenting on iPad)
        let tappedView: UIView? = {
            guard let cell: SessionCell = tableView.cellForRow(at: indexPath) as? SessionCell else {
                return nil
            }
            
            switch (info.leftAccessory, info.rightAccessory) {
                case (_, .highlightingBackgroundLabel(_)):
                    return (!cell.rightAccessoryView.isHidden ? cell.rightAccessoryView : cell)
                    
                case (.highlightingBackgroundLabel(_), _):
                    return (!cell.leftAccessoryView.isHidden ? cell.leftAccessoryView : cell)
                
                default:
                    return cell
            }
        }()
        let maybeOldSelection: (Int, SessionCell.Info<SettingItem>)? = section.elements
            .enumerated()
            .first(where: { index, info in
                switch (info.leftAccessory, info.rightAccessory) {
                    case (_, .radio(_, let isSelected, _)): return isSelected()
                    case (.radio(_, let isSelected, _), _): return isSelected()
                    default: return false
                }
            })
        
        let performAction: () -> Void = { [weak self, weak tappedView] in
            info.onTap?(tappedView)
            self?.manuallyReload(indexPath: indexPath, section: section, info: info)
            
            // Update the old selection as well
            if let oldSelection: (index: Int, info: SessionCell.Info<SettingItem>) = maybeOldSelection {
                self?.manuallyReload(
                    indexPath: IndexPath(
                        row: oldSelection.index,
                        section: indexPath.section
                    ),
                    section: section,
                    info: oldSelection.info
                )
            }
        }
        
        guard
            let confirmationInfo: ConfirmationModal.Info = info.confirmationInfo,
            confirmationInfo.stateToShow.shouldShow(for: info.currentBoolValue)
        else {
            performAction()
            return
        }

        // Show a confirmation modal before continuing
        let confirmationModal: ConfirmationModal = ConfirmationModal(
            targetView: tappedView,
            info: confirmationInfo
                .with(onConfirm: { [weak self] _ in
                    performAction()
                    self?.dismiss(animated: true)
                })
        )
        present(confirmationModal, animated: true, completion: nil)
    }
    
    private func manuallyReload(
        indexPath: IndexPath,
        section: SectionModel,
        info: SessionCell.Info<SettingItem>
    ) {
        // Try update the existing cell to have a nice animation instead of reloading the cell
        if let existingCell: SessionCell = tableView.cellForRow(at: indexPath) as? SessionCell {
            existingCell.update(
                with: info,
                style: .rounded,
                position: Position.with(indexPath.row, count: section.elements.count)
            )
        }
        else {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}
