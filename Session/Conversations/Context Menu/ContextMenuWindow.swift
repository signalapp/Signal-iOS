
final class ContextMenuWindow : UIWindow {

    override var windowLevel: UIWindow.Level {
        get { return UIWindow.Level(rawValue: CGFloat.greatestFiniteMagnitude - 1) }
        set { /* Do nothing */ }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }

    override init(windowScene: UIWindowScene) {
        super.init(windowScene: windowScene)
        initialize()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        initialize()
    }

    private func initialize() {
        backgroundColor = .clear
    }
}
