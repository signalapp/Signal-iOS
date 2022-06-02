
final class ReactionListSheet : BaseVC, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let reactions: [ReactMessage]
    private var reactionMap: OrderedDictionary<String, [ReactMessage]> = OrderedDictionary()
    var selectedReaction: String?
    
    // MARK: Components
    
    private lazy var contentView: UIView = {
        let result = UIView()
        result.layer.borderWidth = 0.5
        result.layer.borderColor = Colors.border.withAlphaComponent(0.5).cgColor
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
        return result
    }()
    
    // MARK: Lifecycle
    
    init(for reactions: [ReactMessage]) {
        self.reactions = reactions
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
        populateData()
        setUpViewHierarchy()
        reactionContainer.reloadData()
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
        // Line
        let lineView = UIView()
        lineView.backgroundColor = Colors.border.withAlphaComponent(0.1)
        lineView.set(.height, to: 0.5)
        contentView.addSubview(lineView)
        lineView.pin(.leading, to: .leading, of: contentView, withInset: Values.smallSpacing)
        lineView.pin(.trailing, to: .trailing, of: contentView, withInset: -Values.smallSpacing)
        lineView.pin(.top, to: .bottom, of: reactionContainer, withInset: Values.verySmallSpacing)
        // Detail info label
        contentView.addSubview(detailInfoLabel)
        detailInfoLabel.pin(.top, to: .bottom, of: lineView, withInset: Values.smallSpacing)
        detailInfoLabel.pin(.leading, to: .leading, of: contentView, withInset: Values.mediumSpacing)
        
    }
    
    private func populateData() {
        for reaction in reactions {
            if let emoji = reaction.emoji {
                if !reactionMap.hasValue(forKey: emoji) { reactionMap.append(key: emoji, value: []) }
                var value = reactionMap.value(forKey: emoji)!
                value.append(reaction)
                reactionMap.replace(key: emoji, value: value)
            }
        }
        if selectedReaction == nil {
            selectedReaction = reactionMap.orderedKeys[0]
        }
    }
    
    private func update() {
        let seletedData = reactionMap.value(forKey: selectedReaction!)!
        detailInfoLabel.text = "\(selectedReaction!) · \(seletedData.count)"
    }
    
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
        cell.isSelected = item.0 == selectedReaction!
        return cell
    }
    
    // MARK: Interaction
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedReaction = reactionMap.orderedKeys[indexPath.item]
        update()
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
}


// MARK: Cell

extension ReactionListSheet {
    
    fileprivate final class Cell : UICollectionViewCell {
        var data: (String, Int)? { didSet { update() } }
        override var isSelected: Bool { didSet { updateBorder() } }
        
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
            if isSelected {
                snContentView.addBorder(with: Colors.accent)
            } else {
                snContentView.addBorder(with: .clear)
            }
        }
    }
}
