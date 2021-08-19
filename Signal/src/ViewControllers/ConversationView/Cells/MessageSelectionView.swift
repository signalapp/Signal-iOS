//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class MessageSelectionView: ManualLayoutView {

    public var isSelected: Bool = false {
        didSet {
            selectedView.isHidden = !isSelected
            unselectedView.isHidden = isSelected
        }
    }

    public init() {
        super.init(name: "MessageSelectionView")

        addSubviewToFillSuperviewEdges(backgroundView)
        addSubviewToCenterOnSuperview(selectedView, size: Self.uiSize)
        addSubviewToCenterOnSuperview(unselectedView, size: Self.uiSize)

        selectedView.isHidden = true
    }

    @available(*, unavailable, message: "use other constructor instead.")
    public required init(name: String) {
        notImplemented()
    }

    public static var totalSize: CGSize {
        CGSize(square: ConversationStyle.selectionViewWidth)
    }
    private static var uiSize: CGSize {
        CGSize(square: ConversationStyle.selectionViewWidth - 2)
    }

    private let selectedView: CVImageView = {
        let checkmarkView = CVImageView()
        checkmarkView.setTemplateImageName("check-circle-solid-24", tintColor: .white)
        return checkmarkView
    }()

    private let unselectedView: CircleView = {
        let circleView = CircleView(diameter: MessageSelectionView.uiSize.width)
        circleView.layer.borderWidth = 1.5
        return circleView
    }()

    private let backgroundView: UIView = {
        ManualLayoutViewWithLayer.circleView(name: "selection background")
    }()

    public func updateStyle(conversationStyle: ConversationStyle) {
        AssertIsOnMainThread()

        if conversationStyle.isDarkThemeEnabled || conversationStyle.hasWallpaper {
            selectedView.tintColor = .ows_white
            unselectedView.layer.borderColor = UIColor.ows_white.cgColor
            backgroundView.backgroundColor = UIColor.ows_black.withAlphaComponent(0.2)
            backgroundView.isHidden = (!conversationStyle.hasWallpaper ||
                                        !conversationStyle.isWallpaperPhoto)
        } else {
            selectedView.tintColor = .ows_accentBlue
            unselectedView.layer.borderColor = UIColor.ows_gray25.cgColor
            backgroundView.isHidden = true
        }
    }
}
