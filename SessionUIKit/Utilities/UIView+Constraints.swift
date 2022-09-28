import UIKit

public protocol ConstraintUtilitiesEdge { }

public extension UIView {
    
    enum HorizontalEdge : ConstraintUtilitiesEdge { case left, leading, right, trailing }
    enum VerticalEdge : ConstraintUtilitiesEdge { case top, bottom }
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
    
    @discardableResult
    func pin(_ constraineeEdge: HorizontalEdge, to constrainerEdge: HorizontalEdge, of view: UIView, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset)
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    func pin(_ constraineeEdge: VerticalEdge, to constrainerEdge: VerticalEdge, of view: UIView, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = anchor(from: constraineeEdge).constraint(equalTo: view.anchor(from: constrainerEdge), constant: inset)
        constraint.isActive = true
        return constraint
    }
    
    func pin(_ edges: [ConstraintUtilitiesEdge], to view: UIView) {
        edges.forEach {
            if let horizontalEdge = $0 as? HorizontalEdge {
                pin(horizontalEdge, to: horizontalEdge, of: view)
            } else if let verticalEdge = $0 as? VerticalEdge {
                pin(verticalEdge, to: verticalEdge, of: view)
            } else {
                preconditionFailure() // Should never occur
            }
        }
    }
    
    func pin(to view: UIView) {
        [ HorizontalEdge.leading, HorizontalEdge.trailing ].forEach { pin($0, to: $0, of: view) }
        [ VerticalEdge.top, VerticalEdge.bottom ].forEach { pin($0, to: $0, of: view) }
    }
    
    func pin(to view: UIView, withInset inset: CGFloat) {
        pin(.leading, to: .leading, of: view, withInset: inset)
        pin(.top, to: .top, of: view, withInset: inset)
        view.pin(.trailing, to: .trailing, of: self, withInset: inset)
        view.pin(.bottom, to: .bottom, of: self, withInset: inset)
    }
    
    @discardableResult
    func center(_ direction: Direction, in view: UIView) -> NSLayoutConstraint {
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
    
    func center(in view: UIView) {
        center(.horizontal, in: view)
        center(.vertical, in: view)
    }
    
    @discardableResult
    func set(_ dimension: Dimension, to size: CGFloat) -> NSLayoutConstraint {
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
    
    @discardableResult
    func set(_ dimension: Dimension, to otherDimension: Dimension, of view: UIView, withOffset offset: CGFloat = 0, multiplier: CGFloat = 1) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let otherAnchor: NSLayoutDimension = {
            switch otherDimension {
                case .width: return view.widthAnchor
                case .height: return view.heightAnchor
            }
        }()
        let constraint: NSLayoutConstraint = {
            switch dimension {
                case .width: return widthAnchor.constraint(equalTo: otherAnchor, multiplier: multiplier, constant: offset)
                case .height: return heightAnchor.constraint(equalTo: otherAnchor, multiplier: multiplier, constant: offset)
            }
        }()
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    func set(_ dimension: Dimension, greaterThanOrEqualTo size: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint: NSLayoutConstraint = {
            switch dimension {
            case .width: return widthAnchor.constraint(greaterThanOrEqualToConstant: size)
            case .height: return heightAnchor.constraint(greaterThanOrEqualToConstant: size)
            }
        }()
        constraint.isActive = true
        return constraint
    }
    
    @discardableResult
    func set(_ dimension: Dimension, lessThanOrEqualTo size: CGFloat) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint: NSLayoutConstraint = {
            switch dimension {
            case .width: return widthAnchor.constraint(lessThanOrEqualToConstant: size)
            case .height: return heightAnchor.constraint(lessThanOrEqualToConstant: size)
            }
        }()
        constraint.isActive = true
        return constraint
    }
}
