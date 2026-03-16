//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

struct ConversationHeaderView: View {
    
    var title: String = ""
    var subtitle: String = ""
    var titleIcon: Image?
    var threadViewModel: ThreadViewModel?
    
    var onHeaderTap: (() -> Void)?
    var onAvatarTap: (() -> Void)?
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.colorScheme) var colorScheme
    
    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass {
        // One size for the navigation bar on iOS 26.
        if #available(iOS 26, *) {
            return .forty
        }
        
        return verticalSizeClass == .compact && !UIDevice.current.isPlusSizePhone
            ? .twentyFour
            : .thirtySix
    }
    
    private var layoutSpacing: CGFloat {
        if #available(iOS 26, *) {
            return 12
        }
        return 8
    }
    
    private var leadingMargin: CGFloat {
        if #available(iOS 26, *) {
            return 4
        }
        return 0
    }
    
    var body: some View {
        VStack(spacing: layoutSpacing) {
            // Avatar
            ConversationAvatarViewRepresentable(
                threadViewModel: threadViewModel,
                sizeClass: avatarSizeClass
            )
            .frame(width: avatarFrameSize, height: avatarFrameSize)
            .onTapGesture {
                onAvatarTap?()
            }
            
            // Text Content
            HStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.Signal.label)
                            .lineLimit(1)
                        
                        if let titleIcon = titleIcon {
                            titleIcon
                                .frame(width: 16, height: 16)
                                .aspectRatio(contentMode: .fit)
                        }
                    }
                    
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.Signal.label)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }
        .padding(.horizontal, leadingMargin)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            onHeaderTap?()
        }
    }
    
    private var avatarFrameSize: CGFloat {
        switch avatarSizeClass {
        case .twenty: return 20
        case .twentyFour: return 24
        case .thirtySix: return 36
        case .forty: return 40
        case .fortyEight: return 48
        @unknown default: return 36
        }
    }
}

// MARK: - UIKit Bridge for ConversationAvatarView

struct ConversationAvatarViewRepresentable: UIViewRepresentable {
    var threadViewModel: ThreadViewModel?
    var sizeClass: ConversationAvatarView.Configuration.SizeClass
    
    func makeUIView(context: Context) -> ConversationAvatarView {
        let avatarView = ConversationAvatarView(
            sizeClass: sizeClass,
            localUserDisplayMode: .noteToSelf
        )
        return avatarView
    }
    
    func updateUIView(_ uiView: ConversationAvatarView, context: Context) {
        if let threadViewModel = threadViewModel {
            uiView.updateWithSneakyTransactionIfNecessary { config in
                config.dataSource = .thread(threadViewModel.threadRecord)
                config.storyConfiguration = .autoUpdate()
                config.applyConfigurationSynchronously()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ConversationHeaderView(
        title: "John Doe",
        subtitle: "Active now",
        titleIcon: Image(systemName: "lock.fill"),
        onHeaderTap: { print("Header tapped") },
        onAvatarTap: { print("Avatar tapped") }
    )
    .padding()
}
