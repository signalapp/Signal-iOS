import PromiseKit
import NVActivityIndicatorView
import SessionMessagingKit
import SessionUIKit

final class OpenGroupSuggestionGrid: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let maxWidth: CGFloat
    private var rooms: [OpenGroupAPI.Room] = [] { didSet { update() } }
    private var heightConstraint: NSLayoutConstraint!
    var delegate: OpenGroupSuggestionGridDelegate?
    
    // MARK: - UI
    
    private static let cellHeight: CGFloat = 40
    private static let separatorWidth = 1 / UIScreen.main.scale
    
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

    private lazy var errorView: UIView = {
        let result: UIView = UIView()
        result.isHidden = true
        
        return result
    }()
    
    private lazy var errorImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: #imageLiteral(resourceName: "warning").withRenderingMode(.alwaysTemplate))
        result.tintColor = Colors.destructive
        
        return result
    }()
    
    private lazy var errorTitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .medium)
        result.text = "DEFAULT_OPEN_GROUP_LOAD_ERROR_TITLE".localized()
        result.textColor = Colors.text
        result.textAlignment = .center
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var errorSubtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = UIFont.systemFont(ofSize: Values.smallFontSize, weight: .medium)
        result.text = "DEFAULT_OPEN_GROUP_LOAD_ERROR_SUBTITLE".localized()
        result.textColor = Colors.text
        result.textAlignment = .center
        result.numberOfLines = 0
        
        return result
    }()
    
    // MARK: - Initialization
    
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
        spinner.pin(.top, to: .top, of: self)
        spinner.center(.horizontal, in: self)
        spinner.startAnimating()
        
        addSubview(errorView)
        errorView.pin(.top, to: .top, of: self, withInset: 10)
        errorView.pin( [HorizontalEdge.leading, HorizontalEdge.trailing], to: self)
        
        errorView.addSubview(errorImageView)
        errorImageView.pin(.top, to: .top, of: errorView)
        errorImageView.center(.horizontal, in: errorView)
        errorImageView.set(.width, to: 60)
        errorImageView.set(.height, to: 60)
        
        errorView.addSubview(errorTitleLabel)
        errorTitleLabel.pin(.top, to: .bottom, of: errorImageView, withInset: 10)
        errorTitleLabel.center(.horizontal, in: errorView)
        
        errorView.addSubview(errorSubtitleLabel)
        errorSubtitleLabel.pin(.top, to: .bottom, of: errorTitleLabel, withInset: 20)
        errorSubtitleLabel.center(.horizontal, in: errorView)
        
        heightConstraint = set(.height, to: OpenGroupSuggestionGrid.cellHeight)
        widthAnchor.constraint(greaterThanOrEqualToConstant: OpenGroupSuggestionGrid.cellHeight).isActive = true
        
        OpenGroupManager.getDefaultRoomsIfNeeded()
            .done { [weak self] rooms in
                self?.rooms = rooms
            }
            .catch { [weak self] _ in
                self?.update()
            }
    }
    
    // MARK: - Updating
    
    private func update() {
        spinner.stopAnimating()
        spinner.isHidden = true
        let roomCount = min(rooms.count, 8) // Cap to a maximum of 8 (4 rows of 2)
        let height = OpenGroupSuggestionGrid.cellHeight * ceil(CGFloat(roomCount) / 2)
        heightConstraint.constant = height
        collectionView.reloadData()
        errorView.isHidden = (roomCount > 0)
    }
    
    // MARK: - Layout
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cellWidth = UIDevice.current.isIPad ? maxWidth / 4 : maxWidth / 2
        return CGSize(width: cellWidth, height: OpenGroupSuggestionGrid.cellHeight)
    }
    
    // MARK: - Data Source
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return (min(rooms.count, 8) + 1) / 2 // Cap to a maximum of 4 (4 rows of 2)
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if (section + 1) * 2 <= min(rooms.count, 8) {
            return 2
        } else {
            return 1
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Cell.identifier, for: indexPath) as! Cell
        cell.room = rooms[indexPath.item + indexPath.section * 2]
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if (section + 1) * 2 <= min(rooms.count, 8) {
            return .zero
        } else {
            let cellWidth = UIDevice.current.isIPad ? maxWidth / 4 : maxWidth / 2
            let sideInset = (maxWidth - cellWidth) / 2
            return UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        }
    }
    
    // MARK: - Interaction
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let room = rooms[indexPath.item]
        delegate?.join(room)
    }
}

// MARK: - Cell

extension OpenGroupSuggestionGrid {
    
    fileprivate final class Cell : UICollectionViewCell {
        var room: OpenGroupAPI.Room? { didSet { update() } }
        
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
            guard let room: OpenGroupAPI.Room = room else { return }
            
            label.text = room.name
            
            // Only continue if we have a room image
            guard let imageId: String = room.imageId else {
                imageView.isHidden = true
                return
            }
            
            let promise = Storage.shared.read { db in
                OpenGroupManager.roomImage(db, fileId: imageId, for: room.token, on: OpenGroupAPI.defaultServer)
            }
            
            if let imageData: Data = promise.value {
                imageView.image = UIImage(data: imageData)
                imageView.isHidden = (imageView.image == nil)
            }
            else {
                imageView.isHidden = true
                
                _ = promise.done { [weak self] imageData in
                    DispatchQueue.main.async {
                        self?.imageView.image = UIImage(data: imageData)
                        self?.imageView.isHidden = (self?.imageView.image == nil)
                    }
                }
            }
        }
    }
}

// MARK: - Delegate

protocol OpenGroupSuggestionGridDelegate {
    func join(_ room: OpenGroupAPI.Room)
}
