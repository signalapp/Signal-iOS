import UIKit

public final class Button : UIButton {
    private let style: Style
    private let size: Size
    private var heightConstraint: NSLayoutConstraint!
    
    public enum Style {
        case unimportant, regular, prominentOutline, prominentFilled, regularBorderless, destructiveOutline
    }
    
    public enum Size {
        case medium, large, small
    }
    
    public init(style: Style, size: Size) {
        self.style = style
        self.size = size
        super.init(frame: .zero)
        setUpStyle()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppModeChangedNotification(_:)), name: .appModeChanged, object: nil)
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(style:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(style:) instead.")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setUpStyle() {
        let fillColor: UIColor
        switch style {
        case .unimportant: fillColor = isLightMode ? UIColor.clear : Colors.unimportantButtonBackground
        case .regular: fillColor = UIColor.clear
        case .prominentOutline: fillColor = UIColor.clear
        case .prominentFilled: fillColor = isLightMode ? Colors.text : Colors.accent
        case .regularBorderless: fillColor = UIColor.clear
        case .destructiveOutline: fillColor = UIColor.clear
        }
        let borderColor: UIColor
        switch style {
        case .unimportant: borderColor = isLightMode ? Colors.text : Colors.unimportantButtonBackground
        case .regular: borderColor = Colors.text
        case .prominentOutline: borderColor = isLightMode ? Colors.text : Colors.accent
        case .prominentFilled: borderColor = isLightMode ? Colors.text : Colors.accent
        case .regularBorderless: borderColor = UIColor.clear
        case .destructiveOutline: borderColor = Colors.destructive
        }
        let textColor: UIColor
        switch style {
        case .unimportant: textColor = Colors.text
        case .regular: textColor = Colors.text
        case .prominentOutline: textColor = isLightMode ? Colors.text : Colors.accent
        case .prominentFilled: textColor = isLightMode ? UIColor.white : Colors.text
        case .regularBorderless: textColor = Colors.text
        case .destructiveOutline: textColor = Colors.destructive
        }
        let height: CGFloat
        switch size {
        case .small: height = Values.smallButtonHeight
        case .medium: height = Values.mediumButtonHeight
        case .large: height = Values.largeButtonHeight
        }
        if heightConstraint == nil { heightConstraint = set(.height, to: height) }
        layer.cornerRadius = height / 2
        backgroundColor = fillColor
        layer.borderColor = borderColor.cgColor
        layer.borderWidth = 1
        let fontSize = (size == .small) ? Values.smallFontSize : Values.mediumFontSize
        titleLabel!.font = .boldSystemFont(ofSize: fontSize)
        setTitleColor(textColor, for: UIControl.State.normal)
    }

    @objc private func handleAppModeChangedNotification(_ notification: Notification) {
        setUpStyle()
    }
}
