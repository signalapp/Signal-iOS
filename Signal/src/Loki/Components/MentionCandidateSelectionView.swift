
// MARK: - User Selection View

@objc(LKMentionCandidateSelectionView)
final class MentionCandidateSelectionView : UIView, UITableViewDataSource, UITableViewDelegate {
    @objc var mentionCandidates: [Mention] = [] { didSet { tableView.reloadData() } }
    @objc var publicChatServer: String?
    var publicChatChannel: UInt64?
    @objc var delegate: MentionCandidateSelectionViewDelegate?
    
    // MARK: Convenience
    @objc(setPublicChatChannel:)
    func setPublicChatChannel(to publicChatChannel: UInt64) {
        self.publicChatChannel = publicChatChannel != 0 ? publicChatChannel : nil
    }
    
    // MARK: Components
    @objc lazy var tableView: UITableView = { // TODO: Make this private
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(Cell.self, forCellReuseIdentifier: "Cell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
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
        let topSeparator = UIView()
        topSeparator.backgroundColor = Colors.separator
        topSeparator.set(.height, to: Values.separatorThickness)
        addSubview(topSeparator)
        topSeparator.pin(.leading, to: .leading, of: self)
        topSeparator.pin(.top, to: .top, of: self)
        topSeparator.pin(.trailing, to: .trailing, of: self)
        let bottomSeparator = UIView()
        bottomSeparator.backgroundColor = Colors.separator
        bottomSeparator.set(.height, to: Values.separatorThickness)
        addSubview(bottomSeparator)
        bottomSeparator.pin(.leading, to: .leading, of: self)
        bottomSeparator.pin(.trailing, to: .trailing, of: self)
        bottomSeparator.pin(.bottom, to: .bottom, of: self)
    }
    
    // MARK: Data
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mentionCandidates.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let mentionCandidate = mentionCandidates[indexPath.row]
        cell.mentionCandidate = mentionCandidate
        cell.publicChatServer = publicChatServer
        cell.publicChatChannel = publicChatChannel
        cell.separator.isHidden = (indexPath.row == (mentionCandidates.count - 1))
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
        var mentionCandidate = Mention(publicKey: "", displayName: "") { didSet { update() } }
        var publicChatServer: String?
        var publicChatChannel: UInt64?
        
        // MARK: Components
        private lazy var profilePictureView = ProfilePictureView()
        
        private lazy var moderatorIconImageView: UIImageView = {
            let result = UIImageView(image: #imageLiteral(resourceName: "Crown"))
            return result
        }()
        
        private lazy var displayNameLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.smallFontSize)
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        lazy var separator: UIView = {
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
            selectedBackgroundView.backgroundColor = Colors.cellBackground // Intentionally not Colors.cellSelected
            self.selectedBackgroundView = selectedBackgroundView
            // Set up the profile picture image view
            let profilePictureViewSize = Values.verySmallProfilePictureSize
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
            stackView.pin(.top, to: .top, of: contentView, withInset: Values.smallSpacing)
            contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.mediumSpacing)
            contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.smallSpacing)
            stackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            // Set up the moderator icon image view
            moderatorIconImageView.set(.width, to: 20)
            moderatorIconImageView.set(.height, to: 20)
            contentView.addSubview(moderatorIconImageView)
            moderatorIconImageView.pin(.trailing, to: .trailing, of: profilePictureView)
            moderatorIconImageView.pin(.bottom, to: .bottom, of: profilePictureView, withInset: 3.5)
            // Set up the separator
            addSubview(separator)
            separator.pin(.leading, to: .leading, of: self)
            separator.pin(.trailing, to: .trailing, of: self)
            separator.pin(.bottom, to: .bottom, of: self)
        }
        
        // MARK: Updating
        private func update() {
            displayNameLabel.text = mentionCandidate.displayName
            profilePictureView.hexEncodedPublicKey = mentionCandidate.publicKey
            profilePictureView.update()
            if let server = publicChatServer, let channel = publicChatChannel {
                let isUserModerator = PublicChatAPI.isUserModerator(mentionCandidate.publicKey, for: channel, on: server)
                moderatorIconImageView.isHidden = !isUserModerator
            } else {
                moderatorIconImageView.isHidden = true
            }
        }
    }
}
