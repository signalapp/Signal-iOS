// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class ConversationTitleView: UIView {
    private static let leftInset: CGFloat = 8
    private static let leftInsetWithCallButton: CGFloat = 54
    
    override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }

    // MARK: - UI Components
    
    private lazy var titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()

    private lazy var subtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: 13)
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()
    
    private lazy var stackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        result.axis = .vertical
        result.alignment = .center
        result.isLayoutMarginsRelativeArrangement = true
        
        return result
    }()

    // MARK: - Initialization
    
    init() {
        super.init(frame: .zero)
        
        addSubview(stackView)
        
        stackView.pin(to: self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init() instead.")
    }

    // MARK: - Content
    
    public func initialSetup(with threadVariant: SessionThread.Variant) {
        self.update(
            with: " ",
            isNoteToSelf: false,
            threadVariant: threadVariant,
            mutedUntilTimestamp: nil,
            onlyNotifyForMentions: false,
            userCount: (threadVariant != .contact ? 0 : nil)
        )
    }
    
    public func update(
        with name: String,
        isNoteToSelf: Bool,
        threadVariant: SessionThread.Variant,
        mutedUntilTimestamp: TimeInterval?,
        onlyNotifyForMentions: Bool,
        userCount: Int?
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.update(
                    with: name,
                    isNoteToSelf: isNoteToSelf,
                    threadVariant: threadVariant,
                    mutedUntilTimestamp: mutedUntilTimestamp,
                    onlyNotifyForMentions: onlyNotifyForMentions,
                    userCount: userCount
                )
            }
            return
        }
        
        // Generate the subtitle
        let subtitle: NSAttributedString? = {
            guard Date().timeIntervalSince1970 > (mutedUntilTimestamp ?? 0) else {
                return NSAttributedString(
                    string: "\u{e067}  ",
                    attributes: [
                        .font: UIFont.ows_elegantIconsFont(10),
                        .foregroundColor: Colors.text
                    ]
                )
                .appending(string: "Muted")
            }
            guard !onlyNotifyForMentions else {
                // FIXME: This is going to have issues when swapping between light/dark mode
                let imageAttachment = NSTextAttachment()
                let color: UIColor = (isDarkMode ? .white : .black)
                imageAttachment.image = UIImage(named: "NotifyMentions.png")?.asTintedImage(color: color)
                imageAttachment.bounds = CGRect(
                    x: 0,
                    y: -2,
                    width: Values.smallFontSize,
                    height: Values.smallFontSize
                )
                
                return NSAttributedString(attachment: imageAttachment)
                    .appending(string: "  ")
                    .appending(string: "view_conversation_title_notify_for_mentions_only".localized())
            }
            guard let userCount: Int = userCount else { return nil }
            
            return NSAttributedString(string: "\(userCount) member\(userCount == 1 ? "" : "s")")
        }()
        
        self.titleLabel.text = name
        self.titleLabel.font = .boldSystemFont(
            ofSize: (subtitle != nil ?
                Values.mediumFontSize :
                Values.veryLargeFontSize
            )
        )
        self.subtitleLabel.attributedText = subtitle
        
        // Contact threads also have the call button to compensate for
        let shouldShowCallButton: Bool = (
            SessionCall.isEnabled &&
            !isNoteToSelf &&
            threadVariant == .contact
        )
        self.stackView.layoutMargins = UIEdgeInsets(
            top: 0,
            left: (shouldShowCallButton ?
                ConversationTitleView.leftInsetWithCallButton :
                ConversationTitleView.leftInset
            ),
            bottom: 0,
            right: 0
        )
    }
}
