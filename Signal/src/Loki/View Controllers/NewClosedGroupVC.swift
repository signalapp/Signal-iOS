
final class NewClosedGroupVC : BaseVC, UITableViewDataSource, UITableViewDelegate {
    private var selectedContacts: Set<String> = []
    
    private lazy var contacts: [String] = {
        var result: [String] = []
        let storage = OWSPrimaryStorage.shared()
        storage.dbReadConnection.read { transaction in
            TSContactThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSContactThread, thread.isContactFriend else { return }
                let hexEncodedPublicKey = thread.contactIdentifier()
                // We shouldn't be able to add slave devices to groups
                if (storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) == nil) {
                    result.append(hexEncodedPublicKey)
                }
            }
        }
        func getDisplayName(for hexEncodedPublicKey: String) -> String {
            return UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
        }
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        var linkedDeviceHexEncodedPublicKeys: Set<String> = [ userHexEncodedPublicKey ]
        OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
            linkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userHexEncodedPublicKey, in: transaction)
        }
        result = result.filter { !linkedDeviceHexEncodedPublicKeys.contains($0) }
        result = result.sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
        return result
    }()
    
    // MARK: Components
    private lazy var nameTextField = TextField(placeholder: NSLocalizedString("Enter a group name", comment: ""))
    
    private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        let customTitleFontSize = isSmallScreen ? Values.largeFontSize : Values.veryLargeFontSize
        setNavBarTitle(NSLocalizedString("New Closed Group", comment: ""), customFontSize: customTitleFontSize)
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(createClosedGroup))
        doneButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = doneButton
        // Set up content
        if !contacts.isEmpty {
            view.addSubview(nameTextField)
            nameTextField.pin(.leading, to: .leading, of: view, withInset: Values.largeSpacing)
            nameTextField.pin(.top, to: .top, of: view, withInset: Values.mediumSpacing)
            nameTextField.pin(.trailing, to: .trailing, of: view, withInset: -Values.largeSpacing)
            let explanationLabel = UILabel()
            explanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.text = NSLocalizedString("Closed groups support up to 10 members and provide the same privacy protections as one-on-one sessions.", comment: "")
            explanationLabel.numberOfLines = 0
            explanationLabel.textAlignment = .center
            explanationLabel.lineBreakMode = .byWordWrapping
            view.addSubview(explanationLabel)
            explanationLabel.pin(.leading, to: .leading, of: view, withInset: Values.largeSpacing)
            explanationLabel.pin(.top, to: .bottom, of: nameTextField, withInset: Values.mediumSpacing)
            explanationLabel.pin(.trailing, to: .trailing, of: view, withInset: -Values.largeSpacing)
            let separator = UIView()
            separator.backgroundColor = Colors.separator
            separator.set(.height, to: Values.separatorThickness)
            view.addSubview(separator)
            separator.pin(.leading, to: .leading, of: view)
            separator.pin(.top, to: .bottom, of: explanationLabel, withInset: Values.largeSpacing)
            separator.pin(.trailing, to: .trailing, of: view)
            view.addSubview(tableView)
            tableView.pin(.leading, to: .leading, of: view)
            tableView.pin(.top, to: .bottom, of: separator)
            tableView.pin(.trailing, to: .trailing, of: view)
            tableView.pin(.bottom, to: .bottom, of: view)
        } else {
            let explanationLabel = UILabel()
            explanationLabel.textColor = Colors.text
            explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
            explanationLabel.numberOfLines = 0
            explanationLabel.lineBreakMode = .byWordWrapping
            explanationLabel.textAlignment = .center
            explanationLabel.text = NSLocalizedString("You don't have any contacts yet", comment: "")
            let createNewPrivateChatButton = Button(style: .prominentOutline, size: .large)
            createNewPrivateChatButton.setTitle(NSLocalizedString("Start a Session", comment: ""), for: UIControl.State.normal)
            createNewPrivateChatButton.addTarget(self, action: #selector(createNewPrivateChat), for: UIControl.Event.touchUpInside)
            createNewPrivateChatButton.set(.width, to: 180)
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
        func showError(title: String, message: String = "") {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            presentAlert(alert)
        }
        guard let name = nameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), name.count > 0 else {
            return showError(title: NSLocalizedString("Please enter a group name", comment: ""))
        }
        guard name.count < 64 else {
            return showError(title: NSLocalizedString("Please enter a shorter group name", comment: ""))
        }
        guard selectedContacts.count >= 2 else {
            return showError(title: NSLocalizedString("Please pick at least 2 group members", comment: ""))
        }
        guard selectedContacts.count <= 10 else {
            return showError(title: NSLocalizedString("A closed group cannot have more than 10 members", comment: ""))
        }
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        let storage = OWSPrimaryStorage.shared()
        var masterHexEncodedPublicKey = ""
        storage.dbReadConnection.readWrite { transaction in
            masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: userHexEncodedPublicKey, in: transaction) ?? userHexEncodedPublicKey
        }
        let members = selectedContacts + [ masterHexEncodedPublicKey ]
        let admins = [ masterHexEncodedPublicKey ]
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
