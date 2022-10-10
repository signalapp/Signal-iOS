// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class PathStatusView: UIView {
    enum Size {
        case small
        case large
        
        var pointSize: CGFloat {
            switch self {
                case .small: return 8
                case .large: return 16
            }
        }
        
        func offset(for interfaceStyle: UIUserInterfaceStyle) -> CGFloat {
            switch self {
                case .small: return (interfaceStyle == .light ? 6 : 8)
                case .large: return (interfaceStyle == .light ? 6 : 8)
            }
        }
    }
    
    enum Status {
        case unknown
        case connecting
        case connected
        case error
        
        var themeColor: ThemeValue {
            switch self {
                case .unknown: return .path_unknown
                case .connecting: return .path_connecting
                case .connected: return .path_connected
                case .error: return .path_error
            }
        }
    }
    
    // MARK: - Initialization
    
    private let size: Size
    
    init(size: Size = .small) {
        self.size = size
        
        super.init(frame: .zero)
        
        setUpViewHierarchy()
        registerObservers()
    }

    required init?(coder: NSCoder) {
        self.size = .small
        
        super.init(coder: coder)
        
        setUpViewHierarchy()
        registerObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Layout
    
    private func setUpViewHierarchy() {
        layer.cornerRadius = (self.size.pointSize / 2)
        layer.masksToBounds = false
        self.set(.width, to: self.size.pointSize)
        self.set(.height, to: self.size.pointSize)
        
        setStatus(to: (!OnionRequestAPI.paths.isEmpty ? .connected : .connecting))
    }
    
    // MARK: - Functions

    private func registerObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleBuildingPathsNotification), name: .buildingPaths, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handlePathsBuiltNotification), name: .pathsBuilt, object: nil)
    }

    private func setStatus(to status: Status) {
        themeBackgroundColor = status.themeColor
        layer.themeShadowColor = status.themeColor
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(
                origin: CGPoint.zero,
                size: CGSize(width: self.size.pointSize, height: self.size.pointSize)
            )
        ).cgPath
        
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _ in
            self?.layer.shadowOpacity = (theme.interfaceStyle == .light ? 0.4 : 1)
            self?.layer.shadowRadius = (self?.size.offset(for: theme.interfaceStyle) ?? 0)
        }
    }

    @objc private func handleBuildingPathsNotification() {
        setStatus(to: .connecting)
    }

    @objc private func handlePathsBuiltNotification() {
        setStatus(to: .connected)
    }
}
