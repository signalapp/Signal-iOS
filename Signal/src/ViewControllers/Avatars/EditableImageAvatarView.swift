//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class EditableImageAvatarView: UIView {
    public var theme: AvatarTheme { didSet { updateTheme() }}

    public convenience init(theme: AvatarTheme, icon: AvatarIcon) {
        self.init(theme: theme, image: icon.image)
    }

    public init(theme: AvatarTheme, image: UIImage) {
        self.theme = theme
        super.init(frame: .zero)

        let imageView = UIImageView()
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.autoPinEdgesToSuperviewEdges()
        imageView.clipsToBounds = true

        addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges()

        updateTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    public override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = height / 2
    }

    // MARK: -

    func updateTheme() {
        backgroundColor = theme.backgroundColor
    }
}
