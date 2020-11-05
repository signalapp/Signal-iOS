//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <Availability.h>

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(major, minor) \
    ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){.majorVersion = major, .minorVersion = minor, .patchVersion = 0}])
