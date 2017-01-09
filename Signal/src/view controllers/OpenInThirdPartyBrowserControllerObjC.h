/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import <Foundation/Foundation.h>

typedef enum {
    ThirdPartyBrowserBrave,
    ThirdPartyBrowserFirefox
} ThirdPartyBrowser;

// This class is used to check if Firefox is installed in the system and
// to open a URL in Firefox either with or without a callback URL.
@interface OpenInThirdPartyBrowserControllerObjC : NSObject 

-(instancetype)initWithBrowser:(ThirdPartyBrowser)browser NS_DESIGNATED_INITIALIZER;

// Returns YES if Firefox is installed in the user's system.
- (BOOL)isInstalled;

// Opens a URL in Firefox.
- (BOOL)openInBrowser:(NSURL *)url;

@end
