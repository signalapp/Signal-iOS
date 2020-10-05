//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
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

    private let iconView = UIView()

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
        label.font = UIFont.ows_dynamicTypeBody.ows_semibold
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
        let stickerPackItem: StickerPackItem = stickerPack.cover
        let stickerInfo = stickerPackItem.stickerInfo(with: stickerPack)
        let installedMetadata = StickerManager.installedStickerMetadataWithSneakyTransaction(stickerInfo: stickerInfo)
        guard let stickerMetadata = installedMetadata else {
            updateIconView(stickerPackItem: stickerPackItem,
                           stickerDataUrl: nil)

            // This sticker is not downloaded; try to download now.
            firstly {
                StickerManager.tryToDownloadSticker(stickerPack: self.stickerPack, stickerInfo: stickerInfo)
            }.map(on: .global()) { (stickerData: Data) in
                let stickerType = StickerManager.stickerType(forContentType: stickerPackItem.contentType)
                let stickerDataUrl = OWSFileSystem.temporaryFileUrl(fileExtension: stickerType.fileExtension)
                try stickerData.write(to: stickerDataUrl)
                return stickerDataUrl
            }.done { [weak self] (stickerDataUrl: URL) in
                guard let self = self else {
                    return
                }
                self.updateIconView(stickerPackItem: stickerPackItem,
                                    stickerDataUrl: stickerDataUrl)
            }.catch {(error) in
                owsFailDebug("error: \(error)")
            }

            return
        }
        updateIconView(stickerPackItem: stickerPackItem,
                       stickerDataUrl: stickerMetadata.stickerDataUrl)
    }

    private func updateIconView(stickerPackItem: StickerPackItem,
                                stickerDataUrl: URL?) {
        for subview in iconView.subviews {
            subview.removeFromSuperview()
        }
        guard let stickerDataUrl = stickerDataUrl else {
            iconView.isHidden = true
            return
        }
        let stickerInfo = stickerPackItem.stickerInfo(with: stickerPack)
        let stickerType: StickerType = StickerManager.stickerType(forContentType: stickerPackItem.contentType)
        guard let stickerView = StickerView.stickerView(stickerInfo: stickerInfo,
                                                        stickerType: stickerType,
                                                        stickerDataUrl: stickerDataUrl) else {
            iconView.isHidden = true
            return
        }
        iconView.addSubview(stickerView)
        stickerView.autoPinEdgesToSuperviewEdges()
        iconView.isHidden = false
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        updateIconView()
    }
}
