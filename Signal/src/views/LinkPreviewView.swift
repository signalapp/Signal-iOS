//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@objc
public enum LinkPreviewImageState: Int {
    case none
    case loading
    case loaded
    case invalid
}

// MARK: -

@objc
public protocol LinkPreviewState {
    func isLoaded() -> Bool
    func urlString() -> String?
    func displayDomain() -> String?
    func title() -> String?
    func imageState() -> LinkPreviewImageState
    func image() -> UIImage?
}

// MARK: -

@objc
public class LinkPreviewLoading: NSObject, LinkPreviewState {

    override init() {
    }

    public func isLoaded() -> Bool {
        return false
    }

    public func urlString() -> String? {
        return nil
    }

    public func displayDomain() -> String? {
        return nil
    }

    public func title() -> String? {
        return nil
    }

    public func imageState() -> LinkPreviewImageState {
        return .none
    }

    public func image() -> UIImage? {
        return nil
    }
}

// MARK: -

@objc
public class LinkPreviewDraft: NSObject, LinkPreviewState {
    private let linkPreviewDraft: OWSLinkPreviewDraft

    @objc
    public required init(linkPreviewDraft: OWSLinkPreviewDraft) {
        self.linkPreviewDraft = linkPreviewDraft
    }

    public func isLoaded() -> Bool {
        return true
    }

    public func urlString() -> String? {
        return linkPreviewDraft.urlString
    }

    public func displayDomain() -> String? {
        guard let displayDomain = linkPreviewDraft.displayDomain() else {
            owsFailDebug("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public func title() -> String? {
        return linkPreviewDraft.title
    }

    public func imageState() -> LinkPreviewImageState {
        if linkPreviewDraft.imageFilePath != nil {
            return .loaded
        } else {
            return .none
        }
    }

    public func image() -> UIImage? {
        assert(imageState() == .loaded)

        guard let imageFilepath = linkPreviewDraft.imageFilePath else {
            return nil
        }
        guard let image = UIImage(contentsOfFile: imageFilepath) else {
            owsFail("Could not load image: \(imageFilepath)")
        }
        return image
    }
}

// MARK: -

@objc
public class LinkPreviewSent: NSObject, LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    @objc
    public required init(linkPreview: OWSLinkPreview,
                  imageAttachment: TSAttachment?) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
    }

    public func isLoaded() -> Bool {
        return true
    }

    public func urlString() -> String? {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url")
            return nil
        }
        return urlString
    }

    public func displayDomain() -> String? {
        guard let displayDomain = linkPreview.displayDomain() else {
            owsFailDebug("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public func title() -> String? {
        return linkPreview.title
    }

    public func imageState() -> LinkPreviewImageState {
        guard linkPreview.imageAttachmentId != nil else {
            return .none
        }
        guard let imageAttachment = imageAttachment else {
            owsFailDebug("Missing imageAttachment.")
            return .none
        }
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return .loading
        }
        guard attachmentStream.isValidImage else {
            return .invalid
        }
        return .loaded
    }

    public func image() -> UIImage? {
        assert(imageState() == .loaded)

        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            owsFailDebug("Could not load image.")
            return nil
        }
        guard attachmentStream.isValidImage else {
            return nil
        }
        guard let imageFilepath = attachmentStream.originalFilePath else {
            owsFailDebug("Attachment is missing file path.")
            return nil
        }
        guard let image = UIImage(contentsOfFile: imageFilepath) else {
            owsFail("Could not load image: \(imageFilepath)")
        }
        return image
    }
}

// MARK: -

@objc
public protocol LinkPreviewViewDelegate {
    func linkPreviewCanCancel() -> Bool
    @objc optional func linkPreviewDidCancel()
    @objc optional func linkPreviewDidTap(urlString: String?)
}

// MARK: -

@objc
public class LinkPreviewView: UIStackView {
    private weak var delegate: LinkPreviewViewDelegate?
    private let state: LinkPreviewState

    @available(*, unavailable, message:"use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
        notImplemented()
    }

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()

    @objc
    public init(state: LinkPreviewState,
                delegate: LinkPreviewViewDelegate?) {
        self.state = state
        self.delegate = delegate

        super.init(frame: .zero)

        createContents()
    }

    private var isApproval: Bool {
        return delegate != nil
    }

