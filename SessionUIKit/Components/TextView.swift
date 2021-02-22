import UIKit

public final class TextView : UITextView, UITextViewDelegate {
    private let usesDefaultHeight: Bool
    private let height: CGFloat
    private let horizontalInset: CGFloat
    private let verticalInset: CGFloat
    private let placeholder: String

    public override var contentSize: CGSize { didSet { centerTextVertically() } }

    private lazy var placeholderLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        return result
    }()

    public init(placeholder: String, usesDefaultHeight: Bool = true, customHeight: CGFloat? = nil, customHorizontalInset: CGFloat? = nil, customVerticalInset: CGFloat? = nil) {
        self.usesDefaultHeight = usesDefaultHeight
        self.height = customHeight ?? TextField.height
        self.horizontalInset = customHorizontalInset ?? (isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing)
        self.verticalInset = customVerticalInset ?? (isIPhone5OrSmaller ? Values.smallSpacing : Values.largeSpacing)
        self.placeholder = placeholder
        super.init(frame: CGRect.zero, textContainer: nil)
        self.delegate = self
        setUpStyle()
    }

    public override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(placeholder:) instead.")
    }

    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(placeholder:) instead.")
    }

    private func setUpStyle() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        placeholderLabel.text = placeholder
        backgroundColor = .clear
        textColor = Colors.text
        font = .systemFont(ofSize: Values.smallFontSize)
        tintColor = Colors.accent
        keyboardAppearance = isLightMode ? .light : .dark
        if usesDefaultHeight {
            set(.height, to: height)
        }
        layer.borderColor = isLightMode ? Colors.text.cgColor : Colors.border.withAlphaComponent(Values.lowOpacity).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = TextField.cornerRadius
        let horizontalInset = usesDefaultHeight ? self.horizontalInset : Values.mediumSpacing
        textContainerInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: 0, right: horizontalInset)
        addSubview(placeholderLabel)
        placeholderLabel.pin(.leading, to: .leading, of: self, withInset: horizontalInset + 3) // Slight visual adjustment
        placeholderLabel.pin(.top, to: .top, of: self)
        pin(.trailing, to: .trailing, of: placeholderLabel, withInset: horizontalInset)
        pin(.bottom, to: .bottom, of: placeholderLabel)
    }

    public func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func centerTextVertically() {
        let topInset = max(0, (bounds.size.height - contentSize.height * zoomScale) / 2)
        contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
    }
}
