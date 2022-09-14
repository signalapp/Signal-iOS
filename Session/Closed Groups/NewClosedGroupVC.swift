// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import PromiseKit
import SessionUIKit
import SessionMessagingKit

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
    private let contactProfiles: [Profile] = Profile.fetchAllContactProfiles(excludeCurrentUser: true)
    private var searchResults: [Profile] {
        return searchText.isEmpty ? contactProfiles : contactProfiles.filter { $0.displayName().range(of: searchText, options: [.caseInsensitive]) != nil }
    }
    private var selectedContacts: Set<String> = []
    private var searchText: String = ""
    
    // MARK: - Components
    
    private lazy var nameTextField: TextField = {
        let result = TextField(
            placeholder: "vc_create_closed_group_text_field_hint".localized(),
            usesDefaultHeight: false,
            customHeight: 50
        )
        result.set(.height, to: 50)
        result.layer.borderColor = Colors.border.withAlphaComponent(0.5).cgColor
        result.layer.cornerRadius = 13
        return result
    }()
    
    private lazy var searchBar: ContactsSearchBar = {
        let result = ContactsSearchBar()
        result.tintColor = Colors.text
        result.backgroundColor = .clear
        result.delegate = self
        return result
    }()

    private lazy var tableView: TableView = {
        let result: TableView = TableView()
        result.dataSource = self
        result.delegate = self
        result.touchDelegate = self
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.isScrollEnabled = false
        result.register(view: UserCell.self)
        
        return result
    }()
    
    private lazy var createGroupButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle(NSLocalizedString("CREATE_GROUP_BUTTON_TITLE", comment: ""), for: .normal)
        result.addTarget(self, action: #selector(createClosedGroup), for: .touchUpInside)
        result.set(.width, to: 160)
        return result
    }()
    
    private lazy var fadeView: UIView = {
        let result = UIView()
        let gradient = Gradients.newClosedGroupVCFade
        result.setHalfWayGradient(
            gradient,
            frame: .init(
                x: 0,
                y: 0,
                width: UIScreen.main.bounds.width,
                height: 150
            )
        )
        result.isUserInteractionEnabled = false
        result.set(.height, to: 150)
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Colors.navigationBarBackground
        setUpNavBarStyle()
        
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle("vc_create_closed_group_title".localized(), customFontSize: customTitleFontSize)
        
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = closeButton
        
        // Set up content
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        guard !contactProfiles.isEmpty else {
            let explanationLabel: UILabel = UILabel()
            explanationLabel.textColor = Colors.text
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.numberOfLines = 0
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.textAlignment = .center
            explanationLabel.text = NSLocalizedString("vc_create_closed_group_empty_state_message", comment: "")
            
            let createNewPrivateChatButton: Button = Button(style: .prominentOutline, size: .large)
            createNewPrivateChatButton.setTitle(NSLocalizedString("vc_create_closed_group_empty_state_button_title", comment: ""), for: UIControl.State.normal)
            createNewPrivateChatButton.addTarget(self, action: #selector(createNewDM), for: UIControl.Event.touchUpInside)
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
        
        let mainStackView: UIStackView = UIStackView()
        mainStackView.axis = .vertical
        nameTextField.delegate = self
        
        let nameTextFieldContainer: UIView = UIView()
        nameTextFieldContainer.addSubview(nameTextField)
        nameTextField.pin(.leading, to: .leading, of: nameTextFieldContainer, withInset: Values.mediumSpacing)
        nameTextField.pin(.top, to: .top, of: nameTextFieldContainer, withInset: Values.mediumSpacing)
        nameTextFieldContainer.pin(.trailing, to: .trailing, of: nameTextField, withInset: Values.mediumSpacing)
        nameTextFieldContainer.pin(.bottom, to: .bottom, of: nameTextField)
        mainStackView.addArrangedSubview(nameTextFieldContainer)
        
        let searchBarContainer: UIView = UIView()
        searchBarContainer.addSubview(searchBar)
        searchBar.pin(.leading, to: .leading, of: searchBarContainer, withInset: Values.smallSpacing)
        searchBarContainer.pin(.trailing, to: .trailing, of: searchBar, withInset: Values.smallSpacing)
        searchBar.pin([ UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: searchBarContainer)
        mainStackView.addArrangedSubview(searchBarContainer)
        
        let separator: UIView = UIView()
        separator.backgroundColor = Colors.separator
        separator.set(.height, to: Values.separatorThickness)
        mainStackView.addArrangedSubview(separator)
        
        tableView.set(.height, to: CGFloat(contactProfiles.count * 65 + 100)) // A cell is exactly 65 points high
        tableView.set(.width, to: UIScreen.main.bounds.width)
        mainStackView.addArrangedSubview(tableView)
        
        let scrollView: UIScrollView = UIScrollView(wrapping: mainStackView, withInsets: UIEdgeInsets.zero)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = self
        view.addSubview(scrollView)
        
        scrollView.set(.width, to: UIScreen.main.bounds.width)
        scrollView.pin(to: view)
        
        view.addSubview(fadeView)
        fadeView.pin(.leading, to: .leading, of: view)
        fadeView.pin(.trailing, to: .trailing, of: view)
        fadeView.pin(.bottom, to: .bottom, of: view)
        
        view.addSubview(createGroupButton)
        createGroupButton.center(.horizontal, in: view)
        createGroupButton.pin(.bottom, to: .bottom, of: view, withInset: -Values.veryLargeSpacing)
    }
    
    @objc override internal func handleAppModeChangedNotification(_ notification: Notification) {
        super.handleAppModeChangedNotification(notification)
        
        let gradient = Gradients.newClosedGroupVCFade
        fadeView.setHalfWayGradient(
            gradient,
            frame: .init(
                x: 0,
                y: 0,
                width: UIScreen.main.bounds.width,
                height: 150
            )
        ) // Re-do the gradient
    }
    
    // MARK: - Table View Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UserCell = tableView.dequeue(type: UserCell.self, for: indexPath)
        cell.update(
            with: searchResults[indexPath.row].id,
            profile: searchResults[indexPath.row],
            isZombie: false,
            accessory: .radio(isSelected: selectedContacts.contains(searchResults[indexPath.row].id))
        )
        
        return cell
    }
    
    // MARK: - Interaction
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        crossfadeLabel.text = textField.text!.isEmpty ? NSLocalizedString("vc_create_closed_group_title", comment: "") : textField.text!
    }

    fileprivate func tableViewWasTouched(_ tableView: TableView) {
        if nameTextField.isFirstResponder {
            nameTextField.resignFirstResponder()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let nameTextFieldCenterY = nameTextField.convert(nameTextField.bounds.center, to: scrollView).y
        let tableViewOriginY = tableView.convert(tableView.bounds.origin, to: scrollView).y
        let titleLabelAlpha = 1 - (scrollView.contentOffset.y - nameTextFieldCenterY) / (tableViewOriginY - nameTextFieldCenterY)
        let crossfadeLabelAlpha = 1 - titleLabelAlpha
        navBarTitleLabel.alpha = titleLabelAlpha
        crossfadeLabel.alpha = crossfadeLabelAlpha
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !selectedContacts.contains(searchResults[indexPath.row].id) {
            selectedContacts.insert(searchResults[indexPath.row].id)
        }
        else {
            selectedContacts.remove(searchResults[indexPath.row].id)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func createClosedGroup() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        guard let name = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), name.count > 0 else {
            return showError(title: NSLocalizedString("vc_create_closed_group_group_name_missing_error", comment: ""))
        }
        guard name.count < 30 else {
            return showError(title: NSLocalizedString("vc_create_closed_group_group_name_too_long_error", comment: ""))
        }
        guard selectedContacts.count >= 1 else {
            return showError(title: "Please pick at least 1 group member")
        }
        guard selectedContacts.count < 100 else { // Minus one because we're going to include self later
            return showError(title: NSLocalizedString("vc_create_closed_group_too_many_group_members_error", comment: ""))
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
                    
                    let title = "Couldn't Create Group"
                    let message = "Please check your internet connection and try again."
                    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
                    self?.presentAlert(alert)
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
        self.tableView.reloadData()
    }
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        searchBar.showsCancelButton = true
        return true
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.showsCancelButton = false
        searchBar.resignFirstResponder()
    }
}
