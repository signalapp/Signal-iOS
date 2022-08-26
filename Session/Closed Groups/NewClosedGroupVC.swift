// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
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
    private let contactProfiles: [Profile] = Profile.fetchAllContactProfiles(excludeCurrentUser: true)
    private var selectedContacts: Set<String> = []
    
    // MARK: - Components
    
    private lazy var nameTextField = TextField(
        placeholder: "vc_create_closed_group_text_field_hint".localized()
    )

    private lazy var tableView: TableView = {
        let result: TableView = TableView()
        result.separatorStyle = .none
        result.themeBackgroundColor = .clear
        result.register(view: UserCell.self)
        result.touchDelegate = self
        result.dataSource = self
        result.delegate = self
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle("vc_create_closed_group_title".localized(), customFontSize: customTitleFontSize)
        
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.themeTintColor = .textPrimary
        navigationItem.leftBarButtonItem = closeButton
        
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(createClosedGroup))
        doneButton.themeTintColor = .textPrimary
        navigationItem.rightBarButtonItem = doneButton
        
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
            
            let createNewPrivateChatButton: OutlineButton = OutlineButton(style: .regular, size: .medium)
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
        
        let nameTextFieldContainer: UIView = UIView()
        view.addSubview(nameTextFieldContainer)
        nameTextFieldContainer.pin(.top, to: .top, of: view)
        nameTextFieldContainer.pin(.leading, to: .leading, of: view)
        nameTextFieldContainer.pin(.trailing, to: .trailing, of: view)
        
        nameTextFieldContainer.addSubview(nameTextField)
        nameTextField.pin(.top, to: .top, of: nameTextFieldContainer, withInset: Values.mediumSpacing)
        nameTextField.pin(.leading, to: .leading, of: nameTextFieldContainer, withInset: Values.largeSpacing)
        nameTextField.pin(.trailing, to: .trailing, of: nameTextFieldContainer, withInset: -Values.largeSpacing)
        nameTextField.pin(.bottom, to: .bottom, of: nameTextFieldContainer, withInset: -Values.largeSpacing)
        
        view.addSubview(tableView)
        tableView.pin(.top, to: .bottom, of: nameTextFieldContainer, withInset: Values.mediumSpacing)
        tableView.pin(.leading, to: .leading, of: view)
        tableView.pin(.trailing, to: .trailing, of: view)
        tableView.pin(.bottom, to: .bottom, of: view)
    }
    
    // MARK: - Table View Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contactProfiles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UserCell = tableView.dequeue(type: UserCell.self, for: indexPath)
        cell.update(
            with: contactProfiles[indexPath.row].id,
            profile: contactProfiles[indexPath.row],
            isZombie: false,
            accessory: .tick(isSelected: selectedContacts.contains(contactProfiles[indexPath.row].id))
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
        if !selectedContacts.contains(contactProfiles[indexPath.row].id) {
            selectedContacts.insert(contactProfiles[indexPath.row].id)
        }
        else {
            selectedContacts.remove(contactProfiles[indexPath.row].id)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
        tableView.reloadRows(at: [indexPath], with: .none)
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let nameTextFieldCenterY = nameTextField.convert(nameTextField.bounds.center, to: scrollView).y
        let tableViewOriginY = tableView.convert(tableView.bounds.origin, to: scrollView).y
        let titleLabelAlpha = 1 - (scrollView.contentOffset.y - nameTextFieldCenterY) / (tableViewOriginY - nameTextFieldCenterY)
        let crossfadeLabelAlpha = 1 - titleLabelAlpha
        navBarTitleLabel.alpha = titleLabelAlpha
        crossfadeLabel.alpha = crossfadeLabelAlpha
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
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
            presentAlert(alert)
        }
        guard let name = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), name.count > 0 else {
            return showError(title: "vc_create_closed_group_group_name_missing_error".localized())
        }
        guard name.count < 64 else {
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
                    
                    let title = "Couldn't Create Group"
                    let message = "Please check your internet connection and try again."
                    let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
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
