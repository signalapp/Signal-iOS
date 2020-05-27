
final class PathVC : BaseVC {
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set up navigation bar
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up close button
        let closeButton = UIBarButtonItem(image: #imageLiteral(resourceName: "X"), style: .plain, target: self, action: #selector(close))
        closeButton.tintColor = Colors.text
        navigationItem.leftBarButtonItem = closeButton
        // Customize title
        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Path", comment: "")
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        navigationItem.titleView = titleLabel
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("Session hides your IP by onion routing your messages through Session's decentralized Service Node network. The Service Nodes currently being used for this are shown below.", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        view.addSubview(explanationLabel)
        explanationLabel.pin(.leading, to: .leading, of: view, withInset: Values.largeSpacing)
        explanationLabel.pin(.top, to: .top, of: view, withInset: Values.mediumSpacing)
        explanationLabel.pin(.trailing, to: .trailing, of: view, withInset: -Values.largeSpacing)
        // Set up path stack view
        guard var mainPath = OnionRequestAPI.paths.first else {
            return close() // TODO: Show path establishing UI
        }
        let rows: [UIStackView]
        switch mainPath.count {
        case 1: return // TODO: Do we want to handle this case?
        case 2:
            let topPathRow = getPathRow(forSnode: mainPath[1], at: .top)
            let bottomPathRow = getPathRow(forSnode: mainPath[0], at: .bottom)
            rows = [ topPathRow, bottomPathRow ]
        default:
            let topPathRow = getPathRow(forSnode: mainPath.removeLast(), at: .top)
            let bottomPathRow = getPathRow(forSnode: mainPath.removeFirst(), at: .bottom)
            let middlePathRows = mainPath.map {
                getPathRow(forSnode: $0, at: .middle)
            }
            rows = [ topPathRow ] + middlePathRows + [ bottomPathRow ]
        }
        let pathStackView = UIStackView(arrangedSubviews: rows)
        pathStackView.axis = .vertical
        view.addSubview(pathStackView)
        pathStackView.pin(.top, to: .bottom, of: explanationLabel, withInset: Values.largeSpacing)
        pathStackView.center(.horizontal, in: view)
        pathStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Values.largeSpacing).isActive = true
        view.trailingAnchor.constraint(greaterThanOrEqualTo: pathStackView.trailingAnchor, constant: Values.largeSpacing).isActive = true
    }
    
    private func getPathRow(forSnode snode: LokiAPITarget, at location: LineView.Location) -> UIStackView {
        let lineView = LineView(location: location)
        lineView.set(.width, to: Values.pathRowDotSize)
        let snodeLabel = UILabel()
        snodeLabel.textColor = Colors.text
        snodeLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        var snodeDescription = snode.description
        if snodeDescription.hasPrefix("https://") {
            snodeDescription.removeFirst(8)
        }
        if let colonIndex = snodeDescription.lastIndex(of: ":") {
            snodeDescription = String(snodeDescription[snodeDescription.startIndex..<colonIndex])
        }
        snodeLabel.text = snodeDescription
        snodeLabel.lineBreakMode = .byTruncatingTail
        let stackView = UIStackView(arrangedSubviews: [ lineView, snodeLabel ])
        stackView.axis = .horizontal
        stackView.spacing = Values.largeSpacing
        return stackView
    }
    
    // MARK: Interaction
    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

// MARK: Line View
private final class LineView : UIView {
    private let location: Location
    
    enum Location {
        case top, middle, bottom
    }
    
    init(location: Location) {
        self.location = location
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(location:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(location:) instead.")
    }
    
    private func setUpViewHierarchy() {
        set(.height, to: Values.pathRowHeight)
        let lineView = UIView()
        lineView.set(.width, to: Values.pathRowLineThickness)
        lineView.backgroundColor = Colors.text
        addSubview(lineView)
        lineView.center(.horizontal, in: self)
        switch location {
        case .top: lineView.topAnchor.constraint(equalTo: centerYAnchor).isActive = true
        case .middle, .bottom: lineView.pin(.top, to: .top, of: self)
        }
        switch location {
        case .top, .middle: lineView.pin(.bottom, to: .bottom, of: self)
        case .bottom: lineView.bottomAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        let dotView = UIView()
        let dotSize = Values.pathRowDotSize
        dotView.set(.width, to: dotSize)
        dotView.set(.height, to: dotSize)
        dotView.layer.cornerRadius = dotSize / 2
        dotView.backgroundColor = Colors.text
        addSubview(dotView)
        dotView.center(in: self)
    }
}
