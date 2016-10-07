//  Created by Michael Kirk on 10/7/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSFakeContactsUpdater.h"
#import "SignalRecipient.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSFakeContactsUpdater

- (void)synchronousLookup:(NSString *)identifier
                  success:(void (^)(SignalRecipient *))success
                  failure:(void (^)(NSError *error))failure
{
    NSLog(@"[OWSFakeContactsUpdater] Faking contact lookup.");
    SignalRecipient *fakeRecipient =
        [[SignalRecipient alloc] initWithTextSecureIdentifier:@"fake-recipient-id" relay:nil supportsVoice:YES];
    success(fakeRecipient);
}

@end

NS_ASSUME_NONNULL_END
