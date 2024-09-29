//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Lottie
public import SignalServiceKit
import YYImage

public class StickerView {

    // Never instantiate this class.
    private init() {}

    public static func stickerView(forStickerInfo stickerInfo: StickerInfo,
                                   dataSource: StickerPackDataSource,
                                   size: CGFloat? = nil) -> UIView? {
        guard let stickerMetadata = dataSource.metadata(forSticker: stickerInfo) else {
            Logger.warn("Missing sticker metadata.")
            return nil
        }
        return stickerView(stickerInfo: stickerInfo, stickerMetadata: stickerMetadata, size: size)
    }

    public static func stickerView(forInstalledStickerInfo stickerInfo: StickerInfo,
                                   size: CGFloat? = nil) -> UIView? {
        let metadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo)
        guard let stickerMetadata = metadata else {
            Logger.warn("Missing sticker metadata.")
            return nil
        }
        return stickerView(stickerInfo: stickerInfo, stickerMetadata: stickerMetadata, size: size)
    }

    private static func stickerView(
        stickerInfo: StickerInfo,
        stickerMetadata: any StickerMetadata,
        size: CGFloat? = nil
    ) -> UIView? {
        guard
            let stickerView = self.stickerView(
                stickerInfo: stickerInfo,
                stickerType: stickerMetadata.stickerType,
                stickerMetadata: stickerMetadata
            )
        else {
            Logger.warn("Could not load sticker for display.")
            return nil
        }
        if let size = size {
            stickerView.autoSetDimensions(to: CGSize(square: size))
        }
        return stickerView
    }

    static func stickerView(
        stickerInfo: StickerInfo,
        stickerType: StickerType,
        stickerMetadata: any StickerMetadata
    ) -> UIView? {
        guard let stickerData = try? stickerMetadata.readStickerData() else {
            Logger.warn("Sticker data does not exist.")
            return nil
        }

        guard stickerMetadata.isValidImage() else {
            owsFailDebug("Invalid sticker")
            return nil
        }

        let stickerView: UIView
        switch stickerType {
        case .webp, .apng, .gif:
            guard let stickerImage = YYImage(data: stickerData) else {
                owsFailDebug("Sticker could not be parsed.")
                return nil
            }
            let yyView = YYAnimatedImageView()
            yyView.alwaysInfiniteLoop = true
            yyView.contentMode = .scaleAspectFit
            yyView.image = stickerImage
            stickerView = yyView
        }
        return stickerView
    }
}

public class StickerPlaceholderView: UIView {
    let placeholderView = UIView()
    public init(color: UIColor) {
        super.init(frame: .zero)

        placeholderView.backgroundColor = color
        addSubview(placeholderView)
        placeholderView.autoPinEdgesToSuperviewMargins()

        placeholderView.layer.cornerCurve = .continuous
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        layoutMargins = UIEdgeInsets(hMargin: width / 8, vMargin: height / 8)
        placeholderView.layer.cornerRadius = placeholderView.width / 3
    }
}

public class StickerReusableView: UIView {
    public var hasStickerView: Bool { stickerView != nil }

    private weak var stickerView: UIView?
    public func configure(with stickerView: UIView) {
        guard stickerView != self.stickerView else { return }

        self.stickerView = stickerView
        addSubview(stickerView)
        stickerView.autoPinEdgesToSuperviewEdges()

        if let placeholderView = placeholderView {
            self.placeholderView = nil
            stickerView.alpha = 0

            UIView.animate(withDuration: 0.2) {
                stickerView.alpha = 1
                placeholderView.alpha = 0
            } completion: { _ in
                placeholderView.removeFromSuperview()
            }
        }
    }

    private weak var placeholderView: StickerPlaceholderView?
    public func showPlaceholder(color: UIColor = Theme.secondaryBackgroundColor) {
        guard placeholderView == nil else { return }
        let placeholderView = StickerPlaceholderView(color: color)
        self.placeholderView = placeholderView
        addSubview(placeholderView)
        placeholderView.autoPinEdgesToSuperviewEdges()

        if let stickerView = stickerView {
            self.stickerView = nil
            placeholderView.alpha = 0

            UIView.animate(withDuration: 0.2) {
                placeholderView.alpha = 1
                stickerView.alpha = 0
            } completion: { _ in
                stickerView.removeFromSuperview()
            }
        }
    }
}
