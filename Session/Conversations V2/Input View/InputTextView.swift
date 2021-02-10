
public final class InputTextView : UITextView, UITextViewDelegate {
    private let snDelegate: InputTextViewDelegate
    private lazy var heightConstraint = self.set(.height, to: minHeight)
    
    // MARK: UI Components
    private lazy var placeholderLabel: UILabel = {
        let result = UILabel()
        result.text = "Message"
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        return result
    }()
    
    // MARK: Settings
    private let minHeight: CGFloat = 22
    private let maxHeight: CGFloat = 80

    // MARK: Lifecycle
    init(delegate: InputTextViewDelegate) {
        snDelegate = delegate
        super.init(frame: CGRect.zero, textContainer: nil)
        setUpViewHierarchy()
        self.delegate = self
    }
    
    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }

    private func setUpViewHierarchy() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        backgroundColor = .clear
        textColor = Colors.text
        font = .systemFont(ofSize: Values.mediumFontSize)
        tintColor = Colors.accent
        keyboardAppearance = isLightMode ? .light : .dark
        heightConstraint.isActive = true
        let horizontalInset: CGFloat = 2
        textContainerInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        addSubview(placeholderLabel)
        placeholderLabel.pin(.leading, to: .leading, of: self, withInset: horizontalInset + 3) // Slight visual adjustment
        placeholderLabel.pin(.top, to: .top, of: self)
        pin(.trailing, to: .trailing, of: placeholderLabel, withInset: horizontalInset)
        pin(.bottom, to: .bottom, of: placeholderLabel)
    }

    // MARK: Updating
    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !text.isEmpty
        let width = frame.width
        let height = frame.height
        let size = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // `textView.contentSize` isn't accurate when restoring a multiline draft, so we set it here manually
        self.contentSize = size
        let newHeight = size.height.clamp(minHeight, maxHeight)
        guard newHeight != height else { return }
        heightConstraint.constant = newHeight
        snDelegate.inputTextViewDidChangeSize(self)
    }
}

// MARK: Delegate
protocol InputTextViewDelegate {
    
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView)
}
