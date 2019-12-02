
final class TextField : UITextField {
    
    init(placeholder: String) {
        super.init(frame: CGRect.zero)
        self.placeholder = placeholder
        setUpStyle()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(placeholder:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(placeholder:) instead.")
    }
    
    private func setUpStyle() {
        textColor = Colors.text
        font = .systemFont(ofSize: Values.smallFontSize)
        let placeholder = NSMutableAttributedString(string: self.placeholder!)
        let placeholderColor = Colors.text.withAlphaComponent(Values.unimportantElementOpacity)
        placeholder.addAttribute(.foregroundColor, value: placeholderColor, range: NSRange(location: 0, length: placeholder.length))
        attributedPlaceholder = placeholder
        tintColor = Colors.accent
        keyboardAppearance = .dark
        set(.height, to: Values.textFieldHeight)
        layer.borderColor = Colors.border.withAlphaComponent(Values.textFieldBorderOpacity).cgColor
        layer.borderWidth = Values.borderThickness
        layer.cornerRadius = Values.textFieldCornerRadius
    }
    
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: Values.largeSpacing, dy: Values.largeSpacing)
    }
    
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.insetBy(dx: Values.largeSpacing, dy: Values.largeSpacing)
    }
}
