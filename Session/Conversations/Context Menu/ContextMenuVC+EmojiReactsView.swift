
extension ContextMenuVC {
    
    final class EmojiReactsView: UIView {
        private let emoji: String
        private let dismiss: () -> Void
        private let work: () -> Void

        // MARK: Settings
        private static let size: CGFloat = 40
        
        // MARK: Lifecycle
        init(for emoji: String, dismiss: @escaping () -> Void, work: @escaping () -> Void) {
            self.emoji = emoji
            self.dismiss = dismiss
            self.work = work
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
            emojiLabel.text = self.emoji
            emojiLabel.font = .systemFont(ofSize: Values.veryLargeFontSize)
            emojiLabel.set(.height, to: ContextMenuVC.EmojiReactsView.size)
            addSubview(emojiLabel)
            emojiLabel.pin(to: self)
            // Tap gesture recognizer
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tapGestureRecognizer)
        }
        
        // MARK: Interaction
        @objc private func handleTap() {
            work()
            dismiss()
        }
    }
    
    final class EmojiPlusButton: UIView {
        private let dismiss: () -> Void
        private let work: () -> Void

        // MARK: Settings
        public static let size: CGFloat = 28
        private let iconSize: CGFloat = 14
        
        // MARK: Lifecycle
        init(dismiss: @escaping () -> Void, work: @escaping () -> Void) {
            self.dismiss = dismiss
            self.work = work
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
        
        // MARK: Interaction
        @objc private func handleTap() {
            dismiss()
            work()
        }
    }
    
}
