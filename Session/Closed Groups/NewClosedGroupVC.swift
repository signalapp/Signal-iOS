// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import PromiseKit
import SessionUIKit
import SessionMessagingKit
import SignalUtilitiesKit

private protocol TableViewTouchDelegate {
    func tableViewWasTouched(_ tableView: TableView)
}

private final class TableView: UITableView {
    var touchDelegate: TableViewTouchDelegate?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        touchDelegate?.tableViewWasTouched(self)
        return super.hitTest(point, with: event)
    }
}

final class NewClosedGroupVC: BaseVC, UITableViewDataSource, UITableViewDelegate, TableViewTouchDelegate, UITextFieldDelegate, UIScrollViewDelegate {
    private enum Section: Int, Differentiable, Equatable, Hashable {
        case contacts
    }
    
    private let contactProfiles: [Profile] = Profile.fetchAllContactProfiles(excludeCurrentUser: true)
    private lazy var data: [ArraySection<Section, Profile>] = [
        ArraySection(model: .contacts, elements: contactProfiles)
    ]
    private var selectedContacts: Set<String> = []
    private var searchText: String = ""
    
    // MARK: - Components
    
    private static let textFieldHeight: CGFloat = 50
    private static let searchBarHeight: CGFloat = (36 + (Values.mediumSpacing * 2))
    
    private lazy var nameTextField: TextField = {
        let result = TextField(
            placeholder: "vc_create_closed_group_text_field_hint".localized(),
            usesDefaultHeight: false,
            customHeight: NewClosedGroupVC.textFieldHeight
        )
        result.set(.height, to: NewClosedGroupVC.textFieldHeight)
        result.themeBorderColor = .borderSeparator
        result.layer.cornerRadius = 13
        result.delegate = self
        
        return result
    }()
    
    private lazy var searchBar: ContactsSearchBar = {
        let result = ContactsSearchBar()
        result.themeTintColor = .textPrimary
        result.themeBackgroundColor = .clear
        result.delegate = self
        result.set(.height, to: NewClosedGroupVC.searchBarHeight)

        return result
    }()
    
    private lazy var headerView: UIView = {
        let result: UIView = UIView(
            frame: CGRect(
                x: 0, y: 0,
                width: UIScreen.main.bounds.width,
                height: (
                    Values.mediumSpacing +
                    NewClosedGroupVC.textFieldHeight +
                    NewClosedGroupVC.searchBarHeight
                )
            )
        )
        result.addSubview(nameTextField)
        result.addSubview(searchBar)
        
        nameTextField.pin(.top, to: .top, of: result, withInset: Values.mediumSpacing)
        nameTextField.pin(.leading, to: .leading, of: result, withInset: Values.largeSpacing)
        nameTextField.pin(.trailing, to: .trailing, of: result, withInset: -Values.largeSpacing)
        
        // Note: The top & bottom padding is built into the search bar
        searchBar.pin(.top, to: .bottom, of: nameTextField)
        searchBar.pin(.leading, to: .leading, of: result, withInset: Values.largeSpacing)
        searchBar.pin(.trailing, to: .trailing, of: result, withInset: -Values.largeSpacing)
        searchBar.pin(.bottom, to: .bottom, of: result)
        
        return result
    }()

    private lazy var tableView: TableView = {
        let result: TableView = TableView()
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        result.tableHeaderView = headerView
        result.contentInset = UIEdgeInsets(
            top: 0,
            leading: 0,
            bottom: Values.footerGradientHeight(window: UIApplication.shared.keyWindow),
            trailing: 0
        )
        result.register(view: SessionCell.self)
        result.touchDelegate = self
        result.dataSource = self
        result.delegate = self
        
        if #available(iOS 15.0, *) {
            result.sectionHeaderTopPadding = 0
        }
        
