import NVActivityIndicatorView

final class PathVC : BaseVC {

    // MARK: Components
    private lazy var pathStackView: UIStackView = {
        let result = UIStackView()
        result.axis = .vertical
        return result
    }()

    private lazy var spinner: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        result.set(.width, to: 64)
        result.set(.height, to: 64)
        return result
    }()

    private lazy var learnMoreButton: Button = {
        let result = Button(style: .prominentOutline, size: .large)
        result.setTitle(NSLocalizedString("vc_path_learn_more_button_title", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(learnMore), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    // MARK: Settings
    static let dotSize = CGFloat(8)
    static let expandedDotSize = CGFloat(16)
    static let rowHeight = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(75)

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        setUpNavBar()
        setUpViewHierarchy()
        registerObservers()
    }

    private func setUpNavBar() {
        setUpNavBarStyle()
        setNavBarTitle(NSLocalizedString("vc_path_title", comment: ""))
    }

    private func setUpViewHierarchy() {
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = NSLocalizedString("vc_path_explanation", comment: "")
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up path stack view
        let pathStackViewContainer = UIView()
        pathStackViewContainer.addSubview(pathStackView)
        pathStackView.pin([ UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: pathStackViewContainer)
        pathStackView.center(in: pathStackViewContainer)
        pathStackView.leadingAnchor.constraint(greaterThanOrEqualTo: pathStackViewContainer.leadingAnchor).isActive = true
        pathStackViewContainer.trailingAnchor.constraint(greaterThanOrEqualTo: pathStackView.trailingAnchor).isActive = true
        pathStackViewContainer.addSubview(spinner)
        spinner.leadingAnchor.constraint(greaterThanOrEqualTo: pathStackViewContainer.leadingAnchor).isActive = true
        spinner.topAnchor.constraint(greaterThanOrEqualTo: pathStackViewContainer.topAnchor).isActive = true
        pathStackViewContainer.trailingAnchor.constraint(greaterThanOrEqualTo: spinner.trailingAnchor).isActive = true
        pathStackViewContainer.bottomAnchor.constraint(greaterThanOrEqualTo: spinner.bottomAnchor).isActive = true
        spinner.center(in: pathStackViewContainer)
        // Set up rebuild path button
        let learnMoreButtonContainer = UIView()
        learnMoreButtonContainer.addSubview(learnMoreButton)
        learnMoreButton.pin(.leading, to: .leading, of: learnMoreButtonContainer, withInset: isIPhone5OrSmaller ? 64 : 80)
        learnMoreButton.pin(.top, to: .top, of: learnMoreButtonContainer)
        learnMoreButtonContainer.pin(.trailing, to: .trailing, of: learnMoreButton, withInset: isIPhone5OrSmaller ? 64 : 80)
        learnMoreButtonContainer.pin(.bottom, to: .bottom, of: learnMoreButton)
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ explanationLabel, topSpacer, pathStackViewContainer, bottomSpacer, learnMoreButtonContainer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        mainStackView.layoutMargins = UIEdgeInsets(top: Values.largeSpacing, left: Values.largeSpacing, bottom: Values.largeSpacing, right: Values.largeSpacing)
        mainStackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        // Set up spacer constraints
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor).isActive = true
        // Perform initial update
        update()
    }

    private func registerObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleBuildingPathsNotification), name: .buildingPaths, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handlePathsBuiltNotification), name: .pathsBuilt, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handleOnionRequestPathCountriesLoadedNotification), name: .onionRequestPathCountriesLoaded, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Updating
    @objc private func handleBuildingPathsNotification() { update() }
    @objc private func handlePathsBuiltNotification() { update() }
    @objc private func handleOnionRequestPathCountriesLoadedNotification() { update() }

    private func update() {
        pathStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !OnionRequestAPI.paths.isEmpty {
            let pathToDisplay = OnionRequestAPI.paths.first!
            let dotAnimationRepeatInterval = Double(pathToDisplay.count) + 2
            let snodeRows: [UIStackView] = pathToDisplay.enumerated().map { index, snode in
                let isGuardSnode = (snode == pathToDisplay.first!)
                return getPathRow(snode: snode, location: .middle, dotAnimationStartDelay: Double(index) + 2, dotAnimationRepeatInterval: dotAnimationRepeatInterval, isGuardSnode: isGuardSnode)
            }
            let youRow = getPathRow(title: NSLocalizedString("vc_path_device_row_title", comment: ""), subtitle: nil, location: .top, dotAnimationStartDelay: 1, dotAnimationRepeatInterval: dotAnimationRepeatInterval)
            let destinationRow = getPathRow(title: NSLocalizedString("vc_path_destination_row_title", comment: ""), subtitle: nil, location: .bottom, dotAnimationStartDelay: Double(pathToDisplay.count) + 2, dotAnimationRepeatInterval: dotAnimationRepeatInterval)
            let rows = [ youRow ] + snodeRows + [ destinationRow ]
            rows.forEach { pathStackView.addArrangedSubview($0) }
            spinner.stopAnimating()
            UIView.animate(withDuration: 0.25) {
                self.spinner.alpha = 0
            }
        } else {
            spinner.startAnimating()
            UIView.animate(withDuration: 0.25) {
                self.spinner.alpha = 1
            }
        }
    }

    // MARK: General
    private func getPathRow(title: String, subtitle: String?, location: LineView.Location, dotAnimationStartDelay: Double, dotAnimationRepeatInterval: Double) -> UIStackView {
        let lineView = LineView(location: location, dotAnimationStartDelay: dotAnimationStartDelay, dotAnimationRepeatInterval: dotAnimationRepeatInterval)
        lineView.set(.width, to: PathVC.expandedDotSize)
        lineView.set(.height, to: PathVC.rowHeight)
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = title
        titleLabel.lineBreakMode = .byTruncatingTail
        let titleStackView = UIStackView(arrangedSubviews: [ titleLabel ])
        titleStackView.axis = .vertical
        if let subtitle = subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.textColor = Colors.text
            subtitleLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
            subtitleLabel.text = subtitle
            subtitleLabel.lineBreakMode = .byTruncatingTail
            titleStackView.addArrangedSubview(subtitleLabel)
        }
        let stackView = UIStackView(arrangedSubviews: [ lineView, titleStackView ])
        stackView.axis = .horizontal
        stackView.spacing = Values.largeSpacing
        stackView.alignment = .center
        return stackView
    }

    private func getPathRow(snode: Snode, location: LineView.Location, dotAnimationStartDelay: Double, dotAnimationRepeatInterval: Double, isGuardSnode: Bool) -> UIStackView {
        let country = IP2Country.isInitialized ? (IP2Country.shared.countryNamesCache[snode.ip] ?? "Resolving...") : "Resolving..."
        let title = isGuardSnode ? NSLocalizedString("vc_path_guard_node_row_title", comment: "") : NSLocalizedString("vc_path_service_node_row_title", comment: "")
        return getPathRow(title: title, subtitle: country, location: location, dotAnimationStartDelay: dotAnimationStartDelay, dotAnimationRepeatInterval: dotAnimationRepeatInterval)
    }
    
    // MARK: Interaction
    @objc private func learnMore() {
        let urlAsString = "https://getsession.org/faq/#onion-routing"
        let url = URL(string: urlAsString)!
        UIApplication.shared.open(url)
    }
}

