#if !defined(__has_feature) || !__has_feature(objc_arc)
#error "This file requires ARC support."
#endif

// Copyright 2012, Google Inc.
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//     * Redistributions of source code must retain the above copyright
// notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
// copyright notice, this list of conditions and the following disclaimer
// in the documentation and/or other materials provided with the
// distribution.
//     * Neither the name of Google Inc. nor the names of its
// contributors may be used to endorse or promote products derived from
// this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#import <UIKit/UIKit.h>

#import "OpenInChromeController.h"

static NSString * const kGoogleChromeHTTPScheme = @"googlechrome:";
static NSString * const kGoogleChromeHTTPSScheme = @"googlechromes:";
static NSString * const kGoogleChromeCallbackScheme =
    @"googlechrome-x-callback:";

// Name of the shared UIPasteboard used to store the Chrome preferences.
static NSString * const kChromePasteboardName =
    @"com.google.preferences.chrome";

// Key of the OpenInChrome preference.
static NSString * const kOpenInChromePreferenceKey =
    @"com.google.preferences.chrome.openinchrome";

// Name of the shared UIPasteboard representation type.
static NSString * const kPasteboardType = @"com.google.data";

// Key for the Data content of the pasteboard.
static NSString * const kDataDictionaryKey = @"Data";

// String for the version key in the main dictionary.
static NSString * const kVersionKey = @"Version-1";

static NSString * encodeByAddingPercentEscapes(NSString *input) {
  NSString *encodedValue =
      (NSString *)CFBridgingRelease(CFURLCreateStringByAddingPercentEscapes(
          kCFAllocatorDefault,
          (CFStringRef)input,
          NULL,
          (CFStringRef)@"!*'();:@&=+$,/?%#[]",
          kCFStringEncodingUTF8));
  return encodedValue;
}

@implementation OpenInChromeController

+ (OpenInChromeController *)sharedInstance {
  static OpenInChromeController *sharedInstance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (BOOL)isChromeInstalled {
  NSURL *simpleURL = [NSURL URLWithString:kGoogleChromeHTTPScheme];
  NSURL *callbackURL = [NSURL URLWithString:kGoogleChromeCallbackScheme];
  return  [[UIApplication sharedApplication] canOpenURL:simpleURL] ||
      [[UIApplication sharedApplication] canOpenURL:callbackURL];
}

- (BOOL)openInChrome:(NSURL *)url {
  return [self openInChrome:url withCallbackURL:nil createNewTab:NO];
}

- (BOOL)openInChrome:(NSURL *)url
     withCallbackURL:(NSURL *)callbackURL
        createNewTab:(BOOL)createNewTab {
  NSURL *chromeSimpleURL = [NSURL URLWithString:kGoogleChromeHTTPScheme];
  NSURL *chromeCallbackURL = [NSURL URLWithString:kGoogleChromeCallbackScheme];
  if ([[UIApplication sharedApplication] canOpenURL:chromeCallbackURL]) {
    NSString *appName =
        [[NSBundle mainBundle]
            objectForInfoDictionaryKey:@"CFBundleDisplayName"];

    NSString *scheme = [url.scheme lowercaseString];

    // Proceed only if scheme is http or https.
    if ([scheme isEqualToString:@"http"] ||
        [scheme isEqualToString:@"https"]) {

      NSMutableString *chromeURLString = [NSMutableString string];
      [chromeURLString appendFormat:
          @"%@//x-callback-url/open/?x-source=%@&url=%@",
          kGoogleChromeCallbackScheme,
          encodeByAddingPercentEscapes(appName),
          encodeByAddingPercentEscapes([url absoluteString])];
      if (callbackURL) {
        [chromeURLString appendFormat:@"&x-success=%@",
            encodeByAddingPercentEscapes([callbackURL absoluteString])];
      }
      if (createNewTab) {
        [chromeURLString appendString:@"&create-new-tab"];
      }

      NSURL *chromeURL = [NSURL URLWithString:chromeURLString];

      // Open the URL with Google Chrome.
      return [[UIApplication sharedApplication] openURL:chromeURL];
    }
  } else if ([[UIApplication sharedApplication] canOpenURL:chromeSimpleURL]) {
    NSString *scheme = [url.scheme lowercaseString];

    // Replace the URL Scheme with the Chrome equivalent.
    NSString *chromeScheme = nil;
    if ([scheme isEqualToString:@"http"]) {
      chromeScheme = kGoogleChromeHTTPScheme;
    } else if ([scheme isEqualToString:@"https"]) {
      chromeScheme = kGoogleChromeHTTPSScheme;
    }

    // Proceed only if a valid Google Chrome URI Scheme is available.
    if (chromeScheme) {
      NSString *absoluteString = [url absoluteString];
      NSRange rangeForScheme = [absoluteString rangeOfString:@":"];
      NSString *urlNoScheme =
          [absoluteString substringFromIndex:rangeForScheme.location + 1];
      NSString *chromeURLString =
          [chromeScheme stringByAppendingString:urlNoScheme];
      NSURL *chromeURL = [NSURL URLWithString:chromeURLString];

      // Open the URL with Google Chrome.
      return [[UIApplication sharedApplication] openURL:chromeURL];
    }
  }
  return NO;
}

- (OpenInChromePreference)openInChromePreference {
  NSDictionary *pasteboardContent = [self pasteboardContent];
  NSDictionary *pasteboardData =
      [pasteboardContent objectForKey:kDataDictionaryKey];
  NSDictionary *userPreferences =
      [pasteboardData objectForKey:kVersionKey];
  NSNumber *value =
      [userPreferences objectForKey:kOpenInChromePreferenceKey];
  return value ? (OpenInChromePreference)[value integerValue]
               : kOpenInChromeNone;
}

#pragma mark - Private methods

- (NSDictionary *)pasteboardContent {
  UIPasteboard *pasteboard =
      [UIPasteboard pasteboardWithName:kChromePasteboardName
                                create:NO];

  NSData *data = [pasteboard dataForPasteboardType:kPasteboardType];
  id pasteboardContent = nil;
  if (data) {
    pasteboardContent =
        [NSPropertyListSerialization propertyListWithData:data
                                                  options:0
                                                   format:nil
                                                    error:nil];
  }
  if ([pasteboardContent isKindOfClass:[NSDictionary class]]) {
    return (NSDictionary *)pasteboardContent;
  }

  return nil;
}


@end
