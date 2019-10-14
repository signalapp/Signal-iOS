
// MARK: - User Selection View

@objc(LKMentionCandidateSelectionView)
final class MentionCandidateSelectionView : UIView, UITableViewDataSource, UITableViewDelegate {
    @objc var mentionCandidates: [Mention] = [] { didSet { tableView.reloadData() } }
    @objc var hasGroupContext = false
    @objc var delegate: MentionCandidateSelectionViewDelegate?
    
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
        return mentionCandidates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let mentionCandidate = mentionCandidates[indexPath.row]
        cell.mentionCandidate = mentionCandidate
        cell.hasGroupContext = hasGroupContext
        return cell
    }
    
    // MARK: Interaction
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let mentionCandidate = mentionCandidates[indexPath.row]
        delegate?.handleMentionCandidateSelected(mentionCandidate, from: self)
    }
}

// MARK: - Cell

private extension MentionCandidateSelectionView {
    
    final class Cell : UITableViewCell {
        var mentionCandidate = Mention(hexEncodedPublicKey: "", displayName: "") { didSet { update() } }
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
            displayNameLabel.text = mentionCandidate.displayName
            let profilePicture = OWSContactAvatarBuilder(signalId: mentionCandidate.hexEncodedPublicKey, colorName: .blue, diameter: 36).build()
            profilePictureImageView.image = profilePicture
            let isUserModerator = LokiGroupChatAPI.isUserModerator(mentionCandidate.hexEncodedPublicKey, for: 1, on: "https://chat.lokinet.org") // FIXME: Mentions need to work for every kind of chat
            moderatorIconImageView.isHidden = !isUserModerator || !hasGroupContext
        }
    }
}
