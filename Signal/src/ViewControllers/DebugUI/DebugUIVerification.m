//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DebugUIVerification.h"
#import "DebugUIMessages.h"
#import "Signal-Swift.h"
#import <SignalServiceKit/OWSIdentityManager.h>

NS_ASSUME_NONNULL_BEGIN

@implementation DebugUIVerification

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Factory Methods

+ (OWSTableSection *)sectionForThread:(TSContactThread *)thread
{
    OWSAssert(thread);

    NSString *recipientId = thread.contactIdentifier;
    OWSAssert(recipientId.length > 0);

    return [OWSTableSection
        sectionWithTitle:@"Verification"
                   items:@[
                       [OWSTableItem itemWithTitle:@"Default"
                                       actionBlock:^{
                                           [DebugUIVerification setVerificationState:OWSVerificationStateDefault
                                                                         recipientId:recipientId];
                                       }],
                       [OWSTableItem itemWithTitle:@"Verified"
                                       actionBlock:^{
                                           [DebugUIVerification setVerificationState:OWSVerificationStateVerified
                                                                         recipientId:recipientId];
                                       }],
                       [OWSTableItem itemWithTitle:@"No Longer Verified"
                                       actionBlock:^{
                                           [DebugUIVerification
                                               setVerificationState:OWSVerificationStateNoLongerVerified
                                                        recipientId:recipientId];
                                       }],
                   ]];
}

+ (void)setVerificationState:(OWSVerificationState)verificationState recipientId:(NSString *)recipientId
{
    OWSAssert(recipientId.length > 0);

    OWSRecipientIdentity *_Nullable recipientIdentity =
        [[OWSIdentityManager sharedManager] recipientIdentityForRecipientId:recipientId];
    OWSAssert(recipientIdentity);
    // By capturing the identity key when we enter these views, we prevent the edge case
    // where the user verifies a key that we learned about while this view was open.
    NSData *identityKey = recipientIdentity.identityKey;
    OWSAssert(identityKey.length > 0);

    [OWSIdentityManager.sharedManager setVerificationState:verificationState
                                               identityKey:identityKey
                                               recipientId:recipientId
                                           sendSyncMessage:verificationState != OWSVerificationStateNoLongerVerified];
}

@end

NS_ASSUME_NONNULL_END
