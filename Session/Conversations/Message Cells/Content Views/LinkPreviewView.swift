import NVActivityIndicatorView

final class LinkPreviewView : UIView {
    private let viewItem: ConversationViewItem?
    private let maxWidth: CGFloat
    private let delegate: LinkPreviewViewDelegate
    var linkPreviewState: LinkPreviewState? { didSet { update() } }
    private lazy var imageViewContainerWidthConstraint = imageView.set(.width, to: 100)
    private lazy var imageViewContainerHeightConstraint = imageView.set(.height, to: 100)

    private lazy var sentLinkPreviewTextColor: UIColor = {
        let isOutgoing = (viewItem!.interaction.interactionType() == .outgoingMessage)
        switch (isOutgoing, AppModeManager.shared.currentAppMode) {
        case (true, .dark), (false, .light): return .black
        default: return .white
        }
    }()

    // MARK: UI Components
    private lazy var imageView: UIImageView = {
        let result = UIImageView()
        result.contentMode = .scaleAspectFill
        return result
    }()

    private lazy var imageViewContainer: UIView = {
        let result = UIView()
        result.clipsToBounds = true
        return result
    }()

    private lazy var loader: NVActivityIndicatorView = {
        let color: UIColor = isLightMode ? .black : .white
        return NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: color, padding: nil)
    }()

    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.numberOfLines = 0
        return result
    }()

    private lazy var bodyTextViewContainer = UIView()

    private lazy var hStackViewContainer = UIView()

    private lazy var hStackView = UIStackView()

    private lazy var cancelButton: UIButton = {
        let result = UIButton(type: .custom)
        let tint: UIColor = isLightMode ? .black : .white
        result.setImage(UIImage(named: "X")?.withTint(tint), for: UIControl.State.normal)
        let cancelButtonSize = LinkPreviewView.cancelButtonSize
        result.set(.width, to: cancelButtonSize)
        result.set(.height, to: cancelButtonSize)
        result.addTarget(self, action: #selector(cancel), for: UIControl.Event.touchUpInside)
        return result
    }()

    // MARK: Settings
    private static let loaderSize: CGFloat = 24
    private static let cancelButtonSize: CGFloat = 45

    // MARK: Lifecycle
    init(for viewItem: ConversationViewItem?, maxWidth: CGFloat, delegate: LinkPreviewViewDelegate) {
        self.viewItem = viewItem
        self.maxWidth = maxWidth
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(for:maxWidth:delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        // Image view
        imageViewContainerWidthConstraint.isActive = true
        imageViewContainerHeightConstraint.isActive = true
        imageViewContainer.addSubview(imageView)
        imageView.pin(to: imageViewContainer)
        // Title label
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(to: titleLabelContainer, withInset: Values.smallSpacing)
        // Horizontal stack view
        hStackView.addArrangedSubview(imageViewContainer)
        hStackView.addArrangedSubview(titleLabelContainer)
        hStackView.axis = .horizontal
        hStackView.alignment = .center
        hStackViewContainer.addSubview(hStackView)
        hStackView.pin(to: hStackViewContainer)
        // Vertical stack view
        let vStackView = UIStackView(arrangedSubviews: [ hStackViewContainer, bodyTextViewContainer ])
        vStackView.axis = .vertical
        addSubview(vStackView)
        vStackView.pin(to: self)
        // Loader
        addSubview(loader)
        let loaderSize = LinkPreviewView.loaderSize
        loader.set(.width, to: loaderSize)
        loader.set(.height, to: loaderSize)
        loader.center(in: self)
    }

    // MARK: Updating
    private func update() {
        cancelButton.removeFromSuperview()
        guard let linkPreviewState = linkPreviewState else { return }
        var image = linkPreviewState.image()
        if image == nil && (linkPreviewState is LinkPreviewDraft || linkPreviewState is LinkPreviewSent) {
            image = UIImage(named: "Link")?.withTint(isLightMode ? .black : .white)
        }
        // Image view
        let imageViewContainerSize: CGFloat = (linkPreviewState is LinkPreviewSent) ? 100 : 80
        imageViewContainerWidthConstraint.constant = imageViewContainerSize
        imageViewContainerHeightConstraint.constant = imageViewContainerSize
        imageViewContainer.layer.cornerRadius = (linkPreviewState is LinkPreviewSent) ? 0 : 8
        if linkPreviewState is LinkPreviewLoading {
            imageViewContainer.backgroundColor = .clear
        } else {
            imageViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
        }
        imageView.image = image
        imageView.contentMode = (linkPreviewState.image() == nil) ? .center : .scaleAspectFill
        // Loader
        loader.alpha = (image != nil) ? 0 : 1
        if image != nil { loader.stopAnimating() } else { loader.startAnimating() }
        // Title
        let isSent = (linkPreviewState is LinkPreviewSent)
        let isOutgoing = (viewItem?.interaction.interactionType() == .outgoingMessage)
        let textColor: UIColor
        if isSent && isOutgoing && isLightMode {
            textColor = .white
        } else {
            textColor = isDarkMode ? .white : .black
        }
        titleLabel.textColor = textColor
        titleLabel.text = linkPreviewState.title()
        // Horizontal stack view
        switch linkPreviewState {
        case is LinkPreviewSent: hStackViewContainer.backgroundColor = isDarkMode ? .black : UIColor.black.withAlphaComponent(0.06)
        default: hStackViewContainer.backgroundColor = nil
        }
        // Body text view
        bodyTextViewContainer.subviews.forEach { $0.removeFromSuperview() }
        if let viewItem = viewItem {
            let bodyTextView = VisibleMessageCell.getBodyTextView(for: viewItem, with: maxWidth, textColor: sentLinkPreviewTextColor, searchText: delegate.lastSearchedText, delegate: delegate)
            bodyTextViewContainer.addSubview(bodyTextView)
            bodyTextView.pin(to: bodyTextViewContainer, withInset: 12)
        }
        if linkPreviewState is LinkPreviewDraft {
            hStackView.addArrangedSubview(cancelButton)
        }
    }

    // MARK: Interaction
    @objc private func cancel() {
        delegate.handleLinkPreviewCanceled()
    }
}

// MARK: Delegate
protocol LinkPreviewViewDelegate : UITextViewDelegate & BodyTextViewDelegate {
    var lastSearchedText: String? { get }

    func handleLinkPreviewCanceled()
}
