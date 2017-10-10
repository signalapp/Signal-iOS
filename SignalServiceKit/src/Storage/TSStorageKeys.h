//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#ifndef TextSecureKit_TSStorageKeys_h
#define TextSecureKit_TSStorageKeys_h

/**
 *  Preferences exposed to the user
 */

#pragma mark User Preferences

#define TSStorageUserPreferencesCollection @"TSStorageUserPreferencesCollection"


/**
 *  Internal settings of the application, not exposed to the user.
 */

#pragma mark Internal Settings

#define TSStorageInternalSettingsCollection @"TSStorageInternalSettingsCollection"
#define TSStorageInternalSettingsVersion @"TSLastLaunchedVersion"

#endif
