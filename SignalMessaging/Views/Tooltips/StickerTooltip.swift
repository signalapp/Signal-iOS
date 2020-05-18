//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage
import PromiseKit

@objc
public class StickerTooltip: TooltipView {

    private let stickerPack: StickerPack

    // MARK: Initializers

    required init(fromView: UIView,
                  widthReferenceView: UIView,
                  tailReferenceView: UIView,
                  stickerPack: StickerPack,
                  wasTappedBlock: (() -> Void)?) {
        self.stickerPack = stickerPack

        super.init(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, wasTappedBlock: wasTappedBlock)

        addObservers()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private let iconView: YYAnimatedImageView = {
        let stickerView = YYAnimatedImageView()
        stickerView.contentMode = .scaleAspectFit
        return stickerView
    }()

    @objc
    public class func present(fromView: UIView,
                               widthReferenceView: UIView,
                               tailReferenceView: UIView,
                               stickerPack: StickerPack,
                               wasTappedBlock: (() -> Void)?) -> StickerTooltip {
        return StickerTooltip(fromView: fromView, widthReferenceView: widthReferenceView, tailReferenceView: tailReferenceView, stickerPack: stickerPack, wasTappedBlock: wasTappedBlock)
    }

    public override func bubbleContentView() -> UIView {
        iconView.autoSetDimensions(to: CGSize(square: 24))
        updateIconView()

        let label = UILabel()
        label.text = NSLocalizedString("STICKER_PACK_INSTALLED_TOOLTIP",
                                       comment: "Tooltip indicating that a sticker pack was installed.")
        label.font = UIFont.ows_dynamicTypeBody.ows_semibold()
        label.textColor = Theme.primaryTextColor

        return horizontalStack(forSubviews: [iconView, label])
    }

    public override var bubbleColor: UIColor {
        return (Theme.isDarkThemeEnabled
            ? UIColor.ows_accentBlue
            : Theme.backgroundColor)
    }

    private func addObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
    }

    private func updateIconView() {
        guard iconView.image == nil else {
            iconView.isHidden = true
            return
        }
        let stickerInfo = stickerPack.coverInfo
        guard let filePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo) else {
            // This sticker is not downloaded; try to download now.
            firstly {
                StickerManager.tryToDownloadSticker(stickerPack: stickerPack, stickerInfo: stickerInfo)
            }.done { [weak self] (stickerData: Data) in
                guard let self = self else {
                    return
                }
                self.updateIconView(imageData: stickerData)
            }.catch {(error) in
                owsFailDebug("error: \(error)")
            }
            return
        }

        guard let image = YYImage(contentsOfFile: filePath) else {
            owsFailDebug("could not load asset.")
            return
        }
        iconView.image = image
        iconView.isHidden = false
    }

    private func updateIconView(imageData: Data) {
        guard iconView.image == nil else {
            iconView.isHidden = true
            return
        }
        guard let image = YYImage(data: imageData) else {
            owsFailDebug("could not load asset.")
            return
        }
        iconView.image = image
        iconView.isHidden = false
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        updateIconView()
    }
}
