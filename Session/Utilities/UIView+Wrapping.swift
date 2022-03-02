
extension UIView {

    convenience init(wrapping view: UIView, withInsets insets: UIEdgeInsets, shouldAdaptForIPad: Bool = false) {
        self.init()
        addSubview(view)
        if UIDevice.current.isIPad && shouldAdaptForIPad {
            view.set(.width, to: Values.iPadButtonWidth)
            view.center(in: self)
        } else {
            view.pin(.leading, to: .leading, of: self, withInset: insets.left)
            self.pin(.trailing, to: .trailing, of: view, withInset: insets.right)
        }
        view.pin(.top, to: .top, of: self, withInset: insets.top)
        self.pin(.bottom, to: .bottom, of: view, withInset: insets.bottom)
    }
}
