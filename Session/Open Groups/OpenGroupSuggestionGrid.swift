import PromiseKit
import NVActivityIndicatorView

final class OpenGroupSuggestionGrid : UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let maxWidth: CGFloat
    private var rooms: [OpenGroupAPIV2.Info] = [] { didSet { update() } }
    private var heightConstraint: NSLayoutConstraint!
    var delegate: OpenGroupSuggestionGridDelegate?
    
    // MARK: UI Components
    private lazy var layout: UICollectionViewFlowLayout = {
        let result = UICollectionViewFlowLayout()
        result.minimumLineSpacing = 0
        result.minimumInteritemSpacing = 0
        return result
    }()
    
    private lazy var collectionView: UICollectionView = {
        let result = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        result.register(Cell.self, forCellWithReuseIdentifier: Cell.identifier)
        result.backgroundColor = .clear
        result.isScrollEnabled = false
        result.dataSource = self
        result.delegate = self
        return result
    }()
    
    private lazy var spinner: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        result.set(.width, to: OpenGroupSuggestionGrid.cellHeight)
        result.set(.height, to: OpenGroupSuggestionGrid.cellHeight)
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
        addSubview(spinner)
        spinner.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top ], to: self)
        spinner.startAnimating()
        heightConstraint = set(.height, to: OpenGroupSuggestionGrid.cellHeight)
        widthAnchor.constraint(greaterThanOrEqualToConstant: OpenGroupSuggestionGrid.cellHeight).isActive = true
        if OpenGroupAPIV2.defaultRoomsPromise == nil {
            OpenGroupAPIV2.getDefaultRoomsIfNeeded()
        }
        let _ = OpenGroupAPIV2.defaultRoomsPromise?.done { [weak self] rooms in
            self?.rooms = rooms
        }
    }
    
    // MARK: Updating
    private func update() {
        spinner.stopAnimating()
        spinner.isHidden = true
        let roomCount = min(rooms.count, 8) // Cap to a maximum of 8 (4 rows of 2)
        let height = OpenGroupSuggestionGrid.cellHeight * ceil(CGFloat(roomCount) / 2)
        heightConstraint.constant = height
        collectionView.reloadData()
    }
    
    // MARK: Layout
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: maxWidth / 2, height: OpenGroupSuggestionGrid.cellHeight)
    }
    
    // MARK: Data Source
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return min(rooms.count, 8) // Cap to a maximum of 8 (4 rows of 2)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.identifier, for: indexPath) as! Cell
        cell.room = rooms[indexPath.item]
        return cell
    }
    
    // MARK: Interaction
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let room = rooms[indexPath.item]
        delegate?.join(room)
    }
}

// MARK: Cell
extension OpenGroupSuggestionGrid {
    
    fileprivate final class Cell : UICollectionViewCell {
        var room: OpenGroupAPIV2.Info? { didSet { update() } }
        
        static let identifier = "OpenGroupSuggestionGridCell"
        
        private lazy var snContentView: UIView = {
            let result = UIView()
            result.backgroundColor = Colors.navigationBarBackground
            result.set(.height, to: Cell.contentViewHeight)
            result.layer.cornerRadius = Cell.contentViewCornerRadius
            return result
        }()
        
        private lazy var imageView: UIImageView = {
            let result = UIImageView()
            let size: CGFloat = 24
            result.set(.width, to: size)
            result.set(.height, to: size)
            result.layer.cornerRadius = size / 2
            result.clipsToBounds = true
            return result
        }()
        
        private lazy var label: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.smallFontSize)
            result.lineBreakMode = .byTruncatingTail
            return result
        }()
        
        private static let contentViewInset: CGFloat = 4
        private static var contentViewHeight: CGFloat { OpenGroupSuggestionGrid.cellHeight - 2 * contentViewInset }
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
            let stackView = UIStackView(arrangedSubviews: [ imageView, label ])
            stackView.axis = .horizontal
            stackView.spacing = Values.smallSpacing
            snContentView.addSubview(stackView)
            stackView.center(.vertical, in: snContentView)
            stackView.pin(.leading, to: .leading, of: snContentView, withInset: 4)
            snContentView.trailingAnchor.constraint(greaterThanOrEqualTo: stackView.trailingAnchor, constant: Values.smallSpacing).isActive = true
            snContentView.pin(to: self, withInset: Cell.contentViewInset)
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            let newPath = UIBezierPath(roundedRect: snContentView.bounds, cornerRadius: Cell.contentViewCornerRadius).cgPath
            snContentView.layer.shadowPath = newPath
            snContentView.layer.shadowColor = UIColor.black.cgColor
            snContentView.layer.shadowOffset = CGSize.zero
            snContentView.layer.shadowOpacity = isLightMode ? 0.2 : 0.6
            snContentView.layer.shadowRadius = 2
        }
        
        private func update() {
            guard let room = room else { return }
            let promise = OpenGroupAPIV2.getGroupImage(for: room.id, on: OpenGroupAPIV2.defaultServer)
            imageView.image = given(promise.value) { UIImage(data: $0)! }
            imageView.isHidden = (imageView.image == nil)
            label.text = room.name
        }
    }
}

// MARK: Delegate
protocol OpenGroupSuggestionGridDelegate {
    
    func join(_ room: OpenGroupAPIV2.Info)
}
