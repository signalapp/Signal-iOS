//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import YYImage

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
    var imageSize: CGSize { get }
    func previewDescription() -> String?
    func date() -> Date?
    var isGroupInviteLink: Bool { get }
    var activityIndicatorStyle: UIActivityIndicatorView.Style { get }
    var conversationStyle: ConversationStyle? { get }
}

// MARK: -

@objc
public enum LinkPreviewLinkType: UInt {
    case preview
    case incomingMessage
    case outgoingMessage
    case incomingMessageGroupInviteLink
    case outgoingMessageGroupInviteLink
}

// MARK: -

@objc
public class LinkPreviewLoading: NSObject, LinkPreviewState {

    public let linkType: LinkPreviewLinkType

    @objc
    required init(linkType: LinkPreviewLinkType) {
        self.linkType = linkType
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

    public let imageSize: CGSize = .zero

    public func previewDescription() -> String? {
        return nil
    }

    public func date() -> Date? {
        return nil
    }

    public var isGroupInviteLink: Bool {
        switch linkType {
        case .incomingMessageGroupInviteLink,
             .outgoingMessageGroupInviteLink:
            return true
        default:
            return false
        }
    }

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        switch linkType {
        case .incomingMessageGroupInviteLink:
            return .gray
        case .outgoingMessageGroupInviteLink:
            return .white
        default:
            return LinkPreviewView.defaultActivityIndicatorStyle
        }
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

@objc
public class LinkPreviewDraft: NSObject, LinkPreviewState {
    let linkPreviewDraft: OWSLinkPreviewDraft

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

    public var imageSize: CGSize {
        guard let image = self.image() else {
            return .zero
        }
        return image.size
    }

    public func previewDescription() -> String? {
        linkPreviewDraft.previewDescription
    }

    public func date() -> Date? {
        linkPreviewDraft.date
    }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
    }

    public let conversationStyle: ConversationStyle? = nil
}

// MARK: -

@objc
public class LinkPreviewSent: NSObject, LinkPreviewState {
    private let linkPreview: OWSLinkPreview
    private let imageAttachment: TSAttachment?

    private let _conversationStyle: ConversationStyle
    public var conversationStyle: ConversationStyle? {
        _conversationStyle
    }

