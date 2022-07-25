// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionMessagingKit

final class CallMessageView: UIView {
    private static let iconSize: CGFloat = 24
    private static let iconImageViewSize: CGFloat = 40
    
    // MARK: - Lifecycle
    
    init(cellViewModel: MessageViewModel, textColor: UIColor) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(cellViewModel: cellViewModel, textColor: textColor)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:textColor:) instead.")
    }
    
    private func setUpViewHierarchy(cellViewModel: MessageViewModel, textColor: UIColor) {
        // Image view
        let imageView: UIImageView = UIImageView(
            image: UIImage(named: "Phone")?
                .withRenderingMode(.alwaysTemplate)
                .resizedImage(to: CGSize(width: CallMessageView.iconSize, height: CallMessageView.iconSize))
        )
        imageView.tintColor = textColor
        imageView.contentMode = .center
        
        let iconImageViewSize = CallMessageView.iconImageViewSize
        imageView.set(.width, to: iconImageViewSize)
        imageView.set(.height, to: iconImageViewSize)
        
        // Body label
        let titleLabel = UILabel()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = cellViewModel.body
        titleLabel.textColor = textColor
        titleLabel.font = .systemFont(ofSize: Values.mediumFontSize)
        
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 12)
        addSubview(stackView)
        stackView.pin(to: self, withInset: Values.smallSpacing)
    }
}
