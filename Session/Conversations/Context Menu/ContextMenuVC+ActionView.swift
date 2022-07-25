// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

extension ContextMenuVC {
    final class ActionView: UIView {
        private static let iconSize: CGFloat = 16
        private static let iconImageViewSize: CGFloat = 24
        
        private let action: Action
        private let dismiss: () -> Void

        // MARK: - Lifecycle
        
        init(for action: Action, dismiss: @escaping () -> Void) {
            self.action = action
            self.dismiss = dismiss
            
            super.init(frame: CGRect.zero)
            
            setUpViewHierarchy()
        }

        override init(frame: CGRect) {
            preconditionFailure("Use init(for:) instead.")
        }

        required init?(coder: NSCoder) {
            preconditionFailure("Use init(for:) instead.")
        }

        private func setUpViewHierarchy() {
            // Icon
            let iconSize = ActionView.iconSize
            let iconImageView: UIImageView = UIImageView(
                image: action.icon?
                    .resizedImage(to: CGSize(width: iconSize, height: iconSize))?
                    .withRenderingMode(.alwaysTemplate)
            )
            iconImageView.set(.width, to: ActionView.iconImageViewSize)
            iconImageView.set(.height, to: ActionView.iconImageViewSize)
            iconImageView.contentMode = .center
            iconImageView.tintColor = Colors.text
            
            // Title
            let titleLabel = UILabel()
            titleLabel.text = action.title
            titleLabel.textColor = Colors.text
            titleLabel.font = .systemFont(ofSize: Values.mediumFontSize)
            
            // Stack view
            let stackView: UIStackView = UIStackView(arrangedSubviews: [ iconImageView, titleLabel ])
            stackView.axis = .horizontal
            stackView.spacing = Values.smallSpacing
            stackView.alignment = .center
            stackView.isLayoutMarginsRelativeArrangement = true
            
            let smallSpacing = Values.smallSpacing
            stackView.layoutMargins = UIEdgeInsets(
                top: smallSpacing,
                leading: smallSpacing,
                bottom: smallSpacing,
                trailing: Values.mediumSpacing
            )
            addSubview(stackView)
            stackView.pin(to: self)
            
            // Tap gesture recognizer
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tapGestureRecognizer)
        }
        
        // MARK: - Interaction
        
        @objc private func handleTap() {
            action.work()
            dismiss()
        }
    }
}
