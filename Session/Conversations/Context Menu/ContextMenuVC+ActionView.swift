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
        private var didTouchDownInside: Bool = false
        
        // MARK: - UI
        
        private let iconImageView: UIImageView = {
            let result: UIImageView = UIImageView()
            result.contentMode = .center
            result.themeTintColor = .textPrimary
            result.set(.width, to: ActionView.iconImageViewSize)
            result.set(.height, to: ActionView.iconImageViewSize)
            
            return result
        }()
        
        private let titleLabel: UILabel = {
            let result: UILabel = UILabel()
            result.font = .systemFont(ofSize: Values.mediumFontSize)
            result.themeTextColor = .textPrimary
            
            return result
        }()

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
            themeBackgroundColor = .clear
            
            iconImageView.image = action.icon?
                .resizedImage(to: CGSize(width: ActionView.iconSize, height: ActionView.iconSize))?
                .withRenderingMode(.alwaysTemplate)
            titleLabel.text = action.title
            
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
        
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard
                isUserInteractionEnabled,
                let location: CGPoint = touches.first?.location(in: self),
                bounds.contains(location)
            else { return }
            
            didTouchDownInside = true
            themeBackgroundColor = .contextMenu_highlight
            iconImageView.themeTintColor = .contextMenu_textHighlight
            titleLabel.themeTextColor = .contextMenu_textHighlight
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard
                isUserInteractionEnabled,
                let location: CGPoint = touches.first?.location(in: self),
                bounds.contains(location),
                didTouchDownInside
            else {
                if didTouchDownInside {
                    themeBackgroundColor = .clear
                    iconImageView.themeTintColor = .textPrimary
                    titleLabel.themeTextColor = .textPrimary
                }
                return
            }
            
            themeBackgroundColor = .contextMenu_highlight
            iconImageView.themeTintColor = .contextMenu_textHighlight
            titleLabel.themeTextColor = .contextMenu_textHighlight
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            if didTouchDownInside {
                themeBackgroundColor = .clear
                iconImageView.themeTintColor = .textPrimary
                titleLabel.themeTextColor = .textPrimary
            }
            
            didTouchDownInside = false
        }
        
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            if didTouchDownInside {
                themeBackgroundColor = .clear
                iconImageView.themeTintColor = .textPrimary
                titleLabel.themeTextColor = .textPrimary
            }
            
            didTouchDownInside = false
        }
    }
}
