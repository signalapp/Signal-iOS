// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

final class ConversationTitleView: UIView {
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
        
        let stackView: UIStackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        addSubview(stackView)
        
        stackView.pin(to: self)
        
        let shouldShowCallButton = SessionCall.isEnabled && !thread.isNoteToSelf() && !thread.isGroupThread()
        let leftMargin: CGFloat = shouldShowCallButton ? 54 : 8 // Contact threads also have the call button to compensate for
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: leftMargin, bottom: 0, right: 0)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGestureRecognizer)
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(update), name: Notification.Name.groupThreadUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(update), name: Notification.Name.muteSettingUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(update), name: Notification.Name.contactUpdated, object: nil)
        update()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init() instead.")
    }

    // MARK: - Content
    
    public func update(
        with name: String,
        mutedUntilTimestamp: TimeInterval?,
        onlyNotifyForMentions: Bool,
        userCount: Int?
    ) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.update(with: name, mutedUntilTimestamp: mutedUntilTimestamp, onlyNotifyForMentions: onlyNotifyForMentions, userCount: userCount)
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
    }
}
