//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum OrchestratingSVRAuthCredential: Equatable {
    case kbsOnly(KBSAuthCredential)
    case svr2Only(SVR2AuthCredential)
    case both(KBSAuthCredential, SVR2AuthCredential)

    public static func from(kbs: KBSAuthCredential?, svr2: SVR2AuthCredential?) -> Self? {
        if let kbs, let svr2 {
            return .both(kbs, svr2)
        } else if let kbs {
            return .kbsOnly(kbs)
        } else if let svr2 {
            return .svr2Only(svr2)
        } else {
            return nil
        }
    }

    public var kbs: KBSAuthCredential? {
        switch self {
        case .kbsOnly(let kBSAuthCredential):
            return kBSAuthCredential
        case .svr2Only:
            return nil
        case .both(let kBSAuthCredential, _):
            return kBSAuthCredential
        }
    }

    public var svr2: SVR2AuthCredential? {
        switch self {
        case .kbsOnly:
            return nil
        case .svr2Only(let sVR2AuthCredential):
            return sVR2AuthCredential
        case .both(_, let sVR2AuthCredential):
            return sVR2AuthCredential
        }
    }
}
