import UIKit

final class PathStatusView : UIView {
    
    static let size = CGFloat(8)
    
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
        layer.cornerRadius = PathStatusView.size / 2
        layer.masksToBounds = false
        if OnionRequestAPI.paths.isEmpty {
            OnionRequestAPI.paths = Storage.shared.getOnionRequestPaths()
        }
        let color = (!OnionRequestAPI.paths.isEmpty) ? Colors.accent : Colors.pathsBuilding
        setColor(to: color, isAnimated: false)
    }

    private func registerObservers() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(handleBuildingPathsNotification), name: .buildingPaths, object: nil)
        notificationCenter.addObserver(self, selector: #selector(handlePathsBuiltNotification), name: .pathsBuilt, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setColor(to color: UIColor, isAnimated: Bool) {
        backgroundColor = color
        let size = PathStatusView.size
        let glowConfiguration = UIView.CircularGlowConfiguration(size: size, color: color, isAnimated: isAnimated, radius: isLightMode ? 6 : 8)
        setCircularGlow(with: glowConfiguration)
    }

    @objc private func handleBuildingPathsNotification() {
        setColor(to: Colors.pathsBuilding, isAnimated: true)
    }

    @objc private func handlePathsBuiltNotification() {
        setColor(to: Colors.accent, isAnimated: true)
    }
}