    @objc
    public required init(linkPreview: OWSLinkPreview,
                  imageAttachment: TSAttachment?,
                  conversationStyle: ConversationStyle) {
        self.linkPreview = linkPreview
        self.imageAttachment = imageAttachment
        _conversationStyle = conversationStyle
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
        guard let value = linkPreview.title?.filterForDisplay,
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

    @objc
    public var imageSize: CGSize {
        guard let attachmentStream = imageAttachment as? TSAttachmentStream else {
            return CGSize.zero
        }
        let pixelSize = attachmentStream.imageSize()
        return CGSize(width: (pixelSize.width / UIScreen.main.scale),
                      height: (pixelSize.height / UIScreen.main.scale))
    }

    public func previewDescription() -> String? {
        linkPreview.previewDescription
    }

    public func date() -> Date? {
        linkPreview.date
    }

    public let isGroupInviteLink = false

    public var activityIndicatorStyle: UIActivityIndicatorView.Style {
        LinkPreviewView.defaultActivityIndicatorStyle
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

    @objc
    public enum Rounding: UInt {
        case none
        case asymmetrical
        case circular
    }

    private let rounding: Rounding
    fileprivate var isHero = false

    @objc
    public init(rounding: Rounding) {
        self.rounding = rounding

        super.init(frame: .zero)

        self.layer.mask = maskLayer
    }

    public required init?(coder aDecoder: NSCoder) {
        self.rounding = .none

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

        guard rounding != .circular else {
            maskLayer.path = UIBezierPath(ovalIn: layerBounds).cgPath
            return
        }

        // One of the corners has assymetrical rounding to match the input toolbar border.
        // This is somewhat inconvenient.
        let upperLeft = CGPoint(x: 0, y: 0)
        let upperRight = CGPoint(x: layerBounds.size.width, y: 0)
        let lowerRight = CGPoint(x: layerBounds.size.width, y: layerBounds.size.height)
        let lowerLeft = CGPoint(x: 0, y: layerBounds.size.height)

        let bigRounding: CGFloat = 14
        let smallRounding: CGFloat = 6

        let upperLeftRounding: CGFloat
        let upperRightRounding: CGFloat
        if rounding == .asymmetrical {
            upperLeftRounding = CurrentAppContext().isRTL ? smallRounding : bigRounding
            upperRightRounding = CurrentAppContext().isRTL ? bigRounding : smallRounding
        } else {
            upperLeftRounding = smallRounding
            upperRightRounding = smallRounding
        }
        let lowerRightRounding = isHero ? 0 : smallRounding
        let lowerLeftRounding = isHero ? 0 : smallRounding

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

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    @objc
    public var state: LinkPreviewState? {
        didSet {
            AssertIsOnMainThread()
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

        guard state.isLoaded() else {
            createDraftLoadingContents(state: state)
            return
        }
        if isDraft {
            createDraftContents(state: state)
        } else if state.isGroupInviteLink {
            createGroupLinkContents()
        } else {
            createSentContents()
        }
    }

    private func createSentContents() {
        guard let state = state else {
            owsFailDebug("Invalid state")
            return
        }
        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return
        }

        self.addBackgroundView(withBackgroundColor: Theme.secondaryBackgroundColor)

        if let imageView = createImageView(state: state) {
            if sentIsHero(state: state) {
                createHeroSentContents(state: state,
                                       conversationStyle: conversationStyle,
                                       imageView: imageView)
            } else if state.previewDescription()?.isEmpty == false,
                state.title()?.isEmpty == false {
                createNonHeroWithDescriptionSentContents(state: state, imageView: imageView)
            } else {
                createNonHeroSentContents(state: state, imageView: imageView)
            }
        } else {
            createNonHeroSentContents(state: state, imageView: nil)
        }
    }

    private func createGroupLinkContents() {
        guard let state = state else {
            owsFailDebug("Invalid state")
            return
        }

        self.addBackgroundView(withBackgroundColor: Theme.secondaryBackgroundColor)

        self.layoutMargins = .zero
        self.axis = .horizontal
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = UIEdgeInsets(top: sentNonHeroVMargin,
                                          left: sentNonHeroHMargin,
                                          bottom: sentNonHeroVMargin,
                                          right: sentNonHeroHMargin)
        self.spacing = sentNonHeroHSpacing

        if let imageView = createImageView(state: state, rounding: .circular) {
            imageView.autoSetDimensions(to: CGSize(square: sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setContentHuggingHigh()
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            addArrangedSubview(imageView)
        }

        let textStack = createGroupLinkTextStack(state: state)
        addArrangedSubview(textStack)

        sentBodyView = self
    }

    private func createGroupLinkTextStack(state: LinkPreviewState) -> UIStackView {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = sentVSpacing

        if let titleLabel = sentTitleLabel(state: state) {
            textStack.addArrangedSubview(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            textStack.addArrangedSubview(descriptionLabel)
        }

        return textStack
    }

    private func sentHeroImageSize(state: LinkPreviewState,
                                   conversationStyle: ConversationStyle) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth
        let imageSize = state.imageSize
        let minImageHeight: CGFloat = maxMessageWidth * 0.5
        let maxImageHeight: CGFloat = maxMessageWidth
        let rawImageHeight = maxMessageWidth * imageSize.height / imageSize.width
        let imageHeight: CGFloat = min(maxImageHeight, max(minImageHeight, rawImageHeight))
        return CGSizeCeil(CGSize(width: maxMessageWidth, height: imageHeight))
    }

    private func createHeroSentContents(state: LinkPreviewState,
                                        conversationStyle: ConversationStyle,
                                        imageView: UIImageView) {
        self.layoutMargins = .zero
        self.axis = .vertical
        self.alignment = .fill

        let heroImageSize = sentHeroImageSize(state: state,
                                              conversationStyle: conversationStyle)
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

    private func createNonHeroWithDescriptionSentContents(state: LinkPreviewState, imageView: UIImageView?) {
        self.axis = .vertical
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = UIEdgeInsets(top: sentNonHeroVMargin,
                                          left: sentNonHeroHMargin,
                                          bottom: sentNonHeroVMargin,
                                          right: sentNonHeroHMargin)
        self.spacing = sentVSpacing
        self.alignment = .fill

        let titleStack = UIStackView()
        titleStack.isLayoutMarginsRelativeArrangement = true
        titleStack.axis = .horizontal
        titleStack.spacing = sentNonHeroHSpacing
        titleStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: sentVSpacing, right: 0)
        addArrangedSubview(titleStack)

        if let imageView = imageView {
            imageView.autoSetDimensions(to: CGSize(square: sentNonHeroImageSize))
            imageView.contentMode = .scaleAspectFill
            imageView.setCompressionResistanceHigh()
            imageView.clipsToBounds = true
            // TODO: Cropping, stroke.

            let containerView = UIView()
            containerView.addSubview(imageView)
            containerView.autoSetDimension(.height, toSize: sentNonHeroImageSize, relation: .greaterThanOrEqual)

            imageView.autoCenterInSuperview()
            imageView.autoPinEdge(toSuperviewEdge: .leading)
            imageView.autoPinEdge(toSuperviewEdge: .trailing)
            titleStack.addArrangedSubview(containerView)
        }

        if let titleLabel = sentTitleLabel(state: state) {
            titleStack.addArrangedSubview(titleLabel)
        } else {
            owsFailDebug("Text stack required")
        }

        if let descriptionLabel = sentDescriptionLabel(state: state) {
            addArrangedSubview(descriptionLabel)
        } else {
            owsFailDebug("Description label required")
        }

        let domainLabel = sentDomainLabel(state: state)
        addArrangedSubview(domainLabel)
        sentBodyView = self
    }

    private func createNonHeroSentContents(state: LinkPreviewState,
                                           imageView: UIImageView?) {
        self.layoutMargins = .zero
        self.axis = .horizontal
        self.isLayoutMarginsRelativeArrangement = true
        self.layoutMargins = UIEdgeInsets(top: sentNonHeroVMargin,
                                          left: sentNonHeroHMargin,
                                          bottom: sentNonHeroVMargin,
                                          right: sentNonHeroHMargin)
        self.spacing = sentNonHeroHSpacing

        if let imageView = imageView {
            imageView.autoSetDimensions(to: CGSize(square: sentNonHeroImageSize))
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

    private func createSentTextStack(state: LinkPreviewState) -> UIStackView {
        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = sentVSpacing

        if let titleLabel = sentTitleLabel(state: state) {
            textStack.addArrangedSubview(titleLabel)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            textStack.addArrangedSubview(descriptionLabel)
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
    private let sentNonHeroHMargin: CGFloat = 12
    private let sentNonHeroVMargin: CGFloat = 12
    private let sentNonHeroImageSize: CGFloat = 64
    private let sentNonHeroHSpacing: CGFloat = 8

    private let sentHeroHMargin: CGFloat = 12
    private let sentHeroVMargin: CGFloat = 12

    private func sentIsHero(state: LinkPreviewState) -> Bool {
        if isSticker(state: state) || state.isGroupInviteLink {
            return false
        }

        let imageSize = state.imageSize
        return imageSize.width >= sentMinimumHeroSize && imageSize.height >= sentMinimumHeroSize
    }

    private func isSticker(state: LinkPreviewState) -> Bool {
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
    private let sentDescriptionLineCount: Int = 3

    private func sentTitleLabel(state: LinkPreviewState) -> UILabel? {
        guard let text = state.title() else {
            return nil
        }
        let label = UILabel()
        label.text = text
        label.font = UIFont.ows_dynamicTypeSubheadline.ows_semibold()
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = sentTitleLineCount
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func sentDescriptionLabel(state: LinkPreviewState) -> UILabel? {
        guard let text = state.previewDescription() else { return nil }
        let label = UILabel()
        label.text = text
        label.font = UIFont.ows_dynamicTypeSubheadline
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = sentDescriptionLineCount
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func sentDomainLabel(state: LinkPreviewState) -> UILabel {
        let label = UILabel()

        var labelText: String
        if let displayDomain = state.displayDomain(),
            displayDomain.count > 0 {
            labelText = displayDomain.lowercased()
        } else {
            labelText = NSLocalizedString("LINK_PREVIEW_UNKNOWN_DOMAIN", comment: "Label for link previews with an unknown host.").uppercased()
        }
        if let date = state.date() {
            labelText.append(" ⋅ \(Self.dateFormatter.string(from: date))")
        }
        label.text = labelText
        label.font = UIFont.ows_dynamicTypeCaption1
        label.textColor = Theme.secondaryTextAndIconColor
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
            imageView.autoSetDimensions(to: CGSize(square: imageSize))
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
            label.textColor = Theme.primaryTextColor
            label.font = UIFont.ows_dynamicTypeBody
            textStack.addArrangedSubview(label)
        }
        if let description = state.previewDescription(), description.count > 0 {
            let label = UILabel()
            label.text = description
            label.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
            label.font = UIFont.ows_dynamicTypeSubheadline
            textStack.addArrangedSubview(label)
        }
        if let displayDomain = state.displayDomain(),
            displayDomain.count > 0 {
            let label = UILabel()
            var labelText = displayDomain.lowercased()
            if let date = state.date() {
                labelText.append(" ⋅ \(Self.dateFormatter.string(from: date))")
            }
            label.text = labelText
            label.textColor = Theme.secondaryTextAndIconColor
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
        cancelButton.tintColor = Theme.secondaryTextAndIconColor
        cancelButton.setContentHuggingHigh()
        cancelButton.setCompressionResistanceHigh()
        cancelStack.addArrangedSubview(cancelButton)

        rightStack.addArrangedSubview(cancelStack)

        // Stroke
        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryTextAndIconColor
        rightStack.addSubview(strokeView)
        strokeView.autoPinWidthToSuperview()
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        strokeView.autoSetDimension(.height, toSize: CGHairlineWidth())
    }

    private func createImageView(state: LinkPreviewState,
                                 rounding roundingParam: LinkPreviewImageView.Rounding? = nil) -> UIImageView? {
        guard state.isLoaded() else {
            owsFailDebug("State not loaded.")
            return nil
        }

        guard state.imageState() == .loaded else {
            return nil
        }
        guard let image = state.image() else {
            owsFailDebug("Could not load image.")
            return nil
        }
        let rounding: LinkPreviewImageView.Rounding = {
            if let roundingParam = roundingParam {
                return roundingParam
            }
            return self.hasAsymmetricalRounding ? .asymmetrical : .none
        }()
        let imageView = LinkPreviewImageView(rounding: rounding)
        imageView.image = image
        imageView.isHero = sentIsHero(state: state)
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
        let rounding: LinkPreviewImageView.Rounding = hasAsymmetricalRounding ? .asymmetrical : .none
        let imageView = LinkPreviewImageView(rounding: rounding)
        imageView.image = image
        return imageView
    }

    private func createDraftLoadingContents(state: LinkPreviewState) {
        self.axis = .vertical
        self.alignment = .center

        self.layoutConstraints.append(self.autoSetDimension(.height, toSize: draftHeight + draftMarginTop))

        let activityIndicatorStyle = state.activityIndicatorStyle
        let activityIndicator = UIActivityIndicatorView(style: activityIndicatorStyle)
        activityIndicator.startAnimating()
        addArrangedSubview(activityIndicator)
        let activityIndicatorSize: CGFloat = 25
        activityIndicator.autoSetDimensions(to: CGSize(square: activityIndicatorSize))

        // Stroke
        let strokeView = UIView()
        strokeView.backgroundColor = Theme.secondaryTextAndIconColor
        self.addSubview(strokeView)
        strokeView.autoPinWidthToSuperview(withMargin: 12)
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        strokeView.autoSetDimension(.height, toSize: CGHairlineWidth())
    }

    static var defaultActivityIndicatorStyle: UIActivityIndicatorView.Style {
        Theme.isDarkThemeEnabled
        ? .white
        : .gray
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
    public func measure(withState state: LinkPreviewState) -> CGSize {
        if let sentState = state as? LinkPreviewSent {
            return self.measure(withSentState: sentState)
        } else if let groupLinkState = state as? LinkPreviewGroupLink {
            return self.measure(withGroupLinkState: groupLinkState)
        } else if let loadingState = state as? LinkPreviewLoading {
            return self.measure(withLoadingState: loadingState)
        } else {
            owsFailDebug("Invalid state.")
            return .zero
        }
    }

    @objc
    public func measure(withLoadingState state: LinkPreviewLoading) -> CGSize {
        let size = draftHeight + draftMarginTop
        return CGSize(width: size, height: size)
    }

    @objc
    public func measure(withGroupLinkState state: LinkPreviewGroupLink) -> CGSize {

        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        let hasImage = state.imageState() != .none

        let maxMessageWidth = conversationStyle.maxMessageWidth

        var maxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        if hasImage {
            maxTextWidth -= (sentNonHeroImageSize + sentNonHeroHSpacing)
        }
        let textStackSize = sentTextStackSize(state: state, maxWidth: maxTextWidth, ignoreDomain: true)

        var result = textStackSize

        result.width += sentNonHeroImageSize + sentNonHeroHSpacing
        result.height = max(result.height, sentNonHeroImageSize)

        result.width += 2 * sentNonHeroHMargin
        result.height += 2 * sentNonHeroVMargin

        return CGSizeCeil(result)
    }

    @objc
    public func measure(withSentState state: LinkPreviewState) -> CGSize {

        guard let conversationStyle = state.conversationStyle else {
            owsFailDebug("Missing conversationStyle.")
            return .zero
        }

        switch state.imageState() {
        case .loaded:
            if sentIsHero(state: state) {
                return measureSentHero(state: state, conversationStyle: conversationStyle)
            } else if state.previewDescription()?.isEmpty == false,
                state.title()?.isEmpty == false {
                return measureSentNonHeroWithDescription(state: state, conversationStyle: conversationStyle)
            } else {
                return measureSentNonHero(state: state, conversationStyle: conversationStyle, hasImage: true)
            }
        default:
            return measureSentNonHero(state: state, conversationStyle: conversationStyle, hasImage: false)
        }
    }

    private func measureSentHero(state: LinkPreviewState,
                                 conversationStyle: ConversationStyle) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth
        var messageHeight: CGFloat  = 0

        let heroImageSize = sentHeroImageSize(state: state, conversationStyle: conversationStyle)
        messageHeight += heroImageSize.height

        let textStackSize = sentTextStackSize(state: state,
                                              maxWidth: maxMessageWidth - 2 * sentHeroHMargin)
        messageHeight += textStackSize.height + 2 * sentHeroVMargin

        return CGSizeCeil(CGSize(width: maxMessageWidth, height: messageHeight))
    }

    private func measureSentNonHeroWithDescription(state: LinkPreviewState,
                                                   conversationStyle: ConversationStyle) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth

        let bottomMaxTextWidth = maxMessageWidth - 2 * sentNonHeroHMargin
        let titleMaxTextWidth = bottomMaxTextWidth - (sentNonHeroImageSize + sentNonHeroHSpacing)

        let titleLabelSize = sentTitleLabel(state: state)
            .map { sentLabelSize(label: $0, maxWidth: titleMaxTextWidth) } ?? .zero
        let descriptionLabelSize = sentDescriptionLabel(state: state)
            .map { sentLabelSize(label: $0, maxWidth: bottomMaxTextWidth) } ?? .zero
        let domainLabel = sentDomainLabel(state: state)
        let domainLabelSize = sentLabelSize(label: domainLabel, maxWidth: bottomMaxTextWidth)

        let bindingTitleHeight = max(titleLabelSize.height, sentNonHeroImageSize)

        var resultSize = CGSize.zero
        resultSize.height += sentNonHeroVMargin
        resultSize.height += bindingTitleHeight
        resultSize.height += sentVSpacing * 2
        resultSize.height += descriptionLabelSize.height
        resultSize.height += sentVSpacing
        resultSize.height += domainLabelSize.height
        resultSize.height += sentNonHeroVMargin

        let titleStackWidth = titleLabelSize.width + sentNonHeroHSpacing + sentNonHeroImageSize
        resultSize.width = [titleStackWidth, descriptionLabelSize.width, domainLabelSize.width].max() ?? 0
        resultSize.width += (sentNonHeroHMargin * 2)

        return CGSizeCeil(resultSize)
    }

    private func measureSentNonHero(state: LinkPreviewState,
                                    conversationStyle: ConversationStyle,
                                    hasImage: Bool) -> CGSize {
        let maxMessageWidth = conversationStyle.maxMessageWidth

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

    private func sentLabelSize(label: UILabel, maxWidth: CGFloat) -> CGSize {
        CGSizeCeil(label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)))
    }

    private func sentTextStackSize(state: LinkPreviewState, maxWidth: CGFloat, ignoreDomain: Bool = false) -> CGSize {

        var labelSizes = [CGSize]()

        if !ignoreDomain {
            let domainLabel = sentDomainLabel(state: state)
            let domainLabelSize = sentLabelSize(label: domainLabel, maxWidth: maxWidth)
            labelSizes.append(domainLabelSize)
        }
        if let titleLabel = sentTitleLabel(state: state) {
            let titleLabelSize = sentLabelSize(label: titleLabel, maxWidth: maxWidth)
            labelSizes.append(titleLabelSize)
        }
        if let descriptionLabel = sentDescriptionLabel(state: state) {
            let descriptionLabelSize = sentLabelSize(label: descriptionLabel, maxWidth: maxWidth)
            labelSizes.append(descriptionLabelSize)
        }

        return measureTextStack(labelSizes: labelSizes)
    }

    private func measureTextStack(labelSizes: [CGSize]) -> CGSize {
        let width = labelSizes.map { $0.width }.reduce(0, max)
        let height = labelSizes.map { $0.height }.reduce(0, +) + CGFloat(labelSizes.count - 1) * sentVSpacing
        return CGSize(width: width, height: height)
    }

    @objc
    public func addBorderViews(bubbleView: OWSBubbleView) {
        if let heroImageView = self.heroImageView {
            let borderView = OWSBubbleShapeView(draw: ())
            borderView.strokeColor = Theme.primaryTextColor
            borderView.strokeThickness = CGHairlineWidthFraction(1.8)
            heroImageView.addSubview(borderView)
            bubbleView.addPartnerView(borderView)
            borderView.autoPinEdgesToSuperviewEdges()
        }
        if let sentBodyView = self.sentBodyView {
            let borderView = OWSBubbleShapeView(draw: ())
            let borderColor = (Theme.isDarkThemeEnabled ? UIColor.ows_gray60 : UIColor.ows_gray15)
            borderView.strokeColor = borderColor
            borderView.strokeThickness = CGHairlineWidthFraction(1.8)
            sentBodyView.addSubview(borderView)
            bubbleView.addPartnerView(borderView)
            borderView.autoPinEdgesToSuperviewEdges()
        } else {
            owsFailDebug("Missing sentBodyView")
        }
    }

    @objc func didTapCancel(sender: UIButton) {
        self.draftDelegate?.linkPreviewDidCancel()
    }
}
