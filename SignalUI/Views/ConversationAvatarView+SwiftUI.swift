//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI
public import SignalServiceKit

public struct AvatarView: View {
    public typealias Configuration = ConversationAvatarView.Configuration

    public var dataSource: ConversationAvatarDataSource?
    public var sizeClass: Configuration.SizeClass
    public var localUserDisplayMode: LocalUserDisplayMode
    public var badged: Bool
    public var shape: Configuration.Shape

    public init(
        dataSource: ConversationAvatarDataSource?,
        sizeClass: Configuration.SizeClass,
        localUserDisplayMode: LocalUserDisplayMode,
        badged: Bool = true,
        shape: Configuration.Shape = .circular
    ) {
        self.dataSource = dataSource
        self.sizeClass = sizeClass
        self.localUserDisplayMode = localUserDisplayMode
        self.badged = badged
        self.shape = shape
    }

    public var body: some View {
        AvatarViewRepresentable(
            dataSource: self.dataSource,
            sizeClass: self.sizeClass,
            localUserDisplayMode: self.localUserDisplayMode,
            badged: self.badged,
            shape: self.shape,
            useAutolayout: true
        )
        .fixedSize()
    }

    private struct AvatarViewRepresentable: UIViewRepresentable {
        var dataSource: ConversationAvatarDataSource?
        var sizeClass: Configuration.SizeClass
        var localUserDisplayMode: LocalUserDisplayMode
        var badged: Bool
        var shape: Configuration.Shape
        var useAutolayout: Bool

        func makeUIView(context: Context) -> ConversationAvatarView {
            let uiView = ConversationAvatarView(
                sizeClass: self.sizeClass,
                localUserDisplayMode: self.localUserDisplayMode,
                badged: self.badged,
                shape: self.shape,
                useAutolayout: self.useAutolayout
            )
            if let dataSource {
                uiView.updateWithSneakyTransactionIfNecessary { config in
                    config.dataSource = dataSource
                }
            }
            return uiView
        }

        func updateUIView(_ uiView: ConversationAvatarView, context: Context) {
            uiView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = self.dataSource
                config.sizeClass = self.sizeClass
                config.localUserDisplayMode = self.localUserDisplayMode
                config.addBadgeIfApplicable = self.badged
                config.shape = self.shape
                config.useAutolayout = self.useAutolayout
            }
        }
    }
}

#Preview {
    AvatarView(
        dataSource: .asset(
            avatar: .init(named: "avatar_cat"),
            badge: nil
        ),
        sizeClass: .eightyEight,
        localUserDisplayMode: .asLocalUser,
        badged: false,
        shape: .circular
    )
}
