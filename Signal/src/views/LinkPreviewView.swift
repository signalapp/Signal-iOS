//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

public extension CGPoint {
    func offsetBy(dx: CGFloat) -> CGPoint {
        return CGPoint(x: x + dx, y: y)
    }

    func offsetBy(dy: CGFloat) -> CGPoint {
        return CGPoint(x: x, y: y + dy)
    }
}

// MARK: -

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
        guard let value = linkPreviewDraft.title,
            value.count > 0 else {
                return nil
        }
        return value
    }

    public func imageState() -> LinkPreviewImageState {
        if linkPreviewDraft.imageData != nil {
            return .loaded
        } else {
            return .none
        }
    }

    public func image() -> UIImage? {
        assert(imageState() == .loaded)

        guard let imageData = linkPreviewDraft.imageData else {
            return nil
        }
        guard let image = UIImage(data: imageData) else {
            owsFailDebug("Could not load image: \(imageData.count)")
            return nil
        }
        return image
    }
}

// MARK: -

@objc
public class LinkPreviewSent: NSObject, LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    @objc public let conversationStyle: ConversationStyle

    @objc
    public var imageSize: CGSize {
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        return attachmentStream.imageSize()
    }

    @objc
    public required init(linkPreview: OWSLinkPreview,
                  imageAttachment: TSAttachment?,
                  conversationStyle: ConversationStyle) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        self.conversationStyle = conversationStyle
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
            Logger.error("Missing display domain")
            return nil
        }
        return displayDomain
    }

    public func title() -> String? {
        guard let value = linkPreview.title,
            value.count > 0 else {
                return nil
        }
        return value
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
        guard attachmentStream.isImage,
            attachmentStream.isValidImage else {
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
        guard attachmentStream.isImage,
            attachmentStream.isValidImage else {
            return nil
        }
        guard let imageFilepath = attachmentStream.originalFilePath else {
            owsFailDebug("Attachment is missing file path.")
            return nil
        }

        guard NSData.ows_isValidImage(atPath: imageFilepath, mimeType: attachmentStream.contentType) else {
            owsFailDebug("Invalid image.")
            return nil
        }

        let imageClass: UIImage.Type
        if attachmentStream.contentType == OWSMimeTypeImageWebp {
            imageClass = YYImage.self
        } else {
            imageClass = UIImage.self
        }

        guard let image = imageClass.init(contentsOfFile: imageFilepath) else {
            owsFailDebug("Could not load image: \(imageFilepath)")
            return nil
        }

        return image
    }
}

// MARK: -

@objc
public protocol LinkPreviewViewDraftDelegate {
    func linkPreviewCanCancel() -> Bool
    func linkPreviewDidCancel()
}

// MARK: -

@objc
public class LinkPreviewImageView: UIImageView {
    private let maskLayer = CAShapeLayer()

    private let hasAsymmetricalRounding: Bool

    @objc
    public init(hasAsymmetricalRounding: Bool) {
        self.hasAsymmetricalRounding = hasAsymmetricalRounding

        super.init(frame: .zero)

        self.layer.mask = maskLayer
    }

    public required init?(coder aDecoder: NSCoder) {
        self.hasAsymmetricalRounding = false

        super.init(coder: aDecoder)
    }

    public override var bounds: CGRect {
        didSet {
            updateMaskLayer()
        }
    }

    public override var frame: CGRect {
        didSet {
            updateMaskLayer()
        }
    }

    public override var center: CGPoint {
        didSet {
            updateMaskLayer()
        }
    }

