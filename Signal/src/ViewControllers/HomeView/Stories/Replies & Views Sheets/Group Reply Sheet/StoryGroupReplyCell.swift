//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit
import SignalMessaging

class StoryGroupReplyCell: UITableViewCell {
    lazy var avatarView = ConversationAvatarView(sizeClass: .twentyEight, localUserDisplayMode: .asUser, useAutolayout: true)
    lazy var messageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        return label
    }()
    lazy var authorNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold
        return label
    }()
    lazy var reactionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28)
        label.textAlignment = .trailing
        return label
    }()
    lazy var bubbleView: UIView = {
        let view = UIView()
        view.backgroundColor = .ows_gray80
        view.layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 7)
        return view
    }()
    lazy var bubbleCornerMaskLayer = CAShapeLayer()

    private lazy var sendingSpinner = SendingSpinner()

    private lazy var sendFailureIcon: UIView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = #imageLiteral(resourceName: "error-20").withRenderingMode(.alwaysTemplate)
        imageView.tintColor = .ows_accentRed
        imageView.autoSetDimensions(to: .square(20))

        let container = UIView()
        container.layoutMargins = UIEdgeInsets(hMargin: 12, vMargin: 0)
        container.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewMargins()

        return container
    }()

    enum CellType: String, CaseIterable {
        case standalone
        case top
        case bottom
        case middle
        case reaction

        var hasFooter: Bool {
            switch self {
            case .standalone, .bottom, .reaction: return true
            case .top, .middle: return false
            }
        }

        var hasAuthor: Bool {
            switch self {
            case .standalone, .top, .reaction: return true
            case .middle, .bottom: return false
            }
        }

        var hasAvatar: Bool {
            switch self {
            case .standalone, .bottom, .reaction: return true
            case .top, .middle: return false
            }
        }

        var hasBubble: Bool {
            switch self {
            case .reaction: return false
            case .standalone, .top, .middle, .bottom: return true
            }
        }

        var hasReaction: Bool {
            switch self {
            case .reaction: return true
            case .standalone, .top, .middle, .bottom: return false
            }
        }

        var insets: UIEdgeInsets {
            switch self {
            case .standalone, .reaction: return UIEdgeInsets(hMargin: 16, vMargin: 6)
            case .top: return UIEdgeInsets(top: 6, leading: 16, bottom: 1, trailing: 16)
            case .middle: return UIEdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16)
            case .bottom: return UIEdgeInsets(top: 1, leading: 16, bottom: 6, trailing: 16)
            }
        }

        var verticalAlignment: UIStackView.Alignment {
            switch self {
            case .reaction: return .center
            case .standalone, .top, .middle, .bottom: return .bottom
            }
        }

        var sharpCorners: UIRectCorner {
            switch self {
            case .standalone, .reaction: return []
            case .top: return CurrentAppContext().isRTL ? .bottomRight : .bottomLeft
            case .middle: return CurrentAppContext().isRTL ? [.bottomRight, .topRight] : [.bottomLeft, .topLeft]
            case .bottom: return CurrentAppContext().isRTL ? .topRight : .topLeft
            }
        }

        var cornerRadius: CGFloat { 18 }
        var sharpCornerRadius: CGFloat { 4 }
    }
    let cellType: CellType

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        if let reuseIdentifier = reuseIdentifier, let cellType = CellType(rawValue: reuseIdentifier) {
            self.cellType = cellType
        } else {
            owsFailDebug("Missing cellType for reuseIdentifer \(String(describing: reuseIdentifier))")
            self.cellType = .standalone
        }

        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        backgroundColor = .clear

        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 2

        let hStack = UIStackView()
        hStack.axis = .horizontal
        hStack.alignment = cellType.verticalAlignment

        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = cellType.insets

        if cellType.hasAvatar {
            avatarView.autoSetDimensions(to: CGSize(square: 28))
            hStack.addArrangedSubview(avatarView)
        } else {
            hStack.addArrangedSubview(.spacer(withWidth: 28))
        }

        hStack.addArrangedSubview(.spacer(withWidth: 8))

        if cellType.hasBubble {
            hStack.addArrangedSubview(bubbleView)
            bubbleView.addSubview(vStack)
            vStack.autoPinEdgesToSuperviewMargins()

            if cellType.sharpCorners.isEmpty {
                bubbleView.layer.cornerRadius = cellType.cornerRadius
                bubbleView.clipsToBounds = true
            } else {
                bubbleView.layer.mask = bubbleCornerMaskLayer
            }
        } else {
            hStack.addArrangedSubview(.spacer(withWidth: 12))
            hStack.addArrangedSubview(vStack)
        }

        hStack.addArrangedSubview(sendFailureIcon)
        sendFailureIcon.isHidden = true

        hStack.addArrangedSubview(.hStretchingSpacer())

        if cellType.hasReaction {
            hStack.addArrangedSubview(reactionLabel)
        }

        if cellType.hasAuthor {
            vStack.addArrangedSubview(authorNameLabel)
        }

        let internalHStack = UIStackView(arrangedSubviews: [messageLabel, sendingSpinner])
        internalHStack.axis = .horizontal
        internalHStack.alignment = .bottom
        internalHStack.spacing = 6

        sendingSpinner.isHidden = true
        sendingSpinner.autoSetDimension(.width, toSize: 12)
        sendingSpinner.tintColor = Theme.darkThemePrimaryColor

        vStack.addArrangedSubview(internalHStack)

        contentView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: StoryGroupReplyViewItem) {
        if cellType.hasAuthor {
            authorNameLabel.textColor = item.authorColor
            authorNameLabel.text = item.authorDisplayName
        }

        if cellType.hasAvatar {
            avatarView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .address(item.authorAddress)
            }
        }

        if cellType.hasReaction {
            reactionLabel.text = item.reactionEmoji
        }

        configureBodyAndFooter(for: item)
    }

    func configureBodyAndFooter(for item: StoryGroupReplyViewItem) {
        guard let messageText: NSAttributedString = {
            if item.wasRemotelyDeleted {
                return NSLocalizedString("THIS_MESSAGE_WAS_DELETED", comment: "text indicating the message was remotely deleted").styled(
                    with: .font(UIFont.ows_dynamicTypeBodyClamped.ows_italic),
                    .color(.ows_gray05)
                )
            } else if cellType == .reaction {
                return NSLocalizedString("STORY_REPLY_REACTION", comment: "Text indicating a story has been reacted to").styled(
                    with: .font(.ows_dynamicTypeBodyClamped),
                    .color(.ows_gray05),
                    .alignment(.natural)
                )
            } else if let displayableText = item.displayableText {
                return displayableText.displayAttributedText.styled(
                    with: .font(.ows_dynamicTypeBodyClamped),
                    .color(.ows_gray05),
                    .alignment(displayableText.displayTextNaturalAlignment)
                )
            } else {
                return nil
            }
        }() else { return }

        guard cellType.hasFooter else {
            messageLabel.attributedText = messageText
            return
        }

        var maxMessageWidth = min(512, CurrentAppContext().frame.width) - 92
        let footerSpacer: CGFloat = 6

        var allowFooterOnLastMessageLine = true
        var renderTimestamp = true
        let footerText = NSMutableAttributedString()

        sendingSpinner.isHidden = true
        sendFailureIcon.isHidden = true

        if let recipientStatus = item.recipientStatus {
            switch recipientStatus {
            case .pending, .uploading, .sending:
                // Make room for the spinner
                maxMessageWidth -= 18
                sendingSpinner.isHidden = false
            case .sent, .skipped, .delivered, .read, .viewed:
                // No indicator
                break
            case .failed:
                allowFooterOnLastMessageLine = false
                renderTimestamp = false
                maxMessageWidth -= 44
                sendFailureIcon.isHidden = false
                footerText.append(NSLocalizedString("STORY_SEND_FAILED", comment: "Text indicating that the story send has failed"))
            }
        }

        // Append timestamp to attributed text
        if renderTimestamp {
            footerText.append(item.timeString)
        }

        // Style footer
        footerText.addAttributesToEntireString([
            .font: UIFont.ows_dynamicTypeCaption1Clamped,
            .foregroundColor: UIColor.ows_gray25
        ])

        // Render footer inline if possible
        let messageMeasurement = measure(messageText, maxWidth: maxMessageWidth)
        let footerMeasurement = measure(footerText, maxWidth: maxMessageWidth)

        let lastLineFreeSpace = maxMessageWidth - footerSpacer - messageMeasurement.lastLineRect.width

        let textDirectionMatchesAppDirection: Bool
        switch item.displayableText?.displayTextNaturalAlignment ?? .natural {
        case .left:
            textDirectionMatchesAppDirection = !CurrentAppContext().isRTL
        case .right:
            textDirectionMatchesAppDirection = CurrentAppContext().isRTL
        case .natural:
            textDirectionMatchesAppDirection = true
        default:
            owsFailDebug("Unexpected text alignment")
            textDirectionMatchesAppDirection = true
        }

        let hasSpacedForFooterOnLastMessageLine = lastLineFreeSpace >= footerMeasurement.rect.width
        let shouldRenderFooterOnLastMessageLine = hasSpacedForFooterOnLastMessageLine && textDirectionMatchesAppDirection && allowFooterOnLastMessageLine

        if shouldRenderFooterOnLastMessageLine {
            var possibleMessageBubbleWidths = [
                messageMeasurement.rect.width,
                messageMeasurement.lastLineRect.width + footerSpacer + footerMeasurement.rect.width
            ]
            if cellType.hasAuthor, let authorDisplayName = item.authorDisplayName {
                let authorMeasurement = measure(authorDisplayName.styled(with: .font(authorNameLabel.font)), maxWidth: maxMessageWidth)
                possibleMessageBubbleWidths.append(authorMeasurement.rect.width)
            }

            let finalMessageLabelWidth = possibleMessageBubbleWidths.max()!

            messageLabel.attributedText = .composed(of: [
                messageText,
                "\n",
                footerText.styled(
                    with: .paragraphSpacingBefore(-footerMeasurement.rect.height),
                    .firstLineHeadIndent(finalMessageLabelWidth - footerMeasurement.rect.width)
                )
            ])
        } else {
            var possibleMessageBubbleWidths = [
                messageMeasurement.rect.width,
                footerMeasurement.rect.width
            ]
            if cellType.hasAuthor, let authorDisplayName = item.authorDisplayName {
                let authorMeasurement = measure(authorDisplayName.styled(with: .font(authorNameLabel.font)), maxWidth: maxMessageWidth)
                possibleMessageBubbleWidths.append(authorMeasurement.rect.width)
            }

            let finalMessageLabelWidth = possibleMessageBubbleWidths.max()!

            messageLabel.attributedText = .composed(of: [
                messageText,
                "\n",
                footerText.styled(
                    with: textDirectionMatchesAppDirection
                    ? .firstLineHeadIndent(finalMessageLabelWidth - footerMeasurement.rect.width)
                    : .alignment(.trailing)
                )
            ])
        }
    }

    private func measure(_ attributedString: NSAttributedString, maxWidth: CGFloat) -> (rect: CGRect, lastLineRect: CGRect) {
        guard !attributedString.isEmpty else { return (.zero, .zero) }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: maxWidth, height: .infinity))
        let textStorage = NSTextStorage()

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(attributedString)

        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        textContainer.maximumNumberOfLines = 0

        let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: attributedString.length - 1)
        let lastLineFragmentRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: lastGlyphIndex,
            effectiveRange: nil
        )

        let fullTextRect = layoutManager.usedRect(for: textContainer)

        return (fullTextRect, lastLineFragmentRect)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard !cellType.sharpCorners.isEmpty else { return }

        bubbleView.layoutIfNeeded()
        bubbleCornerMaskLayer.path = UIBezierPath.roundedRect(
            bubbleView.bounds,
            sharpCorners: cellType.sharpCorners,
            sharpCornerRadius: cellType.sharpCornerRadius,
            wideCornerRadius: cellType.cornerRadius
        ).cgPath
    }
}

private class SendingSpinner: UIImageView {
    init() {
        super.init(image: #imageLiteral(resourceName: "message_status_sending").withRenderingMode(.alwaysTemplate).withAlignmentRectInsets(.init(hMargin: 0, vMargin: -2)))

        startAnimating()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func startAnimating() {
        super.startAnimating()

        guard layer.animation(forKey: "spin") == nil else { return }

        let animation = CABasicAnimation.init(keyPath: "transform.rotation.z")
        animation.toValue = CGFloat.pi * 2
        animation.duration = kSecondInterval * 1
        animation.isCumulative = true
        animation.repeatCount = .infinity
        layer.add(animation, forKey: "spin")
    }

    override func stopAnimating() {
        super.stopAnimating()

        layer.removeAnimation(forKey: "spin")
    }

    override var isHidden: Bool {
        didSet {
            isHidden ? stopAnimating() : startAnimating()
        }
    }
}
