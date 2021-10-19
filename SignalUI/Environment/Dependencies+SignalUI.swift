//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var audioSession: OWSAudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
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
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var audioSession: OWSAudioSession {
        SUIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
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
}

// MARK: - Swift-only Dependencies

public extension NSObject {
}

// MARK: - Swift-only Dependencies

public extension Dependencies {
}
