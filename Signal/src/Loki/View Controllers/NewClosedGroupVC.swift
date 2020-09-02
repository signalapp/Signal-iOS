import PromiseKit

final class NewClosedGroupVC : BaseVC, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIScrollViewDelegate {
    private var selectedContacts: Set<String> = []
    
    private lazy var contacts: [String] = {
        var result: [String] = []
        let storage = OWSPrimaryStorage.shared()
        storage.dbReadConnection.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSContactThread, thread.shouldThreadBeVisible else { return }
                let publicKey = thread.contactIdentifier()
                guard UserDisplayNameUtilities.getPrivateChatDisplayName(for: publicKey) != nil else { return }
                // We shouldn't be able to add slave devices to groups
                guard storage.getMasterHexEncodedPublicKey(for: publicKey, in: transaction) == nil else { return }
                result.append(publicKey)
            }
        }
        func getDisplayName(for hexEncodedPublicKey: String) -> String {
            return UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
        }
        let userPublicKey = getUserHexEncodedPublicKey()
        var userLinkedDevices: Set<String> = [ userPublicKey ]
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userPublicKey, in: transaction)
        }
        result = result.filter { !userLinkedDevices.contains($0) }
        result = result.sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
        return result
    }()
    
    // MARK: Components
    private lazy var nameTextField = TextField(placeholder: NSLocalizedString("vc_create_closed_group_text_field_hint", comment: ""))
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
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
            tableView.set(.height, to: CGFloat(contacts.count * 67)) // A cell is exactly 67 points high
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
            createNewPrivateChatButton.addTarget(self, action: #selector(createNewPrivateChat), for: UIControl.Event.touchUpInside)
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
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let contact = contacts[indexPath.row]
        cell.hexEncodedPublicKey = contact
        cell.hasTick = selectedContacts.contains(contact)
        return cell
    }
    
    // MARK: Interaction
    func textFieldDidEndEditing(_ textField: UITextField) {
        crossfadeLabel.text = textField.text!.isEmpty ? NSLocalizedString("vc_create_closed_group_title", comment: "") : textField.text!
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if nameTextField.isFirstResponder {
            nameTextField.resignFirstResponder()
        }
        let nameTextFieldCenterY = nameTextField.convert(nameTextField.bounds.center, to: scrollView).y
        let tableViewOriginY = tableView.convert(tableView.bounds.origin, to: scrollView).y
        let titleLabelAlpha = 1 - (scrollView.contentOffset.y - nameTextFieldCenterY) / (tableViewOriginY - nameTextFieldCenterY)
        let crossfadeLabelAlpha = 1 - titleLabelAlpha
        navBarTitleLabel.alpha = titleLabelAlpha
        crossfadeLabel.alpha = crossfadeLabelAlpha
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let contact = contacts[indexPath.row]
        if !selectedContacts.contains(contact) {
            selectedContacts.insert(contact)
        } else {
            selectedContacts.remove(contact)
        }
        guard let cell = tableView.cellForRow(at: indexPath) as? Cell else { return }
        cell.hasTick = selectedContacts.contains(contact)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func createClosedGroup() {
        if ClosedGroupsProtocol.isSharedSenderKeysEnabled {
            createSSKClosedGroup()
        } else {
            createLegacyClosedGroup()
        }
    }

    private func createSSKClosedGroup() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
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
        guard selectedContacts.count < ClosedGroupsProtocol.groupSizeLimit else { // Minus one because we're going to include self later
            return showError(title: NSLocalizedString("vc_create_closed_group_too_many_group_members_error", comment: ""))
        }
        let selectedContacts = self.selectedContacts
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] _ in
            FileServerAPI.getDeviceLinks(associatedWith: selectedContacts).then2 { _ -> Promise<TSGroupThread> in
                var promise: Promise<TSGroupThread>!
                try! Storage.writeSync { transaction in
                    promise = ClosedGroupsProtocol.createClosedGroup(name: name, members: selectedContacts, transaction: transaction)
                }
                return promise
            }.done(on: DispatchQueue.main) { thread in
                self?.presentingViewController?.dismiss(animated: true, completion: nil)
                SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
            }.catch(on: DispatchQueue.main) { _ in
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                let title = "Couldn't Create Group"
                let message = "Please check your internet connection and try again."
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
                self?.presentAlert(alert)
            }
        }
    }

    private func createLegacyClosedGroup() {
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
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
        guard selectedContacts.count < 10 else { // Minus one because we're going to include self later
            return showError(title: NSLocalizedString("vc_create_closed_group_too_many_group_members_error", comment: ""))
        }
        let userPublicKey = getUserHexEncodedPublicKey()
        let storage = OWSPrimaryStorage.shared()
        var masterPublicKey = ""
        storage.dbReadConnection.read { transaction in
            masterPublicKey = storage.getMasterHexEncodedPublicKey(for: userPublicKey, in: transaction) ?? userPublicKey
        }
        let members = selectedContacts + [ masterPublicKey ]
        let admins = [ masterPublicKey ]
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(Randomness.generateRandomBytes(kGroupIdLength)!.toHexString())
        let group = TSGroupModel(title: name, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group)
        OWSProfileManager.shared().addThread(toProfileWhitelist: thread)
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            let message = TSOutgoingMessage(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
            message.update(withCustomMessage: "Closed group created")
            DispatchQueue.main.async {
                SSKEnvironment.shared.messageSender.send(message, success: {
                    DispatchQueue.main.async {
                        self?.presentingViewController?.dismiss(animated: true, completion: nil)
                        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
                    }
                }, failure: { error in
                    let message = TSErrorMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, failedMessageType: .groupCreationFailed)
                    message.save()
                    DispatchQueue.main.async {
                        self?.presentingViewController?.dismiss(animated: true, completion: nil)
                        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
                    }
                })
            }
        }
    }
    
    @objc private func createNewPrivateChat() {
        presentingViewController?.dismiss(animated: true, completion: nil)
        SignalApp.shared().homeViewController!.createNewPrivateChat()
    }
}

