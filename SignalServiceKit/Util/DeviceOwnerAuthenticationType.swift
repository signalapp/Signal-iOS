//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LocalAuthentication

public enum DeviceOwnerAuthenticationType {
    case unknown, passcode, faceId, touchId, opticId
}

extension DeviceOwnerAuthenticationType {
    public static func localAuthenticationContext() -> LAContext {
        let context = LAContext()

        // Never recycle biometric auth.
        context.touchIDAuthenticationAllowableReuseDuration = TimeInterval(0)

        assert(!context.interactionNotAllowed)

        return context
    }

    /// > Important: Do not call this in the reply block of the ``LocalAuthentication/LAContext/evaluatePolicy(_:localizedReason:reply:)`` method because that might lead to a deadlock.
    public static var current: Self {
        let context = localAuthenticationContext()

        // the return value of this doesn't matter; the docs on LAContext.biometryType specify this has to be called first though
        context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)

        switch context.biometryType {
        case .none:
            return .passcode
        case .faceID:
            return .faceId
        case .touchID:
            return .touchId
        case .opticID:
            return .opticId
        @unknown default:
            return .unknown
        }
    }
}
