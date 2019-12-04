
final class Button : UIButton {
    private let style: Style
    
    enum Style {
        case unimportant, regular, prominent
    }
    
    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        setUpStyle()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    private func setUpStyle() {
        let fillColor: UIColor
        switch style {
        case .unimportant: fillColor = Colors.unimportantButtonBackground
        case .regular: fillColor = UIColor.clear
        case .prominent: fillColor = UIColor.clear
        }
        let borderColor: UIColor
        switch style {
        case .unimportant: borderColor = Colors.unimportantButtonBackground
        case .regular: borderColor = Colors.text
        case .prominent: borderColor = Colors.accent
        }
        let textColor: UIColor
        switch style {
        case .unimportant: textColor = Colors.text
        case .regular: textColor = Colors.text
        case .prominent: textColor = Colors.accent
        }
        let height = Values.buttonHeight
        set(.height, to: height)
        layer.cornerRadius = height / 2
        backgroundColor = fillColor
        layer.borderColor = borderColor.cgColor
        layer.borderWidth = Values.borderThickness
        titleLabel!.font = Fonts.spaceMono(ofSize: Values.mediumFontSize)
        setTitleColor(textColor, for: UIControl.State.normal)
    }
}