    private func updateMaskLayer() {
        let layerBounds = self.bounds

        // One of the corners has assymetrical rounding to match the input toolbar border.
        // This is somewhat inconvenient.
        let upperLeft = CGPoint(x: 0, y: 0)
        let upperRight = CGPoint(x: layerBounds.size.width, y: 0)
        let lowerRight = CGPoint(x: layerBounds.size.width, y: layerBounds.size.height)
        let lowerLeft = CGPoint(x: 0, y: layerBounds.size.height)

        let bigRounding: CGFloat = 14
        let smallRounding: CGFloat = 4

        let upperLeftRounding: CGFloat
        let upperRightRounding: CGFloat
        if hasAsymmetricalRounding {
            upperLeftRounding = CurrentAppContext().isRTL ? smallRounding : bigRounding
            upperRightRounding = CurrentAppContext().isRTL ? bigRounding : smallRounding
        } else {
            upperLeftRounding = smallRounding
            upperRightRounding = smallRounding
        }
        let lowerRightRounding = smallRounding
        let lowerLeftRounding = smallRounding

        let path = UIBezierPath()

        // It's sufficient to "draw" the rounded corners and not the edges that connect them.
        path.addArc(withCenter: upperLeft.offsetBy(dx: +upperLeftRounding).offsetBy(dy: +upperLeftRounding),
                    radius: upperLeftRounding,
                    startAngle: CGFloat.pi * 1.0,
                    endAngle: CGFloat.pi * 1.5,
                    clockwise: true)

        path.addArc(withCenter: upperRight.offsetBy(dx: -upperRightRounding).offsetBy(dy: +upperRightRounding),
                    radius: upperRightRounding,
                    startAngle: CGFloat.pi * 1.5,
                    endAngle: CGFloat.pi * 0.0,
                    clockwise: true)

        path.addArc(withCenter: lowerRight.offsetBy(dx: -lowerRightRounding).offsetBy(dy: -lowerRightRounding),
                    radius: lowerRightRounding,
                    startAngle: CGFloat.pi * 0.0,
                    endAngle: CGFloat.pi * 0.5,
                    clockwise: true)

        path.addArc(withCenter: lowerLeft.offsetBy(dx: +lowerLeftRounding).offsetBy(dy: -lowerLeftRounding),
                    radius: lowerLeftRounding,
                    startAngle: CGFloat.pi * 0.5,
                    endAngle: CGFloat.pi * 1.0,
                    clockwise: true)

        maskLayer.path = path.cgPath
    }
}

// MARK: -

@objc
public class LinkPreviewView: UIStackView {
    private weak var draftDelegate: LinkPreviewViewDraftDelegate?

    @objc
    public var state: LinkPreviewState? {
        didSet {
            AssertIsOnMainThread()
            assert(state == nil || oldValue == nil)

            updateContents()
        }
    }

    @objc
    public var hasAsymmetricalRounding: Bool = false {
        didSet {
            AssertIsOnMainThread()

            if hasAsymmetricalRounding != oldValue {
                updateContents()
            }
        }
    }

    @available(*, unavailable, message:"use other constructor instead.")
    required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @available(*, unavailable, message:"use other constructor instead.")
    override init(frame: CGRect) {
        notImplemented()
    }

    private var cancelButton: UIButton?
    private weak var heroImageView: UIView?
    private weak var sentBodyView: UIView?
    private var layoutConstraints = [NSLayoutConstraint]()