// MARK: Line View
private final class LineView : UIView {
    private let location: Location
    private let dotAnimationStartDelay: Double
    private let dotAnimationRepeatInterval: Double
    private var dotViewWidthConstraint: NSLayoutConstraint!
    private var dotViewHeightConstraint: NSLayoutConstraint!
    private var dotViewAnimationTimer: Timer!

    enum Location {
        case top, middle, bottom
    }

    private lazy var dotView: UIView = {
        let result = UIView()
        result.layer.cornerRadius = PathVC.dotSize / 2
        let glowRadius: CGFloat = isLightMode ? 1 : 2
        let glowColor = isLightMode ? UIColor.black.withAlphaComponent(0.4) : UIColor.black
        let glowConfiguration = UIView.CircularGlowConfiguration(size: PathVC.dotSize, color: glowColor, isAnimated: true, animationDuration: 0.5, radius: glowRadius)
        result.setCircularGlow(with: glowConfiguration)
        result.backgroundColor = Colors.accent
        return result
    }()
    
    init(location: Location, dotAnimationStartDelay: Double, dotAnimationRepeatInterval: Double) {
        self.location = location
        self.dotAnimationStartDelay = dotAnimationStartDelay
        self.dotAnimationRepeatInterval = dotAnimationRepeatInterval
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(location:dotAnimationStartDelay:dotAnimationRepeatInterval:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(location:dotAnimationStartDelay:dotAnimationRepeatInterval:) instead.")
    }
    
    private func setUpViewHierarchy() {
        let lineView = UIView()
        lineView.set(.width, to: Values.separatorThickness)
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
        let dotSize = PathVC.dotSize
        dotViewWidthConstraint = dotView.set(.width, to: dotSize)
        dotViewHeightConstraint = dotView.set(.height, to: dotSize)
        addSubview(dotView)
        dotView.center(in: self)
        Timer.scheduledTimer(withTimeInterval: dotAnimationStartDelay, repeats: false) { [weak self] _ in
            guard let strongSelf = self else { return }
            strongSelf.animate()
            strongSelf.dotViewAnimationTimer = Timer.scheduledTimer(withTimeInterval: strongSelf.dotAnimationRepeatInterval, repeats: true) { _ in
                guard let strongSelf = self else { return }
                strongSelf.animate()
            }
        }
    }

    deinit {
        dotViewAnimationTimer?.invalidate()
    }

    private func animate() {
        expandDot()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in
            self?.collapseDot()
        }
    }

    private func expandDot() {
        let newSize = PathVC.expandedDotSize
        let newGlowRadius: CGFloat = isLightMode ? 4 : 6
        let newGlowColor = Colors.accent.withAlphaComponent(0.6)
        updateDotView(size: newSize, glowRadius: newGlowRadius, glowColor: newGlowColor)
    }

    private func collapseDot() {
        let newSize = PathVC.dotSize
        let newGlowRadius: CGFloat = isLightMode ? 1 : 2
        let newGlowColor = isLightMode ? UIColor.black.withAlphaComponent(0.4) : UIColor.black
        updateDotView(size: newSize, glowRadius: newGlowRadius, glowColor: newGlowColor)
    }

    private func updateDotView(size: CGFloat, glowRadius: CGFloat, glowColor: UIColor) {
        let frame = CGRect(center: dotView.center, size: CGSize(width: size, height: size))
        dotViewWidthConstraint.constant = size
        dotViewHeightConstraint.constant = size
        UIView.animate(withDuration: 0.5) {
            self.layoutIfNeeded()
            self.dotView.frame = frame
            self.dotView.layer.cornerRadius = size / 2
            let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: glowColor, isAnimated: true, animationDuration: 0.5, radius: glowRadius)
            self.dotView.setCircularGlow(with: glowConfiguration)
            self.dotView.backgroundColor = Colors.accent
        }
    }
}
