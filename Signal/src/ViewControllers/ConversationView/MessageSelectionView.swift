//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageSelectionView: UIView {

    @objc
    public var isSelected: Bool = false {
        didSet {
            selectedView.isHidden = !isSelected
            unselectedView.isHidden = isSelected
        }
    }

    @objc
    public init() {
        super.init(frame: .zero)

        addSubview(selectedView)
        selectedView.autoPinWidthToSuperview()
        selectedView.autoVCenterInSuperview()

        addSubview(unselectedView)
        unselectedView.autoPinWidthToSuperview()
        unselectedView.autoVCenterInSuperview()

        autoSetDimension(.width, toSize: ConversationStyle.selectionViewWidth)
        selectedView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var selectedView: UIView = {
        let wrapper = UIView()
        wrapper.autoSetDimensions(to: CGSize(square: ConversationStyle.selectionViewWidth))

        // the checkmark shape is transparent, but we want it colored white, even in dark theme
        let backgroundView = CircleView(diameter: ConversationStyle.selectionViewWidth - 8)
        backgroundView.backgroundColor = .white
        wrapper.addSubview(backgroundView)
        backgroundView.autoCenterInSuperview()

        let image = #imageLiteral(resourceName: "check-circle-solid-24").withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = .ows_accentBlue
        wrapper.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        return wrapper
    }()

    private lazy var unselectedView: UIView = {
        let view = CircleView(diameter: ConversationStyle.selectionViewWidth)
        view.layer.borderColor = UIColor.ows_gray25.cgColor
        view.layer.borderWidth = 1.5
        return view
    }()
}
