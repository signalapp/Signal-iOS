// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class SettingsTableViewController<Section: SettingSection, SettingItem: Hashable & Differentiable>: BaseVC, UITableViewDataSource, UITableViewDelegate {
    typealias SectionModel = SettingsTableViewModel<Section, SettingItem>.SectionModel
    
    private let viewModel: SettingsTableViewModel<Section, SettingItem>
    private let shouldShowCloseButton: Bool
    private var dataChangeObservable: DatabaseCancellable?
    private var hasLoadedInitialSettingsData: Bool = false
    
    // MARK: - Components
    
    private lazy var tableView: UITableView = {
        let result: UITableView = UITableView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.showsHorizontalScrollIndicator = false
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
    
    init(viewModel: SettingsTableViewModel<Section, SettingItem>, shouldShowCloseButton: Bool = false) {
        self.viewModel = viewModel
        self.shouldShowCloseButton = shouldShowCloseButton
        
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
        dataChangeObservable = Storage.shared.start(
            viewModel.observableSettingsData,
            // If we haven't done the initial load the trigger it immediately (blocking the main
            // thread so we remain on the launch screen until it completes to be consistent with
            // the old behaviour)
            scheduling: (hasLoadedInitialSettingsData ?
                .async(onQueue: .main) :
                .immediate
            ),
            onError: { _ in },
            onChange: { [weak self] settingsData in
                // The default scheduler emits changes on the main thread
                self?.handleSettingsUpdates(settingsData)
            }
        )
    }
    
    private func stopObservingChanges() {
        // Stop observing database changes
        dataChangeObservable?.cancel()
    }
    
    private func handleSettingsUpdates(_ updatedData: [SectionModel], initialLoad: Bool = false) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialSettingsData else {
            hasLoadedInitialSettingsData = true
            UIView.performWithoutAnimation { handleSettingsUpdates(updatedData, initialLoad: true) }
            return
        }
        
        // Navigation bar
        updateNavigation(updatedData)
        
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
    
    private func updateNavigation(_ data: [SectionModel]) {
        guard
            case .listSelection(_, _, let shouldAutoSave, _) = data.first?.elements.first?.action,
            !shouldAutoSave
        else {
            navigationItem.leftBarButtonItem = {
                guard shouldShowCloseButton else { return nil }
                
                return UIBarButtonItem(
                    image: UIImage(named: "X")?.withRenderingMode(.alwaysTemplate),
                    style: .plain,
                    target: self,
                    action: #selector(closePressed)
                )
            }()
            navigationItem.rightBarButtonItem = nil
            return
        }
        
        let isStoredSelected: Bool = (data.first?.elements ?? []).contains { info in
            switch info.action {
                case .listSelection(let isSelected, let storedSelection, _, _):
                    return (isSelected() && storedSelection)
                    
                default: return false
            }
        }
        
        let cancelButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonPressed))
        cancelButton.themeTintColor = .textPrimary
        navigationItem.leftBarButtonItem = cancelButton
        
        let saveButton: UIBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveButtonPressed))
        saveButton.themeTintColor = .textPrimary
        navigationItem.rightBarButtonItem = (isStoredSelected ? nil : saveButton)
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
        
        let cell: SettingsCell = tableView.dequeue(type: SettingsCell.self, for: indexPath)
        cell.update(
            title: settingInfo.title,
            subtitle: settingInfo.subtitle,
            subtitleExtraViewGenerator: settingInfo.subtitleExtraViewGenerator,
            action: settingInfo.action,
            extraActionTitle: settingInfo.extraActionTitle,
            onExtraAction: settingInfo.onExtraAction,
            isFirstInSection: (indexPath.row == 0),
            isLastInSection: (indexPath.row == (section.elements.count - 1))
        )
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let section: SectionModel = viewModel.settingsData[section]
        let view: SettingHeaderView = tableView.dequeueHeaderFooterView(type: SettingHeaderView.self)
        view.update(
            with: section.model.title,
            hasSeparator: (section.elements.first?.action.shouldHaveBackground != false)
        )
        
        return view
    }
    
    // MARK: - UITableViewDelegate
    
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
            case .trigger(let action):
                action()
                
            case .rightButtonAction(_, let action):
                guard let cell: SettingsCell = tableView.cellForRow(at: indexPath) as? SettingsCell else {
                    return
                }
                
                action(cell.rightActionButtonContainerView)
                
            case .userDefaultsBool(let defaults, let key, let onChange):
                defaults.set(!defaults.bool(forKey: key), forKey: key)
                manuallyReload(indexPath: indexPath, section: section, settingInfo: settingInfo)
                onChange?()
                
            case .settingBool(let key, let confirmationInfo):
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
            
            case .push(let createDestination), .dangerPush(let createDestination),
                    .settingEnum(_, _, let createDestination):
                let viewController: UIViewController = createDestination()
                navigationController?.pushViewController(viewController, animated: true)
                
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
                updateNavigation(viewModel.settingsData)
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
                title: settingInfo.title,
                subtitle: settingInfo.subtitle,
                subtitleExtraViewGenerator: settingInfo.subtitleExtraViewGenerator,
                action: settingInfo.action,
                extraActionTitle: settingInfo.extraActionTitle,
                onExtraAction: settingInfo.onExtraAction,
                isFirstInSection: (indexPath.row == 0),
                isLastInSection: (indexPath.row == (section.elements.count - 1))
            )
        }
        else {
            tableView.reloadRows(at: [indexPath], with: .none)
        }
    }
    
    // MARK: - NavigationActions
    
    @objc private func closePressed() {
        navigationController?.dismiss(animated: true)
    }
    
    @objc private func cancelButtonPressed() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func saveButtonPressed() {
        viewModel.saveChanges()
        
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - SettingHeaderView

class SettingHeaderView: UITableViewHeaderFooterView {
    private lazy var emptyHeightConstraint: NSLayoutConstraint = self.heightAnchor
        .constraint(equalToConstant: (Values.verySmallSpacing * 2))
    private lazy var filledHeightConstraint: NSLayoutConstraint = self.heightAnchor
        .constraint(greaterThanOrEqualToConstant: Values.mediumSpacing)
    
    // MARK: - UI
    
    private let stackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.distribution = .fill
        result.alignment = .fill
        result.isLayoutMarginsRelativeArrangement = true
        
        return result
    }()
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textSecondary
        
        return result
    }()
    
    private let separator: UIView = UIView.separator()
    
    // MARK: - Initialization
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        self.backgroundView = UIView()
        self.backgroundView?.themeBackgroundColor = .backgroundPrimary
        
        addSubview(stackView)
        addSubview(separator)
        
        stackView.addArrangedSubview(titleLabel)
        
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupLayout() {
        stackView.pin(to: self)
        
        separator.pin(.left, to: .left, of: self)
        separator.pin(.right, to: .right, of: self)
        separator.pin(.bottom, to: .bottom, of: self)
    }
    
    // MARK: - Content
    
    fileprivate func update(with title: String, hasSeparator: Bool) {
        titleLabel.text = title
        titleLabel.isHidden = title.isEmpty
        stackView.layoutMargins = UIEdgeInsets(
            top: (title.isEmpty ? Values.verySmallSpacing : Values.mediumSpacing),
            left: Values.largeSpacing,
            bottom: (title.isEmpty ? Values.verySmallSpacing : Values.mediumSpacing),
            right: Values.largeSpacing
        )
        emptyHeightConstraint.isActive = title.isEmpty
        filledHeightConstraint.isActive = !title.isEmpty
        separator.isHidden = !hasSeparator
        
        self.layoutIfNeeded()
    }
}
