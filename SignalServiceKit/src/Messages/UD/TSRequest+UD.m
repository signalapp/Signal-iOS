//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSRequest+UD.h"
#import <SignalCoreKit/NSData+OWS.h>
#import <SignalMetadataKit/SignalMetadataKit-Swift.h>

@implementation TSRequest (UD)

- (void)useUDAuth:(SMKUDAccessKey *)udAccessKey
{
    OWSAssertDebug(udAccessKey);

    // Suppress normal auth headers.
    self.shouldHaveAuthorizationHeaders = NO;
    // Add UD auth header.
    [self setValue:[udAccessKey.keyData base64EncodedString] forHTTPHeaderField:@"Unidentified-Access-Key"];
}

@end
