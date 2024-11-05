//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

public struct SignalList<Content: View>: View {
    private var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var list: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            self.list
                .scrollContentBackground(.hidden)
                .background(Color.Signal.groupedBackground)
        } else {
            self.list
        }
    }
}

public struct SignalSection<Content: View, Header: View, Footer: View>: View {

    private enum Components {
        case contentHeaderFooter(Content, Header, Footer)
        case contentHeader(Content, Header)
        case contentFooter(Content, Footer)
        case content(Content)
    }

    private let components: Components

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer
    ) {
        components = .contentHeaderFooter(content(), header(), footer())
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) where Footer == EmptyView {
        components = .contentHeader(content(), header())
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        components = .contentFooter(content(), footer())
    }

    public init(
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView, Header == EmptyView {
        components = .content(content())
    }

    public var body: some View {
        switch components {
        case let .contentHeaderFooter(content, header, footer):
            Section {
                content
            } header: {
                HeaderView {
                    header
                }
            } footer: {
                footer
            }
        case let .contentHeader(content, header):
            Section {
                content
            } header: {
                HeaderView {
                    header
                }
            }
        case let .contentFooter(content, footer):
            Section {
                content
            } footer: {
                footer
            }
        case let .content(content):
            Section {
                content
            }
        }
    }

    private struct HeaderView<C: View>: View {
        private let content: C

        init(@ViewBuilder content: () -> C) {
            self.content = content()
        }

        var body: some View {
            content
                .listRowInsets(.init(top: 12, leading: 8, bottom: 10, trailing: 8))
                .textCase(.none)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }
}

@available(iOS 18.0, *)
#Preview {
    SignalList {
        SignalSection {
            Text(verbatim: "Section with no header or footer")
        }

        SignalSection {
            Text(verbatim: "Section with header")
        } header: {
            Text(verbatim: "Section header")
        }

        SignalSection {
            Text(verbatim: "Section with header and footer")
        } header: {
            Text(verbatim: "Header")
        } footer: {
            Text(verbatim: "Esse aperiam eius neque. Incidunt facere alias quibusdam qui magnam. Ut et quae quo soluta.")
        }
    }
}
