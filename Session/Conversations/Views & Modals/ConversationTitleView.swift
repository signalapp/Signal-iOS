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
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()

    private lazy var subtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: 13)
        result.themeTextColor = .textPrimary
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
        
        let shouldHaveSubtitle: Bool = (
            Date().timeIntervalSince1970 <= (mutedUntilTimestamp ?? 0) ||
            onlyNotifyForMentions ||
            userCount != nil
        )
        
        self.titleLabel.text = name
        self.titleLabel.font = .boldSystemFont(
            ofSize: (shouldHaveSubtitle ?
                Values.mediumFontSize :
                Values.veryLargeFontSize
            )
        )
        
        ThemeManager.onThemeChange(observer: self.subtitleLabel) { [weak subtitleLabel] theme, _ in
            guard let textPrimary: UIColor = theme.color(for: .textPrimary) else { return }
            //subtitleLabel?.attributedText = subtitle
            guard Date().timeIntervalSince1970 > (mutedUntilTimestamp ?? 0) else {
                subtitleLabel?.attributedText = NSAttributedString(
                    string: "\u{e067}  ",
                    attributes: [
                        .font: UIFont.ows_elegantIconsFont(10),
                        .foregroundColor: textPrimary
                    ]
                )
                .appending(string: "Muted")
                return
            }
            guard !onlyNotifyForMentions else {
                let imageAttachment = NSTextAttachment()
                imageAttachment.image = UIImage(named: "NotifyMentions.png")?.withTint(textPrimary)
                imageAttachment.bounds = CGRect(
                    x: 0,
                    y: -2,
                    width: Values.smallFontSize,
                    height: Values.smallFontSize
                )
                
                subtitleLabel?.attributedText = NSAttributedString(attachment: imageAttachment)
                    .appending(string: "  ")
                    .appending(string: "view_conversation_title_notify_for_mentions_only".localized())
                return
            }
            guard let userCount: Int = userCount else { return }
            
            subtitleLabel?.attributedText = NSAttributedString(
                string: "\(userCount) member\(userCount == 1 ? "" : "s")"
            )
        }
        
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
