// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class DocumentView: UIView {
    // MARK: - Lifecycle
    
    init(attachment: Attachment, textColor: ThemeValue) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(attachment: attachment, textColor: textColor)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    private func setUpViewHierarchy(attachment: Attachment, textColor: ThemeValue) {
        let imageBackgroundView: UIView = UIView()
        imageBackgroundView.themeBackgroundColor = .messageBubble_overlay
        addSubview(imageBackgroundView)
        
        // Image view
        let imageView = UIImageView(
            image: UIImage(systemName: "doc")?
                .withRenderingMode(.alwaysTemplate)
        )
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.themeTintColor = textColor
        imageView.set(.height, to: 22)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = (attachment.sourceFilename ?? "File")
        titleLabel.themeTextColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        
        // Size label
        let sizeLabel = UILabel()
        sizeLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        sizeLabel.text = OWSFormat.formatFileSize(UInt(attachment.byteCount))
        sizeLabel.themeTextColor = textColor
        sizeLabel.lineBreakMode = .byTruncatingTail
        
        // Label stack view
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, sizeLabel ])
        labelStackView.axis = .vertical
        
        // Download image view
        let downloadImageView = UIImageView(
            image: UIImage(systemName: "arrow.down")?
                .withRenderingMode(.alwaysTemplate)
        )
        downloadImageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        downloadImageView.setContentHuggingPriority(.required, for: .horizontal)
        downloadImageView.themeTintColor = textColor
        downloadImageView.set(.height, to: 16)
        
        // Stack view
        let stackView = UIStackView(
            arrangedSubviews: [
                imageView,
                UIView.spacer(withWidth: 0),
                labelStackView,
                downloadImageView
            ]
        )
        stackView.axis = .horizontal
        stackView.spacing = Values.mediumSpacing
        stackView.alignment = .center
        addSubview(stackView)
        stackView.pin(.top, to: .top, of: self, withInset: Values.smallSpacing)
        stackView.pin(.leading, to: .leading, of: self, withInset: Values.mediumSpacing)
        stackView.pin(.trailing, to: .trailing, of: self, withInset: -Values.mediumSpacing)
        stackView.pin(.bottom, to: .bottom, of: self, withInset: -Values.smallSpacing)
        
        imageBackgroundView.pin(.top, to: .top, of: self)
        imageBackgroundView.pin(.leading, to: .leading, of: self)
        imageBackgroundView.pin(.trailing, to: .trailing, of: imageView, withInset: Values.mediumSpacing)
        imageBackgroundView.pin(.bottom, to: .bottom, of: self)
    }
}
