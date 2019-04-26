//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public class OWSButton: UIButton {

    @objc
    var block: () -> Void = { }

    // MARK: -

    @objc
    public init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    @objc
    public init(title: String, block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        setTitle(title, for: .normal)
    }

    @objc
    public init(imageName: String,
         tintColor: UIColor?,
         block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        setImage(imageName: imageName)
        self.tintColor = tintColor
    }

    @objc
    public func setImage(imageName: String) {
        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    @objc
    func didTap() {
        block()
    }
}
