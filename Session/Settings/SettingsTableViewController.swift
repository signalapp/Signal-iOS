// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import Combine
import GRDB
import DifferenceKit
import SessionUIKit
import SessionUtilitiesKit
import SignalUtilitiesKit

protocol SettingsViewModelAccessible {
    var viewModelType: AnyObject.Type { get }
}

class SettingsTableViewController<NavItemId: Equatable, Section: SettingSection, SettingItem: Hashable & Differentiable>: BaseVC, UITableViewDataSource, UITableViewDelegate, SettingsViewModelAccessible {
    typealias SectionModel = SettingsTableViewModel<NavItemId, Section, SettingItem>.SectionModel
    
    private let viewModel: SettingsTableViewModel<NavItemId, Section, SettingItem>
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
        result.register(view: SettingsAvatarCell.self)
        result.register(view: SettingsCell.self)
        result.registerHeaderFooterView(view: SettingHeaderView.self)
        result.dataSource = self
        result.delegate = self
        
        if #available(iOS 15.0, *) {
            result.sectionHeaderTopPadding = 0
        }
        
        return result
    }()
    
    // MARK: - Initialization
    
    init(viewModel: SettingsTableViewModel<NavItemId, Section, SettingItem>) {
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
                        case let settingsCell as SettingsCell:
                            settingsCell.update(isEditing: isEditing, animated: true)
                            
                        case let avatarCell as SettingsAvatarCell:
                            avatarCell.update(isEditing: isEditing, animated: true)
                            
                        default: break
                    }
                }
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
        
        viewModel.closeScreen
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldDismiss in
                guard shouldDismiss else {
                    self?.navigationController?.popViewController(animated: true)
                    return
                }
                
                self?.navigationController?.dismiss(animated: true)
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
        let settingInfo: SettingInfo<SettingItem> = section.elements[indexPath.row]
        
        switch settingInfo.action {
            case .threadInfo(let threadViewModel, let style, let avatarTapped, let titleTapped, let titleChanged):
                let cell: SettingsAvatarCell = tableView.dequeue(type: SettingsAvatarCell.self, for: indexPath)
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
                let cell: SettingsCell = tableView.dequeue(type: SettingsCell.self, for: indexPath)
                cell.update(
                    icon: settingInfo.icon,
                    iconSize: settingInfo.iconSize,
                    iconSetter: settingInfo.iconSetter,
                    title: settingInfo.title,
                    subtitle: settingInfo.subtitle,
                    alignment: settingInfo.alignment,
                    accessibilityIdentifier: settingInfo.accessibilityIdentifier,
                    subtitleExtraViewGenerator: settingInfo.subtitleExtraViewGenerator,
                    action: settingInfo.action,
                    extraActionTitle: settingInfo.extraActionTitle,
                    onExtraAction: settingInfo.onExtraAction,
                    position: {
                        guard section.elements.count > 1 else { return .individual }
                        
                        switch indexPath.row {
                            case 0: return .top
                            case (section.elements.count - 1): return .bottom
                            default: return .middle
                        }
                    }()
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
                let result: SettingHeaderView = tableView.dequeueHeaderFooterView(type: SettingHeaderView.self)
                result.update(
                    title: section.model.title,
                    hasSeparator: (section.elements.first?.action.shouldHaveBackground != false)
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
        let settingInfo: SettingInfo<SettingItem> = section.elements[indexPath.row]

        switch settingInfo.action {
            case .threadInfo: break
            
            case .trigger(_, let action):
                action()
                
            case .rightButtonAction(_, let action):
                guard let cell: SettingsCell = tableView.cellForRow(at: indexPath) as? SettingsCell else {
                    return
                }
                
                action(cell.rightActionButtonContainerView)
                
            case .userDefaultsBool(let defaults, let key, let isEnabled, let onChange):
                guard isEnabled else { return }
                
                defaults.set(!defaults.bool(forKey: key), forKey: key)
                manuallyReload(indexPath: indexPath, section: section, settingInfo: settingInfo)
                onChange?()
                
            case .settingBool(let key, let confirmationInfo, let isEnabled):
                guard isEnabled else { return }
                guard
                    let confirmationInfo: ConfirmationModal.Info = confirmationInfo,
                    confirmationInfo.stateToShow.shouldShow(for: Storage.shared[key])
                else {
                    Storage.shared.write { db in db[key] = !db[key] }
                    manuallyReload(indexPath: indexPath, section: section, settingInfo: settingInfo)
                    return
                }
                
                // Show a confirmation modal before continuing
                let confirmationModal: ConfirmationModal = ConfirmationModal(
                    info: confirmationInfo
                        .with(onConfirm: { [weak self] _ in
                            Storage.shared.write { db in db[key] = !db[key] }
                            self?.manuallyReload(indexPath: indexPath, section: section, settingInfo: settingInfo)
                            self?.dismiss(animated: true)
                        })
                )
                present(confirmationModal, animated: true, completion: nil)
            
            case .customToggle(let value, let isEnabled, let confirmationInfo, let onChange):
                guard isEnabled else { return }
                
                let updatedValue: Bool = !value
                let performChange: () -> () = { [weak self] in
                    self?.manuallyReload(
                        indexPath: indexPath,
                        section: section,
                        settingInfo: settingInfo
                            .with(
                                action: .customToggle(
                                    value: updatedValue,
                                    isEnabled: isEnabled,
                                    onChange: onChange
                                )
                            )
                    )
                    onChange?(updatedValue)
                    
                    // In this case we need to restart the database observation to force a re-query as
                    // the change here might not actually trigger a database update so the content wouldn't
                    // be updated
                    self?.stopObservingChanges()
                    self?.startObservingChanges()
                }
                
                guard
                    let confirmationInfo: ConfirmationModal.Info = confirmationInfo,
                    confirmationInfo.stateToShow.shouldShow(for: value)
                else {
                    performChange()
                    return
                }
                
                // Show a confirmation modal before continuing
                let confirmationModal: ConfirmationModal = ConfirmationModal(
                    info: confirmationInfo
                        .with(onConfirm: { [weak self] _ in
                            performChange()
                            
                            self?.dismiss(animated: true) {
                                guard let strongSelf: UIViewController = self else { return }
                                
                                confirmationInfo.onConfirm?(strongSelf)
                            }
                        })
                )
                present(confirmationModal, animated: true, completion: nil)
            
            case .push(_, _, _, let createDestination), .settingEnum(_, _, let createDestination), .generalEnum(_, let createDestination):
                let viewController: UIViewController = createDestination()
                navigationController?.pushViewController(viewController, animated: true)
                
            case .present(_, let createDestination):
                let viewController: UIViewController = createDestination()
                
                if UIDevice.current.isIPad {
                    viewController.popoverPresentationController?.permittedArrowDirections = []
                    viewController.popoverPresentationController?.sourceView = self.view
                    viewController.popoverPresentationController?.sourceRect = self.view.bounds
                }
                
                navigationController?.present(viewController, animated: true)
                
            case .listSelection(_, _, let shouldAutoSave, let selectValue):
                let maybeOldSelection: (Int, SettingInfo<SettingItem>)? = section.elements
                    .enumerated()
                    .first(where: { index, info in
                        switch info.action {
                            case .listSelection(let isSelected, _, _, _): return isSelected()
                            default: return false
                        }
                    })
                
                selectValue()
                manuallyReload(indexPath: indexPath, section: section, settingInfo: settingInfo)
                
                // Update the old selection as well
                if let oldSelection: (index: Int, info: SettingInfo<SettingItem>) = maybeOldSelection {
                    manuallyReload(
                        indexPath: IndexPath(
                            row: oldSelection.index,
                            section: indexPath.section
                        ),
                        section: section,
                        settingInfo: oldSelection.info
                    )
                }
                
                guard shouldAutoSave else { return }
                
                navigationController?.popViewController(animated: true)
        }
    }
    
    private func manuallyReload(
        indexPath: IndexPath,
        section: SectionModel,
        settingInfo: SettingInfo<SettingItem>
    ) {
        // Try update the existing cell to have a nice animation instead of reloading the cell
        if let existingCell: SettingsCell = tableView.cellForRow(at: indexPath) as? SettingsCell {
            existingCell.update(
                icon: settingInfo.icon,
                iconSize: settingInfo.iconSize,
                iconSetter: settingInfo.iconSetter,
                title: settingInfo.title,
                subtitle: settingInfo.subtitle,
                alignment: settingInfo.alignment,
                accessibilityIdentifier: settingInfo.accessibilityIdentifier,
                subtitleExtraViewGenerator: settingInfo.subtitleExtraViewGenerator,
                action: settingInfo.action,
                extraActionTitle: settingInfo.extraActionTitle,
                onExtraAction: settingInfo.onExtraAction,
                position: {
                    guard section.elements.count > 1 else { return .individual }
                    
                    switch indexPath.row {
                        case 0: return .top
                        case (section.elements.count - 1): return .bottom
                        default: return .middle
                    }
                }()
            )
        }
        else {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
}
