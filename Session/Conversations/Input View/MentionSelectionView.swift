
final class MentionSelectionView : UIView, UITableViewDataSource, UITableViewDelegate {
    var candidates: [Mention] = [] {
        didSet {
            tableView.isScrollEnabled = (candidates.count > 4)
            tableView.reloadData()
        }
    }
    var openGroupServer: String?
    var openGroupChannel: UInt64?
    var openGroupRoom: String?
    weak var delegate: MentionSelectionViewDelegate?

    // MARK: Components
    lazy var tableView: UITableView = { // TODO: Make this private
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
        // Table view
        addSubview(tableView)
        tableView.pin(to: self)
        // Top separator
        let topSeparator = UIView()
        topSeparator.backgroundColor = Colors.separator
        topSeparator.set(.height, to: Values.separatorThickness)
        addSubview(topSeparator)
        topSeparator.pin(.leading, to: .leading, of: self)
        topSeparator.pin(.top, to: .top, of: self)
        topSeparator.pin(.trailing, to: .trailing, of: self)
        // Bottom separator
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
        return candidates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! Cell
        let mentionCandidate = candidates[indexPath.row]
        cell.mentionCandidate = mentionCandidate
        cell.openGroupServer = openGroupServer
        cell.openGroupChannel = openGroupChannel
        cell.openGroupRoom = openGroupRoom
        cell.separator.isHidden = (indexPath.row == (candidates.count - 1))
        return cell
    }

    // MARK: Interaction
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let mentionCandidate = candidates[indexPath.row]
        delegate?.handleMentionSelected(mentionCandidate, from: self)
    }
}

// MARK: - Cell

private extension MentionSelectionView {

    final class Cell : UITableViewCell {
        var mentionCandidate = Mention(publicKey: "", displayName: "") { didSet { update() } }
        var openGroupServer: String?
        var openGroupChannel: UInt64?
        var openGroupRoom: String?

        // MARK: Components
        private lazy var profilePictureView = ProfilePictureView()

        private lazy var moderatorIconImageView = UIImageView(image: #imageLiteral(resourceName: "Crown"))

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
            // Cell background color
            backgroundColor = .clear
            // Highlight color
            let selectedBackgroundView = UIView()
            selectedBackgroundView.backgroundColor = .clear
            self.selectedBackgroundView = selectedBackgroundView
            // Profile picture image view
            let profilePictureViewSize = Values.smallProfilePictureSize
            profilePictureView.set(.width, to: profilePictureViewSize)
            profilePictureView.set(.height, to: profilePictureViewSize)
            profilePictureView.size = profilePictureViewSize
            // Main stack view
            let mainStackView = UIStackView(arrangedSubviews: [ profilePictureView, displayNameLabel ])
            mainStackView.axis = .horizontal
            mainStackView.alignment = .center
            mainStackView.spacing = Values.mediumSpacing
            mainStackView.set(.height, to: profilePictureViewSize)
            contentView.addSubview(mainStackView)
            mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
            mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.smallSpacing)
            contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.mediumSpacing)
            contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.smallSpacing)
            mainStackView.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            // Moderator icon image view
            moderatorIconImageView.set(.width, to: 20)
            moderatorIconImageView.set(.height, to: 20)
            contentView.addSubview(moderatorIconImageView)
            moderatorIconImageView.pin(.trailing, to: .trailing, of: profilePictureView, withInset: 1)
            moderatorIconImageView.pin(.bottom, to: .bottom, of: profilePictureView, withInset: 4.5)
            // Separator
            addSubview(separator)
            separator.pin(.leading, to: .leading, of: self)
            separator.pin(.trailing, to: .trailing, of: self)
            separator.pin(.bottom, to: .bottom, of: self)
        }

        // MARK: Updating
        private func update() {
            displayNameLabel.text = mentionCandidate.displayName
            profilePictureView.publicKey = mentionCandidate.publicKey
            profilePictureView.update()
            if let server = openGroupServer, let room = openGroupRoom {
                let isUserModerator = OpenGroupAPIV2.isUserModerator(mentionCandidate.publicKey, for: room, on: server)
                moderatorIconImageView.isHidden = !isUserModerator
            } else {
                moderatorIconImageView.isHidden = true
            }
        }
    }
}

// MARK: - Delegate

protocol MentionSelectionViewDelegate : class {

    func handleMentionSelected(_ mention: Mention, from view: MentionSelectionView)
}
