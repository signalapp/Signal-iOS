
@objc(LKGroupMembersVC)
final class GroupMembersVC : UIViewController, UITableViewDataSource {
    private let thread: TSGroupThread
    
    private lazy var members: [String] = {
        func getDisplayName(for hexEncodedPublicKey: String) -> String {
            return DisplayNameUtilities.getPrivateChatDisplayName(for: hexEncodedPublicKey) ?? "Unknown Contact"
        }
        return GroupUtilities.getClosedGroupMembers(thread).sorted { getDisplayName(for: $0) < getDisplayName(for: $1) }
    }()
    
    // MARK: Components
    @objc private lazy var tableView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
    // MARK: Lifecycle
    @objc init(thread: TSGroupThread) {
        self.thread = thread
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("Using GroupMembersVC.init(nibName:bundle:) isn't allowed. Use GroupMembersVC.init(thread:) instead.") }
    override init(nibName: String?, bundle: Bundle?) { fatalError("Using GroupMembersVC.init(nibName:bundle:) isn't allowed. Use GroupMembersVC.init(thread:) instead.") }
    
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
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Group Members", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up table view
        view.addSubview(tableView)
        tableView.pin(to: view)
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return members.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let contact = members[indexPath.row]
        cell.hexEncodedPublicKey = contact
        return cell
    }
    
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: - Cell

private extension GroupMembersVC {
    
    final class Cell : UITableViewCell {
        var hexEncodedPublicKey = "" { didSet { update() } }
        
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
        }
    }
}