        return result
    }()
    
    private lazy var fadeView: GradientView = {
        let result: GradientView = GradientView()
        result.themeBackgroundGradient = [
            .value(.backgroundSecondary, alpha: 0), // Want this to take up 20% (~25pt)
            .backgroundSecondary,
            .backgroundSecondary,
            .backgroundSecondary,
            .backgroundSecondary
        ]
        result.set(.height, to: Values.footerGradientHeight(window: UIApplication.shared.keyWindow))
        
        return result
    }()
    
    private lazy var createGroupButton: SessionButton = {
        let result = SessionButton(style: .bordered, size: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle("CREATE_GROUP_BUTTON_TITLE".localized(), for: .normal)
        result.addTarget(self, action: #selector(createClosedGroup), for: .touchUpInside)
        result.set(.width, to: 160)
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundSecondary
        
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle("vc_create_closed_group_title".localized(), customFontSize: customTitleFontSize)
        
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.themeTintColor = .textPrimary
        navigationItem.rightBarButtonItem = closeButton
        
        // Set up content
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        guard !contactProfiles.isEmpty else {
            let explanationLabel: UILabel = UILabel()
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.text = "vc_create_closed_group_empty_state_message".localized()
            explanationLabel.themeTextColor = .textPrimary
            explanationLabel.textAlignment = .center
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.numberOfLines = 0
            
            let createNewPrivateChatButton: SessionButton = SessionButton(style: .bordered, size: .medium)
            createNewPrivateChatButton.setTitle("vc_create_closed_group_empty_state_button_title".localized(), for: .normal)
            createNewPrivateChatButton.addTarget(self, action: #selector(createNewDM), for: .touchUpInside)
            createNewPrivateChatButton.set(.width, to: 196)
            
            let stackView: UIStackView = UIStackView(arrangedSubviews: [ explanationLabel, createNewPrivateChatButton ])
            stackView.axis = .vertical
            stackView.spacing = Values.mediumSpacing
            stackView.alignment = .center
            view.addSubview(stackView)
            stackView.center(.horizontal, in: view)
            
            let verticalCenteringConstraint = stackView.center(.vertical, in: view)
            verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
            return
        }
        
        view.addSubview(tableView)
        tableView.pin(.top, to: .top, of: view)
        tableView.pin(.leading, to: .leading, of: view)
        tableView.pin(.trailing, to: .trailing, of: view)
        tableView.pin(.bottom, to: .bottom, of: view)
        
        view.addSubview(fadeView)
        fadeView.pin(.leading, to: .leading, of: view)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
        
        view.addSubview(createGroupButton)
        createGroupButton.center(.horizontal, in: view)
        createGroupButton.pin(.bottom, to: .bottom, of: view.safeAreaLayoutGuide, withInset: -Values.smallSpacing)
    }
    
    // MARK: - Table View Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data[section].elements.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: SessionCell = tableView.dequeue(type: SessionCell.self, for: indexPath)
        let profile: Profile = data[indexPath.section].elements[indexPath.row]
        cell.update(
            with: SessionCell.Info(
                id: profile,
                leftAccessory: .profile(profile.id, profile),
                title: profile.displayName(),
                rightAccessory: .radio(isSelected: { [weak self] in
                    self?.selectedContacts.contains(profile.id) == true
                })
            ),
            style: .edgeToEdge,
            position: Position.with(indexPath.row, count: data[indexPath.section].elements.count)
        )
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let profileId: String = data[indexPath.section].elements[indexPath.row].id
        
        if !selectedContacts.contains(profileId) {
            selectedContacts.insert(profileId)
        }
        else {
            selectedContacts.remove(profileId)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let nameTextFieldCenterY = nameTextField.convert(nameTextField.bounds.center, to: scrollView).y
        let shouldShowGroupNameInTitle: Bool = (scrollView.contentOffset.y > nameTextFieldCenterY)
        let groupNameLabelVisible: Bool = (crossfadeLabel.alpha >= 1)
        
        switch (shouldShowGroupNameInTitle, groupNameLabelVisible) {
            case (true, false):
                UIView.animate(withDuration: 0.2) {
                    self.navBarTitleLabel.alpha = 0
                    self.crossfadeLabel.alpha = 1
                }
                
            case (false, true):
                UIView.animate(withDuration: 0.2) {
                    self.navBarTitleLabel.alpha = 1
                    self.crossfadeLabel.alpha = 0
                }
                
            default: break
        }
    }
    
    // MARK: - Interaction
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        crossfadeLabel.text = (textField.text?.isEmpty == true ?
            "vc_create_closed_group_title".localized() :
            textField.text
        )
    }

    fileprivate func tableViewWasTouched(_ tableView: TableView) {
        if nameTextField.isFirstResponder {
            nameTextField.resignFirstResponder()
        }
    }
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func createClosedGroup() {
        func showError(title: String, message: String = "") {
            let modal: ConfirmationModal = ConfirmationModal(
                info: ConfirmationModal.Info(
                    title: title,
                    explanation: message,
                    cancelTitle: "BUTTON_OK".localized(),
                    cancelStyle: .alert_text
                )
            )
            present(modal, animated: true)
        }
        guard
            let name: String = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            name.count > 0
        else {
            return showError(title: "vc_create_closed_group_group_name_missing_error".localized())
        }
        guard name.count < 30 else {
            return showError(title: "vc_create_closed_group_group_name_too_long_error".localized())
        }
        guard selectedContacts.count >= 1 else {
            return showError(title: "Please pick at least 1 group member")
        }
        guard selectedContacts.count < 100 else { // Minus one because we're going to include self later
            return showError(title: "vc_create_closed_group_too_many_group_members_error".localized())
        }
        let selectedContacts = self.selectedContacts
        let message: String? = (selectedContacts.count > 20) ? "Please wait while the group is created..." : nil
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, message: message) { [weak self] _ in
            Storage.shared
                .writeAsync { db in
                    try MessageSender.createClosedGroup(db, name: name, members: selectedContacts)
                }
                .done(on: DispatchQueue.main) { thread in
                    Storage.shared.writeAsync { db in
                        try? MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                    }
                    
                    self?.presentingViewController?.dismiss(animated: true, completion: nil)
                    SessionApp.presentConversation(for: thread.id, action: .compose, animated: false)
                }
                .catch(on: DispatchQueue.main) { [weak self] _ in
                    self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                    
                    let modal: ConfirmationModal = ConfirmationModal(
                        targetView: self?.view,
                        info: ConfirmationModal.Info(
                            title: "Couldn't Create Group",
                            explanation: "Please check your internet connection and try again.",
                            cancelTitle: "BUTTON_OK".localized(),
                            cancelStyle: .alert_text
                        )
                    )
                    self?.present(modal, animated: true)
                }
                .retainUntilComplete()
        }
    }
    
    @objc private func createNewDM() {
        presentingViewController?.dismiss(animated: true, completion: nil)
        
        SessionApp.homeViewController.wrappedValue?.createNewDM()
    }
}

extension NewClosedGroupVC: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        
        let changeset: StagedChangeset<[ArraySection<Section, Profile>]> = StagedChangeset(
            source: data,
            target: [
                ArraySection(
                    model: .contacts,
                    elements: (searchText.isEmpty ?
                        contactProfiles :
                        contactProfiles
                            .filter { $0.displayName().range(of: searchText, options: [.caseInsensitive]) != nil }
                    )
                )
            ]
        )
        
        self.tableView.reload(
            using: changeset,
            deleteSectionsAnimation: .none,
            insertSectionsAnimation: .none,
            reloadSectionsAnimation: .none,
            deleteRowsAnimation: .none,
            insertRowsAnimation: .none,
            reloadRowsAnimation: .none,
            interrupt: { $0.changeCount > 100 }
        ) { [weak self] updatedData in
            self?.data = updatedData
        }
    }
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.setShowsCancelButton(true, animated: true)
        return true
    }
    
    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.setShowsCancelButton(false, animated: true)
        return true
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}
