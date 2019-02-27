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
    init(block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }

    @objc
    init(title: String, block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
        setTitle(title, for: .normal)
    }

    @objc
    init(imageName: String,
         tintColor: UIColor,
         block: @escaping () -> Void = { }) {
        super.init(frame: .zero)

        self.block = block
        addTarget(self, action: #selector(didTap), for: .touchUpInside)

        if let image = UIImage(named: imageName) {
            setImage(image.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            owsFailDebug("Missing asset: \(imageName)")
        }
        self.tintColor = tintColor
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
