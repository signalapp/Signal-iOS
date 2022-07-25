// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

extension ContextMenuVC {    
    final class EmojiReactsView: UIView {
        private let action: Action
        private let dismiss: () -> Void

        // MARK: - Settings
        
        private static let size: CGFloat = 40
        
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
            let emojiLabel = UILabel()
            emojiLabel.text = self.action.title
            emojiLabel.font = .systemFont(ofSize: Values.veryLargeFontSize)
            emojiLabel.set(.height, to: ContextMenuVC.EmojiReactsView.size)
            addSubview(emojiLabel)
            emojiLabel.pin(to: self)
            
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
    
    final class EmojiPlusButton: UIView {
        private let action: Action?
        private let dismiss: () -> Void

        // MARK: - Settings
        
        public static let size: CGFloat = 28
        private let iconSize: CGFloat = 14
        
        // MARK: - Lifecycle
        
        init(action: Action?, dismiss: @escaping () -> Void) {
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
            // Icon image
            let iconImageView = UIImageView(image: #imageLiteral(resourceName: "ic_plus_24").withRenderingMode(.alwaysTemplate))
            iconImageView.tintColor = Colors.text
            iconImageView.set(.width, to: iconSize)
            iconImageView.set(.height, to: iconSize)
            iconImageView.contentMode = .scaleAspectFit
            addSubview(iconImageView)
            iconImageView.center(in: self)
            
            // Background
            isUserInteractionEnabled = true
            backgroundColor = Colors.sessionEmojiPlusButtonBackground
            
            // Tap gesture recognizer
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tapGestureRecognizer)
        }
        
        // MARK: - Interaction
        
        @objc private func handleTap() {
            dismiss()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: { [weak self] in
                self?.action?.work()
            })
        }
    }
}
