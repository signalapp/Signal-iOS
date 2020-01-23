
public extension UIView {
    
    public enum HorizontalEdge { case left, leading, right, trailing }
    public enum VerticalEdge { case top, bottom }
    public enum Direction { case horizontal, vertical }
    public enum Dimension { case width, height }
    
    private func anchor(from edge: HorizontalEdge) -> NSLayoutXAxisAnchor {
        switch edge {
        case .left: return leftAnchor
        case .leading: return leadingAnchor
        case .right: return rightAnchor
        case .trailing: return trailingAnchor
        }
    }
    
    private func anchor(from edge: VerticalEdge) -> NSLayoutYAxisAnchor {
        switch edge {
        case .top: return topAnchor
        case .bottom: return bottomAnchor
        }
    }
    
    @discardableResult
    public func pin(_ constraineeEdge: HorizontalEdge, to constrainerEdge: HorizontalEdge, of view: UIView, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset)
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    public func pin(_ constraineeEdge: VerticalEdge, to constrainerEdge: VerticalEdge, of view: UIView, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset)
        constraint.isActive = true
        return constraint
    }
    
    public func pin(to view: UIView) {
        [ HorizontalEdge.leading, HorizontalEdge.trailing ].forEach { pin($0, to: $0, of: view) }
        [ VerticalEdge.top, VerticalEdge.bottom ].forEach { pin($0, to: $0, of: view) }
    }
    
    public func pin(to view: UIView, withInset inset: CGFloat) {
        pin(.leading, to: .leading, of: view, withInset: inset)
        pin(.top, to: .top, of: view, withInset: inset)
        view.pin(.trailing, to: .trailing, of: self, withInset: inset)
        view.pin(.bottom, to: .bottom, of: self, withInset: inset)
    }
    
    @discardableResult
    public func center(_ direction: Direction, in view: UIView) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint: NSLayoutConstraint = {
            switch direction {
            case .horizontal: return centerXAnchor.constraint(equalTo: view.centerXAnchor)
            case .vertical: return centerYAnchor.constraint(equalTo: view.centerYAnchor)
            }
        }()
        constraint.isActive = true
        return constraint
    }
    
    public func center(in view: UIView) {
        center(.horizontal, in: view)
        center(.vertical, in: view)
    }
    
    @discardableResult
    public func set(_ dimension: Dimension, to size: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint: NSLayoutConstraint = {
            switch dimension {
            case .width: return widthAnchor.constraint(equalToConstant: size)
            case .height: return heightAnchor.constraint(equalToConstant: size)
            }
        }()
        constraint.isActive = true
        return constraint
    }
}
