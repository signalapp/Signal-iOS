//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

// MARK: - SignalList

public struct SignalList<Content: View>: View {
    private var content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var list: some View {
        List {
            content
        }
        .readScrollOffset()
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

// MARK: - SignalSection

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
                ContentView {
                    content
                }
            } header: {
                HeaderView {
                    header
                }
            } footer: {
                footer
            }
        case let .contentHeader(content, header):
            Section {
                ContentView {
                    content
                }
            } header: {
                HeaderView {
                    header
                }
            }
        case let .contentFooter(content, footer):
            Section {
                ContentView {
                    content
                }
            } footer: {
                footer
            }
        case let .content(content):
            Section {
                ContentView {
                    content
                }
            }
        }
    }

    private struct ContentView<C: View>: View {
        private let content: C

        init(@ViewBuilder content: () -> C) {
            self.content = content()
        }

        var body: some View {
            content
            // The table cells have a top margin of 12, so the top of
            // the cell is 12 points above the top of the content.
                .provideScrollAnchor(correction: -12)
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
                .provideScrollAnchor(correction: 4)
        }
    }
}

// MARK: - Previews

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
