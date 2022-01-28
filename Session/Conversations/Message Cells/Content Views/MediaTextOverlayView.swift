import UIKit

/// Shown over a media message if it has a message body.
final class MediaTextOverlayView : UIView {
    private let viewItem: ConversationViewItem
    private let albumViewWidth: CGFloat
    private let delegate: MessageCellDelegate
    private let textColor: UIColor
    var readMoreButton: UIButton?
    
    // MARK: Settings
    private static let maxHeight: CGFloat = 88;
    
    // MARK: Lifecycle
    init(viewItem: ConversationViewItem, albumViewWidth: CGFloat, textColor: UIColor, delegate: MessageCellDelegate) {
        self.viewItem = viewItem
        self.albumViewWidth = albumViewWidth
        self.delegate = delegate
        self.textColor = textColor
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(text:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(text:) instead.")
    }
    
    private func setUpViewHierarchy() {
        guard let message = viewItem.interaction as? TSMessage, let body = message.body, body.count > 0 else { return }
        // Body label
        let bodyLabel = UILabel()
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.text = given(body) { MentionUtilities.highlightMentions(in: $0, threadID: viewItem.interaction.uniqueThreadId) }
        bodyLabel.textColor = self.textColor
        bodyLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        // Content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ bodyLabel ])
        contentStackView.axis = .horizontal
        contentStackView.spacing = Values.smallSpacing
        addSubview(contentStackView)
        let inset: CGFloat = 12
        contentStackView.pin(.left, to: .left, of: self, withInset: inset)
        contentStackView.pin(.top, to: .top, of: self)
        contentStackView.pin(.right, to: .right, of: self, withInset: -inset)
        // Max height
        bodyLabel.heightAnchor.constraint(lessThanOrEqualToConstant: MediaTextOverlayView.maxHeight).isActive = true
        // Overflow button
        let bodyLabelTargetSize = bodyLabel.sizeThatFits(CGSize(width: albumViewWidth - 2 * inset, height: .greatestFiniteMagnitude))
        if bodyLabelTargetSize.height > MediaTextOverlayView.maxHeight {
            let readMoreButton = UIButton()
            self.readMoreButton = readMoreButton
            readMoreButton.setTitle("Read More", for: UIControl.State.normal)
            readMoreButton.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
            readMoreButton.setTitleColor(self.textColor, for: UIControl.State.normal)
            readMoreButton.addTarget(self, action: #selector(readMore), for: UIControl.Event.touchUpInside)
            addSubview(readMoreButton)
            readMoreButton.pin(.left, to: .left, of: self, withInset: inset)
            readMoreButton.pin(.top, to: .bottom, of: contentStackView, withInset: Values.smallSpacing)
            readMoreButton.pin(.bottom, to: .bottom, of: self, withInset: -Values.smallSpacing)
        } else {
            contentStackView.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        }
    }
    
    // MARK: Interaction
    @objc private func readMore() {
        delegate.showFullText(viewItem)
    }
}
