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
        result.set(.width, to: 64)
        result.set(.height, to: 64)
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
        heightConstraint = set(.height, to: 64)
        widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        let _ = OpenGroupAPIV2.getDefaultRoomsPromise?.done { [weak self] rooms in
            self?.rooms = rooms
        }
    }
    
    // MARK: Updating
    private func update() {
        spinner.stopAnimating()
        spinner.isHidden = true
        let height = OpenGroupSuggestionGrid.cellHeight * ceil(CGFloat(rooms.count) / 2)
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
        cell.showRightSeparator = (indexPath.row % 2 != 0) || (indexPath.row % 2 == 0 && indexPath.row == rooms.count - 1)
        cell.showBottomSeparator = (indexPath.row >= rooms.count - 2)
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
        var showRightSeparator = false
        var showBottomSeparator = false
        var room: OpenGroupAPIV2.Info? { didSet { update() } }
        private var rightSeparator: UIView!
        private var bottomSeparator: UIView!
        
        static let identifier = "OpenGroupSuggestionGridCell"
        
        private lazy var label: UILabel = {
            let result = UILabel()
            result.textColor = Colors.text
            result.font = .systemFont(ofSize: Values.smallFontSize)
            result.lineBreakMode = .byTruncatingTail
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
            addSubview(label)
            label.center(in: self)
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Values.smallSpacing).isActive = true
            trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: Values.smallSpacing).isActive = true
            setUpSeparators()
        }
        
        private func setUpSeparators() {
            func getVSeparator() -> UIView {
                let separator = UIView()
                separator.backgroundColor = Colors.separator
                separator.set(.height, to: 1 / UIScreen.main.scale)
                return separator
            }
            func getHSeparator() -> UIView {
                let separator = UIView()
                separator.backgroundColor = Colors.separator
                separator.set(.width, to: 1 / UIScreen.main.scale)
                return separator
            }
            let leftSeparator = getHSeparator()
            addSubview(leftSeparator)
            leftSeparator.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: self)
            let topSeparator = getVSeparator()
            addSubview(topSeparator)
            topSeparator.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.top, UIView.HorizontalEdge.right ], to: self)
            rightSeparator = getHSeparator()
            addSubview(rightSeparator)
            rightSeparator.pin([ UIView.VerticalEdge.top, UIView.HorizontalEdge.right, UIView.VerticalEdge.bottom ], to: self)
            bottomSeparator = getVSeparator()
            addSubview(bottomSeparator)
            bottomSeparator.pin([ UIView.HorizontalEdge.left, UIView.VerticalEdge.bottom, UIView.HorizontalEdge.right ], to: self)
        }
        
        private func update() {
            guard let room = room else { return }
            label.text = room.name
            rightSeparator.alpha = showRightSeparator ? 1 :0
            bottomSeparator.alpha = showBottomSeparator ? 1 :0
        }
    }
}

// MARK: Delegate
protocol OpenGroupSuggestionGridDelegate {
    
    func join(_ room: OpenGroupAPIV2.Info)
}
