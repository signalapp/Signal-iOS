//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ThemeHeaderView: UIView {
    let label: UILabel
    private let blurEffectView: UIVisualEffectView?

    static var labelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped.ows_semibold
    }

    static var desiredHeight: CGFloat {
        return labelFont.pointSize / 17 * 28
    }

    private static var textColor: UIColor {
        if #available(iOS 14, *) {
            return UIColor(dynamicProvider: { _ in
                Theme.isDarkThemeEnabled ? UIColor.ows_gray10 : UIColor.ows_gray90
            })
        } else {
            return Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
        }
    }

    init() {
        label = UILabel()
        label.font = Self.labelFont

        if #available(iOS 14, *) {
            blurEffectView = nil
        } else {
            blurEffectView = UIVisualEffectView(effect: Theme.barBlurEffect)
            blurEffectView!.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        super.init(frame: .zero)
        self.preservesSuperviewLayoutMargins = true

        if let blurEffectView {
            self.addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }
        updateColors()

        self.addSubview(label)

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

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateColors()
    }

    private func updateColors() {
        if blurEffectView != nil {
            self.backgroundColor = Theme.navbarBackgroundColor
                .withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)
        } else {
            self.backgroundColor = .clear
        }
        label.textColor = Self.textColor
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
