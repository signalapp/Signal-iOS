//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ThemeHeaderView: UIView {
    // HACK: scrollbar incorrectly appears *behind* section headers
    // in collection view on iOS11 =(
    private class AlwaysOnTopLayer: CALayer {
        override var zPosition: CGFloat {
            get { return 0 }
            set {}
        }
    }

    let label: UILabel

    override public class var layerClass: AnyClass {
        get {
            guard #available(iOS 11.4, *) else {
                // HACK: scrollbar incorrectly appears *behind* section headers
                // in collection view on early iOS11.
                // Appears fine on iOS11.4+
                return AlwaysOnTopLayer.self
            }

            return super.layerClass
        }
    }

    static var labelFont: UIFont {
        return UIFont.ows_dynamicTypeBody.ows_semibold
    }

    static var desiredHeight: CGFloat {
        return labelFont.pointSize / 17 * 28
    }

    init(alwaysDark: Bool = false) {
        label = UILabel()
        label.textColor = alwaysDark ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
        label.font = type(of: self).labelFont

        let blurEffect = alwaysDark ? Theme.darkThemeBarBlurEffect : Theme.barBlurEffect
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: .zero)
        self.preservesSuperviewLayoutMargins = true

        self.backgroundColor = (alwaysDark ? Theme.darkThemeNavbarBackgroundColor : Theme.navbarBackgroundColor)
            .withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

        self.addSubview(blurEffectView)
        self.addSubview(label)

        blurEffectView.autoPinEdgesToSuperviewEdges()
        label.autoPinEdge(toSuperviewMargin: .trailing)
        label.autoPinEdge(toSuperviewMargin: .leading)
        label.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(title: String) {
        self.label.text = title
    }

    public func prepareForReuse() {
        self.label.text = nil
    }
}

public class ThemeCollectionViewSectionHeader: UICollectionReusableView {
    public class var reuseIdentifier: String { return "ThemeCollectionViewSectionHeader" }

    fileprivate lazy var headerView = buildHeaderView()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        preservesSuperviewLayoutMargins = true
        addSubview(headerView)
        headerView.autoPinEdgesToSuperviewEdges()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
    }

    public func configure(title: String) {
        headerView.configure(title: title)
    }

    fileprivate func buildHeaderView() -> ThemeHeaderView {
        return ThemeHeaderView()
    }
}

public class DarkThemeCollectionViewSectionHeader: ThemeCollectionViewSectionHeader {
    public override class var reuseIdentifier: String { return "DarkThemeCollectionViewSectionHeader" }

    override func buildHeaderView() -> ThemeHeaderView {
        return ThemeHeaderView(alwaysDark: true)
    }
}

public class DarkThemeTableSectionHeader: UITableViewHeaderFooterView {
    public static let reuseIdentifier = "DarkThemeTableSectionHeader"
    private let headerView: ThemeHeaderView

    public override init(reuseIdentifier: String?) {
        self.headerView = ThemeHeaderView(alwaysDark: true)
        super.init(reuseIdentifier: reuseIdentifier)
        preservesSuperviewLayoutMargins = true
        contentView.addSubview(headerView)
        headerView.autoPinEdgesToSuperviewEdges()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func prepareForReuse() {
        super.prepareForReuse()
        headerView.prepareForReuse()
    }

    public func configure(title: String) {
        headerView.configure(title: title)
    }
}
