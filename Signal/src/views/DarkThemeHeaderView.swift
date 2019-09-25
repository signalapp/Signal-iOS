//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

public class DarkThemeHeaderView: UIView {
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
                if #available(iOS 11, *) {
                    return AlwaysOnTopLayer.self
                } else {
                    return super.layerClass
                }
            }

            return super.layerClass
        }
    }

    static var labelFont: UIFont {
        return UIFont.ows_dynamicTypeBody.ows_semiBold()
    }

    static var desiredHeight: CGFloat {
        return labelFont.pointSize / 17 * 28
    }

    override init(frame: CGRect) {
        label = UILabel()
        label.textColor = Theme.darkThemeSecondaryColor
        label.font = type(of: self).labelFont

        let blurEffect = Theme.darkThemeBarBlurEffect
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: frame)
        self.preservesSuperviewLayoutMargins = true

        self.backgroundColor = Theme.darkThemeNavbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

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

public class DarkThemeCollectionViewSectionHeader: UICollectionReusableView {
    public static let reuseIdentifier = "DarkThemeCollectionViewSectionHeader"

    private let headerView: DarkThemeHeaderView
    public override init(frame: CGRect) {
        self.headerView = DarkThemeHeaderView(frame: frame)
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
}

public class DarkThemeTableSectionHeader: UITableViewHeaderFooterView {
    public static let reuseIdentifier = "DarkThemeTableSectionHeader"
    private let headerView: DarkThemeHeaderView

    public override init(reuseIdentifier: String?) {
        self.headerView = DarkThemeHeaderView(forAutoLayout: ())
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
