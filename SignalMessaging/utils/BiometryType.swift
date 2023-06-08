//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LocalAuthentication

public enum BiometryType {
    case unknown, passcode, faceId, touchId
}

extension BiometryType {
    public static func localAuthenticationContext() -> LAContext {
        let context = LAContext()

        // Never recycle biometric auth.
        context.touchIDAuthenticationAllowableReuseDuration = TimeInterval(0)

        assert(!context.interactionNotAllowed)

        return context
    }

    public static var biometryType: BiometryType {
        let context = localAuthenticationContext()

        switch context.biometryType {
        case .none:
            return .passcode
        case .faceID:
            return .faceId
        case .touchID:
            return .touchId
        @unknown default:
            return .unknown
        }
    }

    public static var validBiometryType: ValidBiometryType? {
        switch biometryType {
        case .unknown:
            return nil
        case .passcode:
            return .passcode
        case .faceId:
            return .faceId
        case .touchId:
            return .touchId
        }
    }
}

public enum ValidBiometryType {
    case passcode, faceId, touchId
}
