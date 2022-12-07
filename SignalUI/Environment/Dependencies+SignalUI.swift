//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var audioSession: AudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    static var audioSession: AudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    final var contactsViewHelper: ContactsViewHelper {
        SUIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        SUIEnvironment.shared.contactsViewHelperRef
    }

    final var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

    var chatColors: ChatColors {
        SUIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        SUIEnvironment.shared.chatColorsRef
    }

    var payments: Payments {
        SUIEnvironment.shared.paymentsRef
    }

    static var payments: Payments {
        SUIEnvironment.shared.paymentsRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var audioSession: AudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    static var audioSession: AudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    var contactsViewHelper: ContactsViewHelper {
        SUIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        SUIEnvironment.shared.contactsViewHelperRef
    }

    var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

    var chatColors: ChatColors {
        SUIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        SUIEnvironment.shared.chatColorsRef
    }

    var payments: Payments {
        SUIEnvironment.shared.paymentsRef
    }

    static var payments: Payments {
        SUIEnvironment.shared.paymentsRef
    }
}

// MARK: - Swift-only Dependencies

public extension NSObject {

    final var paymentsSwift: PaymentsSwift {
        SUIEnvironment.shared.paymentsRef as! PaymentsSwift
    }

    static var paymentsSwift: PaymentsSwift {
        SUIEnvironment.shared.paymentsRef as! PaymentsSwift
    }

    final var paymentsImpl: PaymentsImpl {
        SUIEnvironment.shared.paymentsRef as! PaymentsImpl
    }

    static var paymentsImpl: PaymentsImpl {
        SUIEnvironment.shared.paymentsRef as! PaymentsImpl
    }
}

// MARK: - Swift-only Dependencies

public extension Dependencies {

    var paymentsSwift: PaymentsSwift {
        SUIEnvironment.shared.paymentsRef as! PaymentsSwift
    }

    static var paymentsSwift: PaymentsSwift {
        SUIEnvironment.shared.paymentsRef as! PaymentsSwift
    }

    var paymentsImpl: PaymentsImpl {
        SUIEnvironment.shared.paymentsRef as! PaymentsImpl
    }

    static var paymentsImpl: PaymentsImpl {
        SUIEnvironment.shared.paymentsRef as! PaymentsImpl
    }
}
