// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit
import SessionUtilitiesKit
import SessionUIKit

final class DeletedMessageView: UIView {
    private static let iconSize: CGFloat = 18
    private static let iconImageViewSize: CGFloat = 30
    
    // MARK: - Lifecycle
    
    init(textColor: ThemeValue) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(textColor: textColor)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    private func setUpViewHierarchy(textColor: ThemeValue) {
        // Image view
        let icon = UIImage(named: "ic_trash")?
            .resizedImage(to: CGSize(
                width: DeletedMessageView.iconSize,
                height: DeletedMessageView.iconSize
            ))?
            .withRenderingMode(.alwaysTemplate)
        
        let imageView = UIImageView(image: icon)
        imageView.themeTintColor = textColor
        imageView.contentMode = .center
        imageView.set(.width, to: DeletedMessageView.iconImageViewSize)
        imageView.set(.height, to: DeletedMessageView.iconImageViewSize)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        titleLabel.text = "message_deleted".localized()
        titleLabel.themeTextColor = textColor
        titleLabel.lineBreakMode = .byTruncatingTail
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6)
        addSubview(stackView)
        
        stackView.pin(to: self, withInset: Values.smallSpacing)
        stackView.set(.height, to: .height, of: imageView)
    }
}
