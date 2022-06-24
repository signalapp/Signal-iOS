// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit
import SessionUtilitiesKit

final class DeletedMessageView: UIView {
    private static let iconSize: CGFloat = 18
    private static let iconImageViewSize: CGFloat = 30
    
    // MARK: - Lifecycle
    
    init(textColor: UIColor) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(textColor: textColor)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(textColor:) instead.")
    }
    
    private func setUpViewHierarchy(textColor: UIColor) {
        // Image view
        let icon = UIImage(named: "ic_trash")?
            .withRenderingMode(.alwaysTemplate)
            .resizedImage(to: CGSize(
                width: DeletedMessageView.iconSize,
                height: DeletedMessageView.iconSize
            ))
        
        let imageView = UIImageView(image: icon)
        imageView.tintColor = textColor
        imageView.contentMode = .center
        imageView.set(.width, to: DeletedMessageView.iconImageViewSize)
        imageView.set(.height, to: DeletedMessageView.iconImageViewSize)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = "message_deleted".localized()
        titleLabel.textColor = textColor
        titleLabel.font = .systemFont(ofSize: Values.smallFontSize)
        
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
