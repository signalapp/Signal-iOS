//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

// MARK: - SignalList

public struct SignalList<Content: View>: View {
    private let sectionSpacing: CGFloat?
    private var content: Content

    public init(
        sectionSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.sectionSpacing = sectionSpacing
        self.content = content()
    }

    @ViewBuilder
    private var list: some View {
        let horizontalPadding: CGFloat = UIDevice.current.isIPad ? 32 : 0

        List {
            if #available(iOS 16.0, *) {
                content
                    .listRowBackground(Color.Signal.secondaryGroupedBackground)
            } else {
                content
            }
        }
        .readScrollOffset()
        .listStyle(.insetGrouped)
        .padding(.horizontal, horizontalPadding)
    }

    @available(iOS 16.0, *)
    private var listWithBackground: some View {
        self.list
            .scrollContentBackground(.hidden)
            .background(Color.Signal.groupedBackground)
    }

    public var body: some View {
        if #available(iOS 16.0, *) {
            if #available(iOS 17, *), let sectionSpacing {
                listWithBackground
                    .listSectionSpacing(sectionSpacing)
            } else {
                listWithBackground
            }
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

    /// Only applies on iOS 17+
    private let sectionSpacing: CGFloat?
    private let components: Components

    public init(
        sectionSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.sectionSpacing = sectionSpacing
        components = .contentHeaderFooter(content(), header(), footer())
    }

    public init(
        sectionSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header,
    ) where Footer == EmptyView {
        self.sectionSpacing = sectionSpacing
        components = .contentHeader(content(), header())
    }

    public init(
        sectionSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer,
    ) where Header == EmptyView {
        self.sectionSpacing = sectionSpacing
        components = .contentFooter(content(), footer())
    }

    public init(
        sectionSpacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content,
    ) where Footer == EmptyView, Header == EmptyView {
        self.sectionSpacing = sectionSpacing
        components = .content(content())
    }

    private var footerExtraTopPadding: CGFloat = 4

    @ViewBuilder
    public var body: some View {
        if #available(iOS 17, *), let sectionSpacing {
            section
                .listSectionSpacing(sectionSpacing)
        } else {
            section
        }
    }

    @ViewBuilder
    private var section: some View {
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
                    .padding(.top, footerExtraTopPadding)
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
                    .padding(.top, footerExtraTopPadding)
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
            if #available(iOS 26, *) {
                content
                    .font(.headline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .provideScrollAnchor(correction: 4)
            } else {
                content
                    .listRowInsets(.init(top: 12, leading: 8, bottom: 10, trailing: 8))
                    .textCase(.none)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .provideScrollAnchor(correction: 4)
            }
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

        Text(verbatim: "Not in a section")
    }
}
