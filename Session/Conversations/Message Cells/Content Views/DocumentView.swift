// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class DocumentView: UIView {
    private static let iconImageViewSize: CGSize = CGSize(width: 31, height: 40)
    
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
        // Image view
        let imageView = UIImageView(image: UIImage(named: "File")?.withRenderingMode(.alwaysTemplate))
        imageView.themeTintColor = textColor
        imageView.contentMode = .center
        
        let iconImageViewSize = DocumentView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize.width)
        imageView.set(.height, to: iconImageViewSize.height)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize, weight: .light)
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
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, labelStackView ])
        stackView.axis = .horizontal
        stackView.spacing = Values.verySmallSpacing
        stackView.alignment = .center
        addSubview(stackView)
        stackView.pin(to: self)
    }
}