// MARK: - Cell

private extension NewClosedGroupVC {
    
    final class Cell : UITableViewCell {
        var hexEncodedPublicKey = "" { didSet { update() } }
        var hasTick = false { didSet { update() } }
        
        // MARK: Components
        private lazy var profilePictureView = ProfilePictureView()
        
        private lazy var displayNameLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        private lazy var tickImageView: UIImageView = {
            let result = UIImageView()
            result.contentMode = .scaleAspectFit
            let size: CGFloat = 24
            result.set(.width, to: size)
            result.set(.height, to: size)
            return result
        }()
        
        private lazy var separator: UIView = {
            let result = UIView()
            result.backgroundColor = Colors.separator
            result.set(.height, to: Values.separatorThickness)
            return result
        }()
        
        // MARK: Initialization
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            setUpViewHierarchy()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }
        
        private func setUpViewHierarchy() {
            // Set the cell background color
            backgroundColor = Colors.cellBackground
            // Set up the highlight color
            let selectedBackgroundView = UIView()
            selectedBackgroundView.backgroundColor = .clear // Disabled for now
            self.selectedBackgroundView = selectedBackgroundView
            // Set up the profile picture image view
            let profilePictureViewSize = Values.smallProfilePictureSize
            profilePictureView.set(.width, to: profilePictureViewSize)
            profilePictureView.set(.height, to: profilePictureViewSize)
            profilePictureView.size = profilePictureViewSize
            // Set up the main stack view
            let stackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel, tickImageView ])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = Values.mediumSpacing
            stackView.set(.height, to: profilePictureViewSize)
            contentView.addSubview(stackView)
            stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
            stackView.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.mediumSpacing)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            // Set up the separator
            addSubview(separator)
            separator.pin(.leading, to: .leading, of: self)
            separator.pin(.bottom, to: .bottom, of: self)
            separator.set(.width, to: UIScreen.main.bounds.width)
        }
        
        // MARK: Updating
        private func update() {
            profilePictureView.hexEncodedPublicKey = hexEncodedPublicKey
            profilePictureView.update()
            displayNameLabel.text = UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
            let icon = hasTick ? #imageLiteral(resourceName: "CircleCheck") : #imageLiteral(resourceName: "Circle")
            tickImageView.image = icon.asTintedImage(color: Colors.text)!
        }
    }
}
