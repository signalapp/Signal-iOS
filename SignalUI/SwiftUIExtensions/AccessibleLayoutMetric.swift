//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SwiftUI

/// A value that is automatically scaled down at accessibility dynamic type sizes.
///
/// This is similar to SwiftUI's `ScaledMetric`, which is designed to scale values
/// *up*, proportionally with dynamic type size. `AccessibleLayoutMetric` is instead
/// designed to make more space for content by tightening up spacing metrics at
/// large dynamic type sizes.
///
/// ```swift
/// struct ContentView: View {
///   // Automatically scales down to 67% at accessibility dynamic type sizes.
///   @AccessibleLayoutMetric private var rowSpacing = 24
///
///   // The scale used at accessibility sizes can be customized.
///   @AccessibleLayoutMetric(scale: 0.5) private var viewPadding = 24
///
///   var body: some View {
///     VStack(spacing: spacing) {
///       Text("Moderately long text")
///       Text("Very long text…")
///     }
///     .padding(.horizontal, viewPadding)
///   }
/// }
/// ```
@propertyWrapper
public struct AccessibleLayoutMetric<Value: BinaryFloatingPoint>: DynamicProperty {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let accessibilityScale: Value

    public let rawValue: Value
    public private(set) var wrappedValue: Value

    public init(wrappedValue: Value, scale: Value = 0.67) {
        self.accessibilityScale = scale
        self.rawValue = wrappedValue
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: Self {
        self
    }

    public mutating func update() {
        let scale = dynamicTypeSize.isAccessibilitySize ? accessibilityScale : 1.0
        wrappedValue = rawValue * scale
    }
}
