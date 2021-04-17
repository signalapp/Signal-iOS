//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageSelectionView: ManualLayoutView {

    @objc
    public var isSelected: Bool = false {
        didSet {
            selectedView.isHidden = !isSelected
            unselectedView.isHidden = isSelected
        }
    }

    @objc
    public init() {
        super.init(name: "MessageSelectionView")

        addSubview(selectedView)
        addSubview(unselectedView)

        centerSubviewOnSuperview(selectedView, size: Self.contentSize)
        centerSubviewOnSuperview(unselectedView, size: Self.contentSize)

        selectedView.isHidden = true
    }

    @available(*, unavailable, message: "use other constructor instead.")
    @objc
    public required init(name: String) {
        notImplemented()
    }

    private static var contentSize: CGSize {
        CGSize(square: ConversationStyle.selectionViewWidth)
    }

    private lazy var selectedView: UIView = {
        let wrapper = ManualLayoutView(name: "MessageSelectionView.selectedView")

        // the checkmark shape is transparent, but we want it colored white, even in dark theme
        let backgroundSize = ConversationStyle.selectionViewWidth - 8
        let backgroundView = CircleView(diameter: backgroundSize)
        backgroundView.backgroundColor = .white
        wrapper.addSubview(backgroundView)
        wrapper.centerSubviewOnSuperview(backgroundView, size: .square(backgroundSize))

        let image = #imageLiteral(resourceName: "check-circle-solid-24").withRenderingMode(.alwaysTemplate)
        let imageView = CVImageView(image: image)
        imageView.tintColor = .ows_accentBlue
        wrapper.addSubview(imageView)
        wrapper.layoutSubviewToFillSuperviewEdges(imageView)

        return wrapper
    }()

    private lazy var unselectedView: UIView = {
        let view = CircleView(diameter: ConversationStyle.selectionViewWidth)
        view.layer.borderColor = UIColor.ows_gray25.cgColor
        view.layer.borderWidth = 1.5
        return view
    }()
}
