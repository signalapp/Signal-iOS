//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

    static var labelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped.ows_semibold
    }

    static var desiredHeight: CGFloat {
        return labelFont.pointSize / 17 * 28
    }

    init(alwaysDark: Bool = false) {
        label = UILabel()
        label.textColor = alwaysDark
            ? Theme.darkThemeSecondaryTextAndIconColor
            : (Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90)
        label.font = Self.labelFont

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
        fatalError("init(coder:) has not been implemented")
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
