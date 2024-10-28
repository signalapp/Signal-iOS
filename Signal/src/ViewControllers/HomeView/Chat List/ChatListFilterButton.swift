//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import UIKit

class ChatListFilterButton: UIButton {
    private var haptic: UIImpactFeedbackGenerator?

    var showsClearIcon = false {
        didSet {
            if showsClearIcon != oldValue {
                setNeedsUpdateConfiguration()
            }
        }
    }

    init() {
        super.init(frame: .zero)
        configuration = .chatListFilter()
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("unimplemented")
    }

    override func updateConfiguration() {
        super.updateConfiguration()

        let title = configuration?.title

        var newValue: UIButton.Configuration = showsClearIcon
            ? .chatListRemoveFilter(compatibleWith: traitCollection)
            : .chatListFilter(compatibleWith: traitCollection)
        newValue.title = title

        configuration = newValue.updated(for: self)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        haptic = UIImpactFeedbackGenerator(style: .light)
        haptic?.prepare()
    }

    override func sendAction(_ action: UIAction) {
        super.sendAction(action)
        haptic?.impactOccurred()
    }

    override func sendActions(for controlEvents: UIControl.Event) {
        super.sendActions(for: controlEvents)
        if controlEvents.contains(.primaryActionTriggered) {
            haptic?.impactOccurred()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        haptic = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        haptic = nil
    }
}

extension UIButton.Configuration {
    static let chatListFilterTextStyle = UIFont.TextStyle.footnote

    static func chatListFilter(compatibleWith traitCollection: UITraitCollection? = nil) -> Self {
        let fontMetrics = UIFontMetrics(forTextStyle: chatListFilterTextStyle)
        var configuration = gray()
        configuration.background.cornerRadius = .greatestFiniteMagnitude // fully rounded / pill-shaped
        configuration.baseBackgroundColor = .Signal.secondaryBackground
        configuration.baseForegroundColor = .Signal.label
        configuration.buttonSize = .small
        configuration.titleLineBreakMode = .byTruncatingMiddle
        let horizontalInset = fontMetrics.scaledValue(for: 12, compatibleWith: traitCollection)
        configuration.contentInsets.leading = horizontalInset
        configuration.contentInsets.trailing = horizontalInset
        let verticalInset = fontMetrics.scaledValue(for: 6, compatibleWith: traitCollection)
        configuration.contentInsets.top = verticalInset
        configuration.contentInsets.bottom = verticalInset
        configuration.imagePadding = fontMetrics.scaledValue(for: 4, compatibleWith: traitCollection)
        configuration.imagePlacement = .trailing
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .small)
        let font = UIFont.preferredFont(forTextStyle: chatListFilterTextStyle, compatibleWith: traitCollection).medium()
        configuration.titleTextAttributesTransformer = .defaultFont(font)
        return configuration
    }

    static func chatListRemoveFilter(compatibleWith traitCollection: UITraitCollection? = nil) -> Self {
        var configuration = chatListFilter(compatibleWith: traitCollection)
        configuration.baseBackgroundColor = .clear
        configuration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        configuration.image = UIImage(systemName: "xmark", compatibleWith: traitCollection)
        configuration.imageColorTransformer = .monochromeTint
        let font = UIFont.preferredFont(forTextStyle: chatListFilterTextStyle, compatibleWith: traitCollection).semibold()
        configuration.titleTextAttributesTransformer = .defaultFont(font)
        return configuration
    }
}

#if DEBUG
import SwiftUI

struct ChatListFilterButtonPreviews: PreviewProvider {
    static var previews: some View {
        VStack {
            ChatListFilterButton(title: "Filtered by Unread", showsClearIcon: true)
            ChatListFilterButton(title: "Clear Unread Filter")
        }
    }

    struct ChatListFilterButton: UIViewRepresentable {
        var title: String
        var showsClearIcon: Bool = false

        func makeUIView(context: Context) -> Signal.ChatListFilterButton {
            Signal.ChatListFilterButton()
        }

        func updateUIView(_ button: Signal.ChatListFilterButton, context: Context) {
            button.configuration?.title = title
            button.showsClearIcon = showsClearIcon
        }
    }
}
#endif // DEBUG
