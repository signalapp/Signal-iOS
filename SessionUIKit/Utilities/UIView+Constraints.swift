// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

// MARK: - Enums

public protocol ConstraintUtilitiesEdge {}

public extension UIView {
    enum HorizontalEdge: ConstraintUtilitiesEdge { case left, leading, right, trailing }
    enum VerticalEdge: ConstraintUtilitiesEdge { case top, bottom }
    enum Direction { case horizontal, vertical }
    enum Dimension { case width, height }
}

// MARK: - Anchorable

public protocol Anchorable {
    func anchor(from edge: UIView.HorizontalEdge) -> NSLayoutXAxisAnchor
    func anchor(from edge: UIView.VerticalEdge) -> NSLayoutYAxisAnchor
}

extension UIView: Anchorable {
    public func anchor(from edge: UIView.HorizontalEdge) -> NSLayoutXAxisAnchor {
        switch edge {
            case .left: return leftAnchor
            case .leading: return leadingAnchor
            case .right: return rightAnchor
            case .trailing: return trailingAnchor
        }
    }
    
    public func anchor(from edge: UIView.VerticalEdge) -> NSLayoutYAxisAnchor {
        switch edge {
            case .top: return topAnchor
            case .bottom: return bottomAnchor
        }
    }
}

extension UILayoutGuide: Anchorable {
    public func anchor(from edge: UIView.HorizontalEdge) -> NSLayoutXAxisAnchor {
        switch edge {
            case .left: return leftAnchor
            case .leading: return leadingAnchor
            case .right: return rightAnchor
            case .trailing: return trailingAnchor
        }
    }
    
    public func anchor(from edge: UIView.VerticalEdge) -> NSLayoutYAxisAnchor {
        switch edge {
            case .top: return topAnchor
            case .bottom: return bottomAnchor
        }
    }
}

fileprivate extension NSLayoutConstraint {
    func setting(isActive: Bool) -> NSLayoutConstraint {
        self.isActive = isActive
        return self
    }
}

public extension Anchorable {
    @discardableResult
    func pin(_ constraineeEdge: UIView.HorizontalEdge, to constrainerEdge: UIView.HorizontalEdge, of anchorable: Anchorable, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        (self as? UIView)?.translatesAutoresizingMaskIntoConstraints = false
        
        return anchor(from: constraineeEdge)
            .constraint(
                equalTo: anchorable.anchor(from: constrainerEdge),
                constant: inset
            )
            .setting(isActive: true)
    }
    
    @discardableResult
    func pin(_ constraineeEdge: UIView.VerticalEdge, to constrainerEdge: UIView.VerticalEdge, of anchorable: Anchorable, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        (self as? UIView)?.translatesAutoresizingMaskIntoConstraints = false
        
        return anchor(from: constraineeEdge)
            .constraint(
                equalTo: anchorable.anchor(from: constrainerEdge),
                constant: inset
            )
            .setting(isActive: true)
    }
}

// MARK: - View extensions

public extension UIView {
    func pin(_ edges: [ConstraintUtilitiesEdge], to view: UIView) {
        edges.forEach {
            switch $0 {
                case let edge as HorizontalEdge: pin(edge, to: edge, of: view)
                case let edge as VerticalEdge: pin(edge, to: edge, of: view)
                default: break
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
    func center(_ direction: Direction, in view: UIView, withInset inset: CGFloat = 0) -> NSLayoutConstraint {
        translatesAutoresizingMaskIntoConstraints = false
        let constraint: NSLayoutConstraint = {
            switch direction {
            case .horizontal: return centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: inset)
            case .vertical: return centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: inset)
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
