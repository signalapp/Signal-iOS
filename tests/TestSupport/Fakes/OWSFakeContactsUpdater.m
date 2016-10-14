//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeContactsUpdater.h"
#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeContactsUpdater

- (SignalRecipient *)synchronousLookup:(NSString *)identifier error:(NSError **)error
{
    NSLog(@"[OWSFakeContactsUpdater] Faking contact lookup.");
    return [[SignalRecipient alloc] initWithTextSecureIdentifier:@"fake-recipient-id" relay:nil supportsVoice:YES];
}

@end

NS_ASSUME_NONNULL_END
