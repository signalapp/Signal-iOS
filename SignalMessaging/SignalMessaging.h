//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import <UIKit/UIKit.h>

//! Project version number for SignalMessaging.
FOUNDATION_EXPORT double SignalMessagingVersionNumber;

//! Project version string for SignalMessaging.
FOUNDATION_EXPORT const unsigned char SignalMessagingVersionString[];

// The public headers of the framework
#import <SignalMessaging/AFQueryString.h>
#import <SignalMessaging/AppSetup.h>
#import <SignalMessaging/DateUtil.h>
#import <SignalMessaging/DebugLogger.h>
#import <SignalMessaging/Environment.h>
#import <SignalMessaging/OWSContactsManager.h>
#import <SignalMessaging/OWSOrphanDataCleaner.h>
#import <SignalMessaging/OWSPreferences.h>
#import <SignalMessaging/OWSProfileManager.h>
#import <SignalMessaging/OWSScrubbingLogFormatter.h>
#import <SignalMessaging/OWSSounds.h>
#import <SignalMessaging/OWSSyncManager.h>
#import <SignalMessaging/ThreadUtil.h>
#import <SignalMessaging/VersionMigrations.h>
#import <SignalServiceKit/OWSUserProfile.h>
