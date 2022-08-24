// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class PathStatusView: UIView {
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
    
    static let size: CGFloat = 8
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setUpViewHierarchy()
        registerObservers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpViewHierarchy()
        registerObservers()
    }
    
    private func setUpViewHierarchy() {
        layer.cornerRadius = (PathStatusView.size / 2)
        layer.masksToBounds = false
        
        setStatus(to: (!OnionRequestAPI.paths.isEmpty ? .connected : .connecting))
    }

    private func registerObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleBuildingPathsNotification), name: .buildingPaths, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handlePathsBuiltNotification), name: .pathsBuilt, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setStatus(to status: Status) {
        themeBackgroundColor = status.themeColor
        layer.themeShadowColor = status.themeColor
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        layer.shadowPath = UIBezierPath(
            ovalIn: CGRect(
                origin: CGPoint.zero,
                size: CGSize(width: PathStatusView.size, height: PathStatusView.size)
            )
        ).cgPath
        
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _ in
            self?.layer.shadowOpacity = (theme.interfaceStyle == .light ? 0.4 : 1)
            self?.layer.shadowRadius = (theme.interfaceStyle == .light ? 6 : 8)
        }
    }

    @objc private func handleBuildingPathsNotification() {
        setStatus(to: .connecting)
    }

    @objc private func handlePathsBuiltNotification() {
        setStatus(to: .connected)
    }
}
