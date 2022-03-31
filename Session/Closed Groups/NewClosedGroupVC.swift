import PromiseKit

private protocol TableViewTouchDelegate {
    
    func tableViewWasTouched(_ tableView: TableView)
}

private final class TableView : UITableView {
    var touchDelegate: TableViewTouchDelegate?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        touchDelegate?.tableViewWasTouched(self)
        return super.hitTest(point, with: event)
    }
}

final class NewClosedGroupVC : BaseVC, UITableViewDataSource, UITableViewDelegate, TableViewTouchDelegate, UITextFieldDelegate, UIScrollViewDelegate {
    private let contacts = ContactUtilities.getAllContacts()
    private var selectedContacts: Set<String> = []
    
    // MARK: Components
    private lazy var nameTextField = TextField(placeholder: NSLocalizedString("vc_create_closed_group_text_field_hint", comment: ""))

    private lazy var tableView: TableView = {
        let result = TableView()
        result.dataSource = self
        result.delegate = self
        result.touchDelegate = self
        result.register(UserCell.self, forCellReuseIdentifier: "UserCell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.isScrollEnabled = false
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        let customTitleFontSize = Values.largeFontSize
        setNavBarTitle(NSLocalizedString("vc_create_closed_group_title", comment: ""), customFontSize: customTitleFontSize)
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(createClosedGroup))
        doneButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = doneButton
        // Set up content
        setUpViewHierarchy()
    }

    private func setUpViewHierarchy() {
        if !contacts.isEmpty {
            let mainStackView = UIStackView()
            mainStackView.axis = .vertical
            nameTextField.delegate = self
            let nameTextFieldContainer = UIView()
            nameTextFieldContainer.addSubview(nameTextField)
            nameTextField.pin(.leading, to: .leading, of: nameTextFieldContainer, withInset: Values.largeSpacing)
            nameTextField.pin(.top, to: .top, of: nameTextFieldContainer, withInset: Values.mediumSpacing)
            nameTextFieldContainer.pin(.trailing, to: .trailing, of: nameTextField, withInset: Values.largeSpacing)
            nameTextFieldContainer.pin(.bottom, to: .bottom, of: nameTextField, withInset: Values.largeSpacing)
            mainStackView.addArrangedSubview(nameTextFieldContainer)
            let separator = UIView()
            separator.backgroundColor = Colors.separator
            separator.set(.height, to: Values.separatorThickness)
            mainStackView.addArrangedSubview(separator)
            tableView.set(.height, to: CGFloat(contacts.count * 65)) // A cell is exactly 65 points high
            tableView.set(.width, to: UIScreen.main.bounds.width)
            mainStackView.addArrangedSubview(tableView)
            let scrollView = UIScrollView(wrapping: mainStackView, withInsets: UIEdgeInsets.zero)
            scrollView.showsVerticalScrollIndicator = false
            scrollView.delegate = self
            view.addSubview(scrollView)
            scrollView.set(.width, to: UIScreen.main.bounds.width)
            scrollView.pin(to: view)
        } else {
            let explanationLabel = UILabel()
            explanationLabel.textColor = Colors.text
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.numberOfLines = 0
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.textAlignment = .center
            explanationLabel.text = NSLocalizedString("vc_create_closed_group_empty_state_message", comment: "")
            let createNewPrivateChatButton = Button(style: .prominentOutline, size: .large)
            createNewPrivateChatButton.setTitle(NSLocalizedString("vc_create_closed_group_empty_state_button_title", comment: ""), for: UIControl.State.normal)
            createNewPrivateChatButton.addTarget(self, action: #selector(createNewDM), for: UIControl.Event.touchUpInside)
            createNewPrivateChatButton.set(.width, to: 196)
            let stackView = UIStackView(arrangedSubviews: [ explanationLabel, createNewPrivateChatButton ])
            stackView.axis = .vertical
            stackView.spacing = Values.mediumSpacing
            stackView.alignment = .center
            view.addSubview(stackView)
            stackView.center(.horizontal, in: view)
            let verticalCenteringConstraint = stackView.center(.vertical, in: view)
            verticalCenteringConstraint.constant = -16 // Makes things appear centered visually
        }
    }
    
    // MARK: Table View Data Source
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell") as! UserCell
        let publicKey = contacts[indexPath.row]
        cell.publicKey = publicKey
        let isSelected = selectedContacts.contains(publicKey)
        cell.accessory = .tick(isSelected: isSelected)
        cell.update()
        return cell
    }
    
    // MARK: Interaction
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
        let publicKey = contacts[indexPath.row]
        if !selectedContacts.contains(publicKey) { selectedContacts.insert(publicKey) } else { selectedContacts.remove(publicKey) }
        guard let cell = tableView.cellForRow(at: indexPath) as? UserCell else { return }
        let isSelected = selectedContacts.contains(publicKey)
        cell.accessory = .tick(isSelected: isSelected)
        cell.update()
        tableView.deselectRow(at: indexPath, animated: true)
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
        guard name.count < 64 else {
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
            var promise: Promise<TSGroupThread>!
            Storage.writeSync { transaction in
                promise = MessageSender.createClosedGroup(name: name, members: selectedContacts, transaction: transaction)
            }
            let _ = promise.done(on: DispatchQueue.main) { thread in
                MessageSender.syncConfiguration(forceSyncNow: true).retainUntilComplete()
                self?.presentingViewController?.dismiss(animated: true, completion: nil)
                SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
            }
            promise.catch(on: DispatchQueue.main) { _ in
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                let title = "Couldn't Create Group"
                let message = "Please check your internet connection and try again."
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
                self?.presentAlert(alert)
            }
        }
    }
    
    @objc private func createNewDM() {
        presentingViewController?.dismiss(animated: true, completion: nil)
        SignalApp.shared().homeViewController!.createNewDM()
    }
}
