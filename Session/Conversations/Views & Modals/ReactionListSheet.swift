
final class ReactionListSheet : BaseVC {
    private let thread: TSGroupThread
    private let viewItem: ConversationViewItem
    private var reactions: [ReactMessage] = []
    private var reactionMap: OrderedDictionary<String, [ReactMessage]> = OrderedDictionary()
    var selectedReaction: String?
    var delegate: ReactionDelegate?
    
    // MARK: Components
    
    private lazy var contentView: UIView = {
        let result = UIView()
        let line = UIView()
        line.set(.height, to: 0.5)
        line.backgroundColor = Colors.border.withAlphaComponent(0.5)
        result.addSubview(line)
        line.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.top ], to: result)
        result.backgroundColor = Colors.modalBackground
        return result
    }()
    
    private lazy var layout: UICollectionViewFlowLayout = {
        let result = UICollectionViewFlowLayout()
        result.scrollDirection = .horizontal
        result.minimumLineSpacing = Values.smallSpacing
        result.minimumInteritemSpacing = Values.smallSpacing
        result.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        return result
    }()
    
    private lazy var reactionContainer: UICollectionView = {
        let result = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        result.register(Cell.self, forCellWithReuseIdentifier: Cell.identifier)
        result.set(.height, to: 48)
        result.backgroundColor = .clear
        result.isScrollEnabled = true
        result.showsHorizontalScrollIndicator = false
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    private lazy var detailInfoLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.grey.withAlphaComponent(0.8)
        result.set(.height, to: 32)
        return result
    }()
    
    private lazy var clearAllButton: Button = {
        let result = Button(style: .destructiveOutline, size: .small)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setTitle(NSLocalizedString("MESSAGE_REQUESTS_CLEAR_ALL", comment: ""), for: .normal)
        result.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        result.layer.borderWidth = 0
        result.isHidden = true
        return result
    }()
    
    private lazy var userListView: UITableView = {
        let result = UITableView()
        result.dataSource = self
        result.delegate = self
        result.register(UserCell.self, forCellReuseIdentifier: "UserCell")
        result.separatorStyle = .none
        result.backgroundColor = .clear
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
    // MARK: Lifecycle
    
    init(for viewItem: ConversationViewItem, thread: TSGroupThread) {
        self.viewItem = viewItem
        self.thread = thread
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(nibName: String?, bundle: Bundle?) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:) instead.")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipeGestureRecognizer.direction = .down
        view.addGestureRecognizer(swipeGestureRecognizer)
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: .emojiReactsUpdated, object: nil)
        setUpViewHierarchy()
        update()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let index = reactionMap.orderedKeys.firstIndex(of: selectedReaction!) {
            let indexPath = IndexPath(item: index, section: 0)
            reactionContainer.selectItem(at: indexPath, animated: true, scrollPosition: .centeredHorizontally)
        }
    }

    private func setUpViewHierarchy() {
        view.addSubview(contentView)
        contentView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing, UIView.VerticalEdge.bottom ], to: view)
        contentView.set(.height, to: 440)
        populateContentView()
    }
    
    private func populateContentView() {
        // Reactions container
        contentView.addSubview(reactionContainer)
        reactionContainer.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: contentView)
        reactionContainer.pin(.top, to: .top, of: contentView, withInset: Values.verySmallSpacing)
        // Seperator
        let seperator = UIView()
        seperator.backgroundColor = Colors.border.withAlphaComponent(0.1)
        seperator.set(.height, to: 0.5)
        contentView.addSubview(seperator)
        seperator.pin(.leading, to: .leading, of: contentView, withInset: Values.smallSpacing)
        seperator.pin(.trailing, to: .trailing, of: contentView, withInset: -Values.smallSpacing)
        seperator.pin(.top, to: .bottom, of: reactionContainer, withInset: Values.verySmallSpacing)
        // Detail info & clear all
        let stackView = UIStackView(arrangedSubviews: [ detailInfoLabel, clearAllButton ])
        contentView.addSubview(stackView)
        stackView.pin(.top, to: .bottom, of: seperator, withInset: Values.smallSpacing)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
        stackView.pin(.trailing, to: .trailing, of: contentView, withInset: -Values.mediumSpacing)
        // Line
        let line = UIView()
        line.set(.height, to: 0.5)
        line.backgroundColor = Colors.border.withAlphaComponent(0.5)
        contentView.addSubview(line)
        line.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: contentView)
        line.pin(.top, to: .bottom, of: stackView, withInset: Values.smallSpacing)
        // Reactor list
        contentView.addSubview(userListView)
        userListView.pin([ UIView.HorizontalEdge.trailing, UIView.HorizontalEdge.leading, UIView.VerticalEdge.bottom ], to: contentView)
        userListView.pin(.top, to: .bottom, of: line, withInset: 0)
    }
    
    private func populateData() {
        self.reactions = []
        self.reactionMap = OrderedDictionary()
        if let messageId = viewItem.interaction.uniqueId, let message = TSMessage.fetch(uniqueId: messageId) {
            self.reactions = message.reactions as! [ReactMessage]
        }
        for reaction in reactions {
            if let emoji = reaction.emoji {
                if !reactionMap.hasValue(forKey: emoji) { reactionMap.append(key: emoji, value: []) }
                var value = reactionMap.value(forKey: emoji)!
                if reaction.sender == getUserHexEncodedPublicKey() {
                    value.insert(reaction, at: 0)
                } else {
                    value.append(reaction)
                }
                reactionMap.replace(key: emoji, value: value)
            }
        }
        if (selectedReaction == nil || reactionMap.value(forKey: selectedReaction!) == nil) && reactionMap.orderedKeys.count > 0 {
            selectedReaction = reactionMap.orderedKeys[0]
        }
    }
    
    private func reloadData() {
        reactionContainer.reloadData()
        let seletedData = reactionMap.value(forKey: selectedReaction!)!
        detailInfoLabel.text = "\(selectedReaction!) · \(seletedData.count)"
        if thread.isOpenGroup, let threadId = thread.uniqueId, let openGroupV2 = Storage.shared.getV2OpenGroup(for: threadId) {
            let isUserModerator = OpenGroupAPIV2.isUserModerator(getUserHexEncodedPublicKey(), for: openGroupV2.room, on: openGroupV2.server)
            clearAllButton.isHidden = !isUserModerator
        }
        userListView.reloadData()
    }
    
    @objc private func update() {
        populateData()
        if reactions.isEmpty {
            close()
            return
        }
        reloadData()
    }
    
    // MARK: Interaction
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: view)
        if contentView.frame.contains(location) {
            super.touchesBegan(touches, with: event)
        } else {
            close()
        }
    }

    @objc func close() {
        dismiss(animated: true, completion: nil)
    }
    
    @objc private func clearAllTapped() {
        guard let reactMessages = reactionMap.value(forKey: selectedReaction!) else { return }
        delegate?.cancelAllReact(reactMessages: reactMessages)
    }
}

