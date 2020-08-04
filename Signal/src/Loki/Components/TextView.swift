import UITextView_Placeholder

final class TextView : UITextView {
    private let usesDefaultHeight: Bool
    private let height: CGFloat
    private let horizontalInset: CGFloat
    private let verticalInset: CGFloat

    override var contentSize: CGSize { didSet { centerTextVertically() } }

    init(placeholder: String, usesDefaultHeight: Bool = true, customHeight: CGFloat? = nil, customHorizontalInset: CGFloat? = nil, customVerticalInset: CGFloat? = nil) {
        self.usesDefaultHeight = usesDefaultHeight
        self.height = customHeight ?? Values.textFieldHeight
        self.horizontalInset = customHorizontalInset ?? (isIPhone5OrSmaller ? Values.mediumSpacing : Values.largeSpacing)
        self.verticalInset = customVerticalInset ?? (isIPhone5OrSmaller ? Values.smallSpacing : Values.largeSpacing)
        super.init(frame: CGRect.zero, textContainer: nil)
        self.placeholder = placeholder
        setUpStyle()
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        preconditionFailure("Use init(placeholder:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(placeholder:) instead.")
    }

    private func setUpStyle() {
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        let placeholder = NSMutableAttributedString(string: self.placeholder!)
        self.placeholder = nil
        let placeholderColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        placeholder.addAttribute(.foregroundColor, value: placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        placeholder.addAttribute(.font, value: UIFont.systemFont(ofSize: Values.smallFontSize), range: NSRange(location: 0, length: placeholder.length))
        attributedPlaceholder = placeholder
        backgroundColor = .clear
        textColor = Colors.text
        font = .systemFont(ofSize: Values.smallFontSize)
        tintColor = Colors.accent
        keyboardAppearance = isLightMode ? .light : .dark
        if usesDefaultHeight {
            set(.height, to: height)
        }
        layer.borderColor = isLightMode ? Colors.text.cgColor : Colors.border.withAlphaComponent(Values.textFieldBorderOpacity).cgColor
        layer.borderWidth = Values.borderThickness
        layer.cornerRadius = Values.textFieldCornerRadius
        let horizontalInset = usesDefaultHeight ? self.horizontalInset : Values.mediumSpacing
        textContainerInset = UIEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
    }

    private func centerTextVertically() {
        let topInset = max(0, (bounds.size.height - contentSize.height * zoomScale) / 2)
        contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
    }
}
