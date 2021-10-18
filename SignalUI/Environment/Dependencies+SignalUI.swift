//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// MARK: - NSObject

@objc
public extension NSObject {
    final var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    final var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    final var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

    final var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    static var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }
}

// MARK: - Obj-C Dependencies

public extension Dependencies {
    var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    static var audioSession: OWSAudioSession {
        UIEnvironment.shared.audioSessionRef
    }

    var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    static var contactsViewHelper: ContactsViewHelper {
        UIEnvironment.shared.contactsViewHelperRef
    }

    var fullTextSearcher: FullTextSearcher { .shared }

    static var fullTextSearcher: FullTextSearcher { .shared }

    var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    static var windowManager: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }

    var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }

    static var chatColors: ChatColors {
        UIEnvironment.shared.chatColorsRef
    }
}

// MARK: - Swift-only Dependencies

public extension NSObject {
}

// MARK: - Swift-only Dependencies

public extension Dependencies {
}

 // MARK: -

 @objc
 public extension OWSWindowManager {
    static var shared: OWSWindowManager {
        UIEnvironment.shared.windowManagerRef
    }
 }
