
final class OpenGroupSuggestionGrid : UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let maxWidth: CGFloat
    private var rooms: [OpenGroupAPIV2.Info] = [] { didSet { reload() } }
    private var heightConstraint: NSLayoutConstraint!
    
    // MARK: UI Components
    private lazy var layout: UICollectionViewFlowLayout = {
        let result = UICollectionViewFlowLayout()
        result.minimumLineSpacing = OpenGroupSuggestionGrid.separatorWidth
        result.minimumInteritemSpacing = OpenGroupSuggestionGrid.separatorWidth
        return result
    }()
    
    private lazy var collectionView: UICollectionView = {
        let result = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        result.register(Cell.self, forCellWithReuseIdentifier: Cell.identifier)
        result.backgroundColor = Colors.unimportant
        result.isScrollEnabled = false
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    // MARK: Settings
    private static let cellHeight: CGFloat = 40
    private static let separatorWidth = 1 / UIScreen.main.scale
    
    // MARK: Initialization
    init(maxWidth: CGFloat) {
        self.maxWidth = maxWidth
        super.init(frame: CGRect.zero)
        initialize()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(maxWidth:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(maxWidth:) instead.")
    }
    
    private func initialize() {
        addSubview(collectionView)
        collectionView.pin(to: self)
        heightConstraint = set(.height, to: 0)
        attempt(maxRetryCount: 8, recoveringOn: DispatchQueue.main) {
            return OpenGroupAPIV2.getAllRooms(from: "https://sessionopengroup.com").done { [weak self] rooms in
                self?.rooms = rooms
            }
        }.retainUntilComplete()
    }
    
    // MARK: Updating
    private func reload() {
        let height = OpenGroupSuggestionGrid.cellHeight * ceil(CGFloat(rooms.count) / 3)
        heightConstraint.constant = height
        collectionView.reloadData()
    }
    
    // MARK: Layout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: (maxWidth - (2 * OpenGroupSuggestionGrid.separatorWidth)) / 3, height: OpenGroupSuggestionGrid.cellHeight)
    }
    
    // MARK: Data Source
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return min(rooms.count, 12) // Cap to a maximum of 12 (4 rows of 3)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.identifier, for: indexPath) as! Cell
        cell.room = rooms[indexPath.item]
        return cell
    }
}

// MARK: Cell
extension OpenGroupSuggestionGrid {
    
    fileprivate final class Cell : UICollectionViewCell {
        var room: OpenGroupAPIV2.Info? { didSet { update() } }
        
        static let identifier = "OpenGroupSuggestionGridCell"
        
        private lazy var label: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.smallFontSize)
            return result
        }()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            setUpViewHierarchy()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setUpViewHierarchy()
        }
        
        private func setUpViewHierarchy() {
            backgroundColor = .white
            addSubview(label)
            label.center(in: self)
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Values.smallSpacing).isActive = true
            trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: Values.smallSpacing).isActive = true
        }
        
        private func update() {
            guard let room = room else { return }
            label.text = room.name
        }
    }
}
