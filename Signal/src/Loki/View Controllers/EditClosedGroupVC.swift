
@objc(LKEditClosedGroupVC)
final class EditClosedGroupVC : BaseVC, UITableViewDataSource, UITableViewDelegate {
    private let thread: TSGroupThread
    private var isEditingGroupName = false { didSet { handleIsEditingGroupNameChanged() } }

    private lazy var members: [String] = {
        func getDisplayName(for hexEncodedPublicKey: String) -> String {
            return UserDisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? hexEncodedPublicKey
        }
        return GroupUtilities.getClosedGroupMembers(thread).sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
    }()

    // MARK: Components
    private lazy var groupNameLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.lineBreakMode = .byTruncatingTail
        result.textAlignment = .center
        return result
    }()

    private lazy var groupNameTextField: TextField = {
        let result = TextField(placeholder: "Enter a group name", usesDefaultHeight: false)
        result.textAlignment = .center
        return result
    }()

    @objc private lazy var tableView: UITableView = {
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
    @objc(initWithThreadID:)
    init(with threadID: String) {
        var thread: TSGroupThread!
        Storage.read { transaction in
            thread = TSGroupThread.fetch(uniqueId: threadID, transaction: transaction)!
        }
        self.thread = thread
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(with:) instead.")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle("Edit Group")
        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        backButton.tintColor = Colors.text
        navigationItem.backBarButtonItem = backButton
        setUpViewHierarchy()
        updateNavigationBarButtons()
    }

    private func setUpViewHierarchy() {
        // Group name container
        groupNameLabel.text = thread.groupModel.groupName
        let groupNameContainer = UIView()
        groupNameContainer.addSubview(groupNameLabel)
        groupNameLabel.pin(to: groupNameContainer)
        groupNameContainer.addSubview(groupNameTextField)
        groupNameTextField.pin(to: groupNameContainer)
        groupNameContainer.set(.height, to: 40)
        groupNameTextField.alpha = 0
        // Top container
        let topContainer = UIView()
        topContainer.addSubview(groupNameContainer)
        groupNameContainer.center(in: topContainer)
        topContainer.set(.height, to: 40)
        let topContainerTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(showEditGroupNameUI))
        topContainer.addGestureRecognizer(topContainerTapGestureRecognizer)
        // Members label
        let membersLabel = UILabel()
        membersLabel.textColor = Colors.text
        membersLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        membersLabel.text = "Members"
        // Add members button
        let addMembersButton = Button(style: .prominentOutline, size: .large)
        addMembersButton.setTitle("Add Members", for: UIControl.State.normal)
        addMembersButton.addTarget(self, action: #selector(addMembers), for: UIControl.Event.touchUpInside)
        addMembersButton.contentEdgeInsets = UIEdgeInsets(top: 0, leading: Values.mediumSpacing, bottom: 0, trailing: Values.mediumSpacing)
        // Middle stack view
        let middleStackView = UIStackView(arrangedSubviews: [ membersLabel, addMembersButton ])
        middleStackView.axis = .horizontal
        middleStackView.alignment = .center
        middleStackView.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, leading: Values.mediumSpacing, bottom: Values.smallSpacing, trailing: Values.mediumSpacing)
        middleStackView.isLayoutMarginsRelativeArrangement = true
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [
            UIView.vSpacer(Values.veryLargeSpacing),
            topContainer,
            UIView.vSpacer(Values.veryLargeSpacing),
            UIView.separator(),
            middleStackView,
            UIView.separator(),
            tableView
        ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        mainStackView.set(.width, to: UIScreen.main.bounds.width)
        // Scroll view
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(mainStackView)
        mainStackView.pin(to: scrollView)
        view.addSubview(scrollView)
        scrollView.pin(to: view)
        mainStackView.pin(.bottom, to: .bottom, of: view)
    }

    // MARK: Table View Data Source / Delegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return members.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let publicKey = members[indexPath.row]
        cell.publicKey = publicKey
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let publicKey = members[indexPath.row]
        return publicKey != getUserHexEncodedPublicKey()
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let removeAction = UITableViewRowAction(style: .destructive, title: "Remove") { [weak self] _, _ in
            // TODO: Implement
        }
        removeAction.backgroundColor = Colors.destructive
        return [ removeAction ]
    }

    // MARK: Updating
    private func updateNavigationBarButtons() {
        if isEditingGroupName {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(handleCancelGroupNameEditingButtonTapped))
            cancelButton.tintColor = Colors.text
            navigationItem.leftBarButtonItem = cancelButton
        } else {
            navigationItem.leftBarButtonItem = nil
        }
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(handleSaveGroupNameButtonTapped))
        doneButton.tintColor = Colors.text
        navigationItem.rightBarButtonItem = doneButton
    }

    private func handleIsEditingGroupNameChanged() {
        updateNavigationBarButtons()
        UIView.animate(withDuration: 0.25) {
            self.groupNameLabel.alpha = self.isEditingGroupName ? 0 : 1
            self.groupNameTextField.alpha = self.isEditingGroupName ? 1 : 0
        }
        if isEditingGroupName {
            groupNameTextField.becomeFirstResponder()
        } else {
            groupNameTextField.resignFirstResponder()
        }
    }

    // MARK: Interaction
    @objc private func showEditGroupNameUI() {
        isEditingGroupName = true
    }

    @objc private func handleCancelGroupNameEditingButtonTapped() {
        isEditingGroupName = false
    }

    @objc private func handleSaveGroupNameButtonTapped() {
        isEditingGroupName = false
    }

    @objc private func addMembers() {

    }


}



// MARK: - Cell

private extension EditClosedGroupVC {

    final class Cell : UITableViewCell {
        var publicKey = "" { didSet { update() } }

        // MARK: Components
        private lazy var profilePictureView = ProfilePictureView()

        private lazy var displayNameLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
            result.lineBreakMode = .byTruncatingTail
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
            let stackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel ])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = Values.mediumSpacing
            contentView.addSubview(stackView)
            stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
            stackView.pin(.top, to: .top, of: contentView, withInset: Values.mediumSpacing)
            contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.mediumSpacing)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.mediumSpacing)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            // Set up the separator
            contentView.addSubview(separator)
            separator.pin(.leading, to: .leading, of: contentView)
            contentView.pin(.trailing, to: .trailing, of: separator)
            separator.pin(.bottom, to: .bottom, of: contentView)
            separator.set(.width, to: UIScreen.main.bounds.width)
        }

        // MARK: Updating
        private func update() {
            profilePictureView.hexEncodedPublicKey = publicKey
            profilePictureView.update()
            displayNameLabel.text = UserDisplayNameUtilities.getPrivateChatDisplayName(for: publicKey) ?? publicKey
        }
    }
}
