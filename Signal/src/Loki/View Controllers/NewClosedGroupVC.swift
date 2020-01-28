
final class NewClosedGroupVC : UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var selectedContacts: Set<String> = []
    
    private lazy var contacts: [String] = {
        var result: [String] = []
        TSContactThread.enumerateCollectionObjects { object, _ in
            guard let thread = object as? TSContactThread, thread.isContactFriend else { return }
            let hexEncodedPublicKey = thread.contactIdentifier()
            result.append(hexEncodedPublicKey)
        }
        func getDisplayName(for hexEncodedPublicKey: String) -> String {
            return DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
        }
        result = result.sorted {
            getDisplayName(for: $0) < getDisplayName(for: $1)
        }
        return result
    }()
    
    // MARK: Components
    @objc private lazy var tableView: UITableView = {
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
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set navigation bar background color
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up navigation bar buttons
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(createClosedGroup))
        doneButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = doneButton
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("New Closed Group", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up table view
        view.addSubview(tableView)
        tableView.pin(to: view)
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
        let userHexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        let members = [String](selectedContacts) + [ userHexEncodedPublicKey ]
        let admins = [ userHexEncodedPublicKey ]
        let groupID = LKGroupUtilities.getEncodedClosedGroupIDAsData(Randomness.generateRandomBytes(kGroupIdLength)!.toHexString())
        let group = TSGroupModel(title: nil, memberIds: members, image: nil, groupId: groupID, groupType: .closedGroup, adminIds: admins)
        let thread = TSGroupThread.getOrCreateThread(with: group)
        OWSProfileManager.shared().addThread(toProfileWhitelist: thread)
        ModalActivityIndicatorViewController.present(fromViewController: navigationController!, canCancel: false) { [weak self] modalActivityIndicator in
            let message = TSOutgoingMessage(in: thread, groupMetaMessage: .new, expiresInSeconds: 0)
            message.update(withCustomMessage: NSLocalizedString("GROUP_CREATED", comment: ""))
            DispatchQueue.main.async {
                SSKEnvironment.shared.messageSender.send(message, success: {
                    DispatchQueue.main.async {
                        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
                        self?.presentingViewController?.dismiss(animated: true, completion: nil)
                    }
                }, failure: { error in
                    let message = TSErrorMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, failedMessageType: .groupCreationFailed)
                    message.save()
                    DispatchQueue.main.async {
                        SignalApp.shared().presentConversation(for: thread, action: .compose, animated: false)
                        self?.presentingViewController?.dismiss(animated: true, completion: nil)
                    }
                })
            }
        }
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
            selectedBackgroundView.backgroundColor = Colors.cellSelected
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
            displayNameLabel.text = DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
            tickImageView.image = hasTick ? #imageLiteral(resourceName: "CircleCheck") : #imageLiteral(resourceName: "Circle")
        }
    }
}
