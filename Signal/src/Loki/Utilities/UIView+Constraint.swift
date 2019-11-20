
extension UIView {
    
    enum HorizontalEdge { case left, leading, right, trailing }
    enum VerticalEdge { case top, bottom }
    enum Direction { case horizontal, vertical }
    enum Dimension { case width, height }
    
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
    
    func pin(_ constraineeEdge: HorizontalEdge, to constrainerEdge: HorizontalEdge, of view: UIView, withInset inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset).isActive = true
    }
    
    func pin(_ constraineeEdge: VerticalEdge, to constrainerEdge: VerticalEdge, of view: UIView, withInset inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset).isActive = true
    }
    
    func pin(to view: UIView) {
        [ HorizontalEdge.leading, HorizontalEdge.trailing ].forEach { pin($0, to: $0, of: view) }
        [ VerticalEdge.top, VerticalEdge.bottom ].forEach { pin($0, to: $0, of: view) }
    }
    
    func center(_ direction: Direction, in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        switch direction {
        case .horizontal: centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        case .vertical: centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        }
    }
    
    func center(in view: UIView) {
        center(.horizontal, in: view)
        center(.vertical, in: view)
    }
    
    func set(_ dimension: Dimension, to size: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        switch dimension {
        case .width: widthAnchor.constraint(equalToConstant: size).isActive = true
        case .height: heightAnchor.constraint(equalToConstant: size).isActive = true
        }
    }
}
