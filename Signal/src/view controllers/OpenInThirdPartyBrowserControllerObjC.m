/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import <UIKit/UIKit.h>
#import "OpenInThirdPartyBrowserControllerObjC.h"

static NSString *const firefoxScheme = @"firefox:";

@interface OpenInThirdPartyBrowserControllerObjC()
@property NSString *scheme;
@end

@implementation OpenInThirdPartyBrowserControllerObjC

// Custom function that does complete percent escape for constructing the URL.
static NSString *encodeByAddingPercentEscapes(NSString *string) {
    NSString *encodedString = (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
    kCFAllocatorDefault,
    (CFStringRef)string,
    NULL,
    (CFStringRef)@"!*'();:@&=+$,/?%#[]",
    kCFStringEncodingUTF8));
    return encodedString;
}

-(instancetype)initWithBrowser:(ThirdPartyBrowser)browser
{
    if (self = [super init]) {
        switch (browser) {
            case ThirdPartyBrowserBrave:
                self.scheme = @"brave://";
                break;
            case ThirdPartyBrowserFirefox:
                self.scheme = @"firefox://";
                break;
        }
    }
    return self;
}

- (BOOL)isInstalled {
    NSURL *url = [NSURL URLWithString:self.scheme];
    return [[UIApplication sharedApplication] canOpenURL:url];
}

- (BOOL)openInBrowser:(NSURL *)url {
    if (![self isInstalled]) {
        return NO;
    }

    NSString *scheme = [url.scheme lowercaseString];
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) {
        return NO;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@open-url?url=%@",
                           self.scheme,
                           encodeByAddingPercentEscapes([url absoluteString])];

    // Open the URL with Firefox.
    return [UIApplication.sharedApplication openURL:[NSURL URLWithString: urlString]];
}

@end
