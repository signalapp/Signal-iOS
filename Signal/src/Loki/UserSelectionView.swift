
// MARK: - User Selection View

@objc(LKUserSelectionView)
final class UserSelectionView : UIView, UITableViewDataSource, UITableViewDelegate {
    @objc var users: [String] = [] { didSet { tableView.reloadData() } }
    @objc var hasGroupContext = false
    @objc var delegate: UserSelectionViewDelegate?
    
    // MARK: Components
    @objc lazy var tableView: UITableView = { // TODO: Make this private
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.contentInset = UIEdgeInsets(top: 6, leading: 0, bottom: 0, trailing: 0)
        return result
    }()
    
    // MARK: Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViewHierarchy()
    }
    
    private func setUpViewHierarchy() {
        addSubview(tableView)
        tableView.pin(to: self)
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return users.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let user = users[indexPath.row]
        cell.user = user
        cell.hasGroupContext = hasGroupContext
        return cell
    }
    
    // MARK: Interaction
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let user = users[indexPath.row]
        delegate?.handleUserSelected(user, from: self)
    }
}

// MARK: - Cell

private extension UserSelectionView {
    
    final class Cell : UITableViewCell {
        var user = "" { didSet { update() } }
        var hasGroupContext = false
        
        // MARK: Components
        private lazy var profilePictureImageView = AvatarImageView()
        
        private lazy var moderatorIconImageView: UIImageView = {
            let result = UIImageView(image: #imageLiteral(resourceName: "Crown"))
            return result
        }()
        
        private lazy var displayNameLabel: UILabel = {
            let result = UILabel()
            result.textColor = Theme.primaryColor
            result.font = UIFont.ows_dynamicTypeSubheadlineClamped
            result.lineBreakMode = .byTruncatingTail
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
            // Make the cell transparent
            backgroundColor = .clear
            // Set up the profile picture image view
            profilePictureImageView.set(.width, to: 36)
            profilePictureImageView.set(.height, to: 36)
            // Set up the main stack view
            let stackView = UIStackView(arrangedSubviews: [ profilePictureImageView, displayNameLabel ])
            stackView.axis = .horizontal
            stackView.alignment = .center
            stackView.spacing = 16
            stackView.set(.height, to: 36)
            contentView.addSubview(stackView)
            stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
            stackView.pin(.top, to: .top, of: contentView, withInset: 8)
            contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 8)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * 16)
            // Set up the moderator icon image view
            moderatorIconImageView.set(.width, to: 20)
            moderatorIconImageView.set(.height, to: 20)
            contentView.addSubview(moderatorIconImageView)
            moderatorIconImageView.pin(.trailing, to: .trailing, of: profilePictureImageView)
            moderatorIconImageView.pin(.bottom, to: .bottom, of: profilePictureImageView, withInset: 3.5)
        }
        
        // MARK: Updating
        private func update() {
            var displayName: String = ""
            OWSPrimaryStorage.shared().dbReadConnection.read { transaction in
                let collection = "\(LokiGroupChatAPI.publicChatServer).\(LokiGroupChatAPI.publicChatServerID)"
                displayName = transaction.object(forKey: self.user, inCollection: collection) as! String
            }
            displayNameLabel.text = displayName
            let profilePicture = OWSContactAvatarBuilder(signalId: user, colorName: .blue, diameter: 36).build()
            profilePictureImageView.image = profilePicture
            let isUserModerator = LokiGroupChatAPI.isUserModerator(user, for: LokiGroupChatAPI.publicChatServerID, on: LokiGroupChatAPI.publicChatServer)
            moderatorIconImageView.isHidden = !isUserModerator || !hasGroupContext
        }
    }
}