    private func createContents() {

        self.isUserInteractionEnabled = true
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))

        guard state.isLoaded() else {
            createLoadingContents()
            return
        }
        guard isApproval else {
            createMessageContents()
            return
        }
        createApprovalContents()
    }

    private func createMessageContents() {
        // TODO:
    }

    private let approvalHeight: CGFloat = 76

    private var cancelButton: UIButton?

    private func createApprovalContents() {
        self.axis = .horizontal
        self.alignment = .fill
        self.distribution = .equalSpacing
        self.spacing = 8

        // Image

        if let imageView = createImageView() {
            imageView.contentMode = .scaleAspectFill
            imageView.autoPinToSquareAspectRatio()
            let imageSize = approvalHeight
            imageView.autoSetDimensions(to: CGSize(width: imageSize, height: imageSize))
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            // TODO: Cropping, stroke.
            addArrangedSubview(imageView)
        }

        // Right

        let rightStack = UIStackView()
        rightStack.axis = .horizontal
        rightStack.alignment = .fill
        rightStack.distribution = .equalSpacing
        rightStack.spacing = 8
        rightStack.setContentHuggingHorizontalLow()
        rightStack.setCompressionResistanceHorizontalLow()
        addArrangedSubview(rightStack)

        // Text

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentHuggingHorizontalLow()
        textStack.setCompressionResistanceHorizontalLow()

        if let title = state.title(),
            title.count > 0 {
            let label = UILabel()
            label.text = title
            label.textColor = Theme.primaryColor
            label.font = UIFont.ows_dynamicTypeBody
            textStack.addArrangedSubview(label)
        }
        if let displayDomain = state.displayDomain(),
            displayDomain.count > 0 {
            let label = UILabel()
            label.text = displayDomain.uppercased()
            label.textColor = Theme.secondaryColor
            label.font = UIFont.ows_dynamicTypeCaption1
            textStack.addArrangedSubview(label)
        }

        let textWrapper = UIStackView(arrangedSubviews: [textStack])
        textWrapper.axis = .horizontal
        textWrapper.alignment = .center
        textWrapper.setContentHuggingHorizontalLow()
        textWrapper.setCompressionResistanceHorizontalLow()

        rightStack.addArrangedSubview(textWrapper)

        // Cancel

        let cancelStack = UIStackView()
        cancelStack.axis = .horizontal
        cancelStack.alignment = .top
        cancelStack.setContentHuggingHigh()
        cancelStack.setCompressionResistanceHigh()

        let cancelImage: UIImage = #imageLiteral(resourceName: "quoted-message-cancel").withRenderingMode(.alwaysTemplate)
        let cancelButton = UIButton(type: .custom)
        cancelButton.setImage(cancelImage, for: .normal)
        cancelButton.addTarget(self, action: #selector(didTapCancel(sender:)), for: .touchUpInside)
        self.cancelButton = cancelButton
        cancelButton.tintColor = Theme.secondaryColor
        cancelButton.setContentHuggingHigh()
        cancelButton.setCompressionResistanceHigh()
        cancelStack.addArrangedSubview(cancelButton)

        rightStack.addArrangedSubview(cancelStack)

        // Stroke
        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryColor
        rightStack.addSubview(strokeView)
        strokeView.autoPinWidthToSuperview()
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        strokeView.autoSetDimension(.height, toSize: CGHairlineWidth())
    }

    private func createImageView() -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }

        guard state.imageState()  == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        let imageView = UIImageView()
        imageView.image = image
        return imageView
    }

    private func createLoadingContents() {
        self.axis = .vertical
        self.alignment = .center
        self.autoSetDimension(.height, toSize: approvalHeight)

        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        activityIndicator.startAnimating()
        addArrangedSubview(activityIndicator)
        let activityIndicatorSize: CGFloat = 25
        activityIndicator.autoSetDimensions(to: CGSize(width: activityIndicatorSize, height: activityIndicatorSize))
    }

    // MARK: Events

    @objc func wasTapped(sender: UIGestureRecognizer) {
        guard sender.state == .recognized else {
            return
        }
        if let cancelButton = cancelButton {
            let cancelLocation = sender.location(in: cancelButton)
            // Permissive hot area to make it very easy to cancel the link preview.
            let hotAreaInset: CGFloat = -20
            let cancelButtonHotArea = cancelButton.bounds.insetBy(dx: hotAreaInset, dy: hotAreaInset)
            if cancelButtonHotArea.contains(cancelLocation) {
                self.delegate?.linkPreviewDidCancel?()
                return
            }
        }
        self.delegate?.linkPreviewDidTap?(urlString: self.state.urlString())
    }

    @objc func didTapCancel(sender: UIButton) {
        self.delegate?.linkPreviewDidCancel?()
    }
}