// MARK: UICollectionView

extension ReactionListSheet: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    // MARK: Layout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, leading: Values.smallSpacing, bottom: 0, trailing: Values.smallSpacing)
    }
    
    // MARK: Data Source
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return reactionMap.orderedKeys.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.identifier, for: indexPath) as! Cell
        let item = reactionMap.orderedItems[indexPath.item]
        cell.data = (item.0, item.1.count)
        cell.isCurrentSelection = item.0 == selectedReaction!
        return cell
    }
    
    // MARK: Interaction
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedReaction = reactionMap.orderedKeys[indexPath.item]
        reloadData()
    }
}

// MARK: UITableView

extension ReactionListSheet: UITableViewDelegate, UITableViewDataSource {
    // MARK: Table View Data Source
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return reactionMap.value(forKey: selectedReaction!)?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserCell") as! UserCell
        let publicKey = reactionMap.value(forKey: selectedReaction!)![indexPath.row].sender!
        cell.publicKey = publicKey
        cell.normalFont = true
        if publicKey == getUserHexEncodedPublicKey() {
            cell.accessory = .x
        } else {
            cell.accessory = .none
        }
        cell.update()
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let reactMessage = reactionMap.value(forKey: selectedReaction!)?[indexPath.row], let publicKey = reactMessage.sender else { return }
        if publicKey == getUserHexEncodedPublicKey() {
            delegate?.cancelReact(viewItem, for: selectedReaction!)
        }
    }
}

// MARK: Cell

extension ReactionListSheet {
    
    fileprivate final class Cell : UICollectionViewCell {
        var data: (String, Int)? { didSet { update() } }
        var isCurrentSelection: Bool? { didSet { updateBorder() } }
        
        static let identifier = "ReactionListSheetCell"
        
        private lazy var snContentView: UIView = {
            let result = UIView()
            result.backgroundColor = Colors.receivedMessageBackground
            result.set(.height, to: Cell.contentViewHeight)
            result.layer.cornerRadius = Cell.contentViewCornerRadius
            return result
        }()
        
        private lazy var emojiLabel: UILabel = {
            let result = UILabel()
            result.font = .systemFont(ofSize: Values.mediumFontSize)
            return result
        }()
        
        private lazy var numberLabel: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.mediumFontSize)
            return result
        }()
        
        private static var contentViewHeight: CGFloat = 32
        private static var contentViewCornerRadius: CGFloat { contentViewHeight / 2 }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setUpViewHierarchy()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }
        
        private func setUpViewHierarchy() {
            addSubview(snContentView)
            let stackView = UIStackView(arrangedSubviews: [ emojiLabel, numberLabel ])
            stackView.axis = .horizontal
            stackView.alignment = .center
            let spacing = Values.smallSpacing + 2
            stackView.spacing = spacing
            stackView.layoutMargins = UIEdgeInsets(top: 0, left: spacing, bottom: 0, right: spacing)
            stackView.isLayoutMarginsRelativeArrangement = true
            snContentView.addSubview(stackView)
            stackView.pin(to: snContentView)
            snContentView.pin(to: self)
        }
        
        private func update() {
            guard let data = data else { return }
            emojiLabel.text = data.0
            numberLabel.text = data.1 < 1000 ? "\(data.1)" : String(format: "%.1f", Float(data.1) / 1000) + "k"
        }
        
        private func updateBorder() {
            if isCurrentSelection == true {
                snContentView.addBorder(with: Colors.accent)
            } else {
                snContentView.addBorder(with: .clear)
            }
        }
    }
}

// MARK: Delegate

protocol ReactionDelegate : AnyObject {
    
    func quickReact(_ viewItem: ConversationViewItem, with emoji: String)
    func cancelReact(_ viewItem: ConversationViewItem, for emoji: String)
    func cancelAllReact(reactMessages: [ReactMessage])
    
}

