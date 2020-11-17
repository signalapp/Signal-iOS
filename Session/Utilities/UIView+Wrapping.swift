
extension UIView {

    convenience init(wrapping view: UIView, withInsets insets: UIEdgeInsets) {
        self.init()
        addSubview(view)
        view.pin(.leading, to: .leading, of: self, withInset: insets.left)
        view.pin(.top, to: .top, of: self, withInset: insets.top)
        self.pin(.trailing, to: .trailing, of: view, withInset: insets.right)
        self.pin(.bottom, to: .bottom, of: view, withInset: insets.bottom)
    }
}