    @objc
    public init(draftDelegate: LinkPreviewViewDraftDelegate?) {
        self.draftDelegate = draftDelegate

        super.init(frame: .zero)

        if let draftDelegate = draftDelegate,
            draftDelegate.linkPreviewCanCancel() {
            self.isUserInteractionEnabled = true
            self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(wasTapped)))
        }
    }

    private var isDraft: Bool {
        return draftDelegate != nil
    }

    private func resetContents() {
        for subview in subviews {
            subview.removeFromSuperview()
        }
        self.axis = .horizontal
        self.alignment = .center
        self.distribution = .fill
        self.spacing = 0
        self.isLayoutMarginsRelativeArrangement = false
        self.layoutMargins = .zero

        cancelButton = nil
        heroImageView = nil
        sentBodyView = nil

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []
    }

    private func updateContents() {
        resetContents()

        guard let state = state else {
            return
        }

        guard isDraft else {
            createSentContents()
            return
        }
        guard state.isLoaded() else {
            createDraftLoadingContents()
            return
        }
        createDraftContents(state: state)
    }

    private func createSentContents() {
        guard let state = state as? LinkPreviewSent else {
            owsFailDebug("Invalid state")
            return
        }

        self.addBackgroundView(withBackgroundColor: Theme.backgroundColor)

        if let imageView = createImageView(state: state) {
            if sentIsHero(state: state) {
                createHeroSentContents(state: state,
                                       imageView: imageView)
            } else {
                createNonHeroSentContents(state: state,
                                          imageView: imageView)
            }
        } else {
            createNonHeroSentContents(state: state,
                                      imageView: nil)
        }
    }

    private func sentHeroImageSize(state: LinkPreviewSent) -> CGSize {
        let maxMessageWidth = state.conversationStyle.maxMessageWidth
        let imageSize = state.imageSize
        let minImageHeight: CGFloat = maxMessageWidth * 0.5
        let maxImageHeight: CGFloat = maxMessageWidth
        let rawImageHeight = maxMessageWidth * imageSize.height / imageSize.width
        let imageHeight: CGFloat = min(maxImageHeight, max(minImageHeight, rawImageHeight))
        return CGSizeCeil(CGSize(width: maxMessageWidth, height: imageHeight))
    }

    private func createHeroSentContents(state: LinkPreviewSent,
                                        imageView: UIImageView) {
        self.layoutMargins = .zero
        self.axis = .vertical
        self.alignment = .fill

        let heroImageSize = sentHeroImageSize(state: state)
        imageView.autoSetDimensions(to: heroImageSize)
        imageView.contentMode = .scaleAspectFill
        imageView.setContentHuggingHigh()
        imageView.setCompressionResistanceHigh()
        imageView.clipsToBounds = true
        // TODO: Cropping, stroke.
        addArrangedSubview(imageView)

        let textStack = createSentTextStack(state: state)
        textStack.isLayoutMarginsRelativeArrangement = true
        textStack.layoutMargins = UIEdgeInsets(top: sentHeroVMargin, left: sentHeroHMargin, bottom: sentHeroVMargin, right: sentHeroHMargin)
        addArrangedSubview(textStack)

        heroImageView = imageView
        sentBodyView = textStack
    }

    private func createNonHeroSentContents(state: LinkPreviewSent,
                                           imageView: UIImageView?) {
        self.layoutMargins = .zero
        self.axis = .horizontal
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = UIEdgeInsets(top: sentNonHeroVMargin, left: sentNonHeroHMargin, bottom: sentNonHeroVMargin, right: sentNonHeroHMargin)
        self.spacing = sentNonHeroHSpacing

        if let imageView = imageView {
            imageView.autoSetDimensions(to: CGSize(width: sentNonHeroImageSize, height: sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            // TODO: Cropping, stroke.
            addArrangedSubview(imageView)
        }

        let textStack = createSentTextStack(state: state)
        addArrangedSubview(textStack)

        sentBodyView = self
    }

    private func createSentTextStack(state: LinkPreviewSent) -> UIStackView {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = sentVSpacing

        if let titleLabel = sentTitleLabel(state: state) {
            textStack.addArrangedSubview(titleLabel)
        }
        let domainLabel = sentDomainLabel(state: state)
        textStack.addArrangedSubview(domainLabel)

        return textStack
    }

    private let sentMinimumHeroSize: CGFloat = 200

    private let sentTitleFontSizePoints: CGFloat = 17
    private let sentDomainFontSizePoints: CGFloat = 12
    private let sentVSpacing: CGFloat = 4

    // The "sent message" mode has two submodes: "hero" and "non-hero".
    private let sentNonHeroHMargin: CGFloat = 6
    private let sentNonHeroVMargin: CGFloat = 6
    private let sentNonHeroImageSize: CGFloat = 72
    private let sentNonHeroHSpacing: CGFloat = 8

    private let sentHeroHMargin: CGFloat = 12
    private let sentHeroVMargin: CGFloat = 7

    private func sentIsHero(state: LinkPreviewSent) -> Bool {
        if isSticker(state: state) {
            return false
        }

        let imageSize = state.imageSize
        return imageSize.width >= sentMinimumHeroSize && imageSize.height >= sentMinimumHeroSize
    }

    private func isSticker(state: LinkPreviewSent) -> Bool {
        guard let urlString = state.urlString() else {
            owsFailDebug("Link preview is missing url.")
            return false
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Could not parse URL.")
            return false
        }
        return StickerPackInfo.isStickerPackShare(url)
    }

    private let sentTitleLineCount: Int = 2

    private func sentTitleLabel(state: LinkPreviewState) -> UILabel? {
        guard let text = state.title() else {
            return nil
        }
        let label = UILabel()
        label.text = text
        label.font = UIFont.systemFont(ofSize: sentTitleFontSizePoints).ows_mediumWeight()
        label.textColor = Theme.primaryColor
        label.numberOfLines = sentTitleLineCount
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func sentDomainLabel(state: LinkPreviewState) -> UILabel {
        let label = UILabel()
        if let displayDomain = state.displayDomain(),
            displayDomain.count > 0 {
            label.text = displayDomain.uppercased()
        } else {
            label.text = NSLocalizedString("LINK_PREVIEW_UNKNOWN_DOMAIN", comment: "Label for link previews with an unknown host.").uppercased()
        }
        label.font = UIFont.systemFont(ofSize: sentDomainFontSizePoints)
        label.textColor = Theme.secondaryColor
        return label
    }

    private let draftHeight: CGFloat = 72
    private let draftMarginTop: CGFloat = 6

    private func createDraftContents(state: LinkPreviewState) {
        self.axis = .horizontal
        self.alignment = .fill
        self.distribution = .fill
        self.spacing = 8
        self.isLayoutMarginsRelativeArrangement = true

        self.layoutConstraints.append(self.autoSetDimension(.height, toSize: draftHeight + draftMarginTop))

        // Image

        let draftImageView = createDraftImageView(state: state)
        if let imageView = draftImageView {
            imageView.contentMode = .scaleAspectFill
            imageView.autoPinToSquareAspectRatio()
            let imageSize = draftHeight
            imageView.autoSetDimensions(to: CGSize(width: imageSize, height: imageSize))
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            addArrangedSubview(imageView)
        }

        let hasImage = draftImageView != nil
        let hMarginLeading: CGFloat = hasImage ? 6 : 12
        let hMarginTrailing: CGFloat = 12
        self.layoutMargins = UIEdgeInsets(top: draftMarginTop,
                                          leading: hMarginLeading,
                                          bottom: 0,
                                          trailing: hMarginTrailing)

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

        let cancelImage = UIImage(named: "compose-cancel")?.withRenderingMode(.alwaysTemplate)
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

    private func createImageView(state: LinkPreviewState) -> UIImageView? {
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

    private func createDraftImageView(state: LinkPreviewState) -> UIImageView? {
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
        let imageView = LinkPreviewImageView(hasAsymmetricalRounding: self.hasAsymmetricalRounding)
        imageView.image = image
        return imageView
    }

    private func createDraftLoadingContents() {
        self.axis = .vertical
        self.alignment = .center

        self.layoutConstraints.append(self.autoSetDimension(.height, toSize: draftHeight + draftMarginTop))

        let activityIndicatorStyle: UIActivityIndicatorView.Style = (Theme.isDarkThemeEnabled
            ? .white
            : .gray)
        let activityIndicator = UIActivityIndicatorView(style: activityIndicatorStyle)
        activityIndicator.startAnimating()
        addArrangedSubview(activityIndicator)
        let activityIndicatorSize: CGFloat = 25
        activityIndicator.autoSetDimensions(to: CGSize(width: activityIndicatorSize, height: activityIndicatorSize))

        // Stroke
        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryColor
        self.addSubview(strokeView)
        strokeView.autoPinWidthToSuperview(withMargin: 12)
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        strokeView.autoSetDimension(.height, toSize: CGHairlineWidth())
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
                self.draftDelegate?.linkPreviewDidCancel()
                return
            }
        }
    }

    // MARK: Measurement

    @objc
    public func measure(withSentState state: LinkPreviewSent) -> CGSize {
        switch state.imageState() {
        case .loaded:
            if sentIsHero(state: state) {
                return measureSentHero(state: state)
            } else {
                return measureSentNonHero(state: state, hasImage: true)
            }
        default:
            return measureSentNonHero(state: state, hasImage: false)
        }
    }

    private func measureSentHero(state: LinkPreviewSent) -> CGSize {
        let maxMessageWidth = state.conversationStyle.maxMessageWidth
        var messageHeight: CGFloat  = 0

        let heroImageSize = sentHeroImageSize(state: state)
        messageHeight += heroImageSize.height

        let textStackSize = sentTextStackSize(state: state, maxWidth: maxMessageWidth - 2 * sentHeroHMargin)
        messageHeight += textStackSize.height + 2 * sentHeroVMargin

        return CGSizeCeil(CGSize(width: maxMessageWidth, height: messageHeight))
    }

    private func measureSentNonHero(state: LinkPreviewSent, hasImage: Bool) -> CGSize {
        let maxMessageWidth = state.conversationStyle.maxMessageWidth

        var maxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        if hasImage {
            maxTextWidth -= (sentNonHeroImageSize + sentNonHeroHSpacing)
        }
        let textStackSize = sentTextStackSize(state: state, maxWidth: maxTextWidth)

        var result = textStackSize

        if hasImage {
            result.width += sentNonHeroImageSize + sentNonHeroHSpacing
            result.height = max(result.height, sentNonHeroImageSize)
        }

        result.width += 2 * sentNonHeroHMargin
        result.height += 2 * sentNonHeroVMargin

        return CGSizeCeil(result)
    }

    private func sentTextStackSize(state: LinkPreviewSent, maxWidth: CGFloat) -> CGSize {
        let domainLabel = sentDomainLabel(state: state)
        let domainLabelSize = CGSizeCeil(domainLabel.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)))

        var result = domainLabelSize

        if let titleLabel = sentTitleLabel(state: state) {
            let titleLabelSize = CGSizeCeil(titleLabel.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)))
            let maxTitleLabelHeight: CGFloat = ceil(CGFloat(sentTitleLineCount) * titleLabel.font.lineHeight)
            result.width = max(result.width, titleLabelSize.width)
            result.height += min(maxTitleLabelHeight, titleLabelSize.height) + sentVSpacing
        }

        return result
    }

    @objc
    public func addBorderViews(bubbleView: OWSBubbleView) {
        if let heroImageView = self.heroImageView {
            let borderView = OWSBubbleShapeView(draw: ())
            borderView.strokeColor = Theme.primaryColor
            borderView.strokeThickness = CGHairlineWidthFraction(1.8)
            heroImageView.addSubview(borderView)
            bubbleView.addPartnerView(borderView)
            borderView.ows_autoPinToSuperviewEdges()
        }
        if let sentBodyView = self.sentBodyView {
            let borderView = OWSBubbleShapeView(draw: ())
            let borderColor = (Theme.isDarkThemeEnabled ? UIColor.ows_gray60 : UIColor.ows_gray15)
            borderView.strokeColor = borderColor
            borderView.strokeThickness = CGHairlineWidthFraction(1.8)
            sentBodyView.addSubview(borderView)
            bubbleView.addPartnerView(borderView)
            borderView.ows_autoPinToSuperviewEdges()
        } else {
            owsFailDebug("Missing sentBodyView")
        }
    }

    @objc func didTapCancel(sender: UIButton) {
        self.draftDelegate?.linkPreviewDidCancel()
    }
}
