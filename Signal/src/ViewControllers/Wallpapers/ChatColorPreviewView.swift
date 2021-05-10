//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// A round "swatch" that offers a preview of a conversation color option.
public class ChatColorPreviewView: ManualLayoutViewWithLayer {
    private var chatColorValue: ChatColorValue

    public enum Mode {
        case circle
        case rectangle
    }
    private let mode: Mode

    public init(chatColorValue: ChatColorValue, mode: Mode) {
        self.chatColorValue = chatColorValue
        self.mode = mode

        super.init(name: "ChatColorSwatchView")

        self.shouldDeactivateConstraints = false

        configure()

        NotificationCenter.default.addObserver(self, selector: #selector(themeDidChange), name: .ThemeDidChange, object: nil)

        addLayoutBlock { view in
            guard let view = view as? ChatColorPreviewView else { return }
            view.configure()
        }
    }

    @available(swift, obsoleted: 1.0)
    required init(name: String) {
        owsFail("Do not use this initializer.")
    }

    @objc
    private func themeDidChange() {
        configure()
    }

    fileprivate struct State: Equatable {
        let size: CGSize
        let appearance: ChatColorAppearance
    }
    private var state: State?

    private func configure() {
        let size = bounds.size
        let appearance = chatColorValue.appearance
        let newState = State(size: size, appearance: appearance)
        // Exit early if the appearance and bounds haven't changed.
        guard state != newState else {
            return
        }
        self.state = newState

        switch mode {
        case .circle:
            self.layer.cornerRadius = size.smallerAxis * 0.5
            self.clipsToBounds = true
        case .rectangle:
            self.layer.cornerRadius = 0
            self.clipsToBounds = false
        }

        switch appearance {
        case .solidColor(let color):
            backgroundColor = color.uiColor
        case .gradient(let color1, let color2, let angleRadians):
            // TODO:
            backgroundColor = color1.uiColor
        }
    }
}
