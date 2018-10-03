//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSInvalidIdentityKeySendingErrorMessage.h"
#import "OWSFingerprint.h"
#import "OWSIdentityManager.h"
#import "OWSPrimaryStorage+SessionStore.h"
#import "OWSPrimaryStorage.h"
#import "PreKeyBundle+jsonDict.h"
#import "TSContactThread.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSOutgoingMessage.h"
#import <AxolotlKit/NSData+keyVersionByte.h>

NS_ASSUME_NONNULL_BEGIN

NSString *TSInvalidPreKeyBundleKey = @"TSInvalidPreKeyBundleKey";
NSString *TSInvalidRecipientKey = @"TSInvalidRecipientKey";

@interface TSInvalidIdentityKeySendingErrorMessage ()

@property (nonatomic, readonly) PreKeyBundle *preKeyBundle;

@end

// DEPRECATED - we no longer create new instances of this class (as of  mid-2017); However, existing instances may
// exist, so we should keep this class around to honor their old behavior.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation TSInvalidIdentityKeySendingErrorMessage
#pragma clang diagnostic pop

- (void)throws_acceptNewIdentityKey
{
    // Shouldn't really get here, since we're no longer creating blocking SN changes.
    // But there may still be some old unaccepted SN errors in the wild that need to be accepted.
    OWSFailDebug(@"accepting new identity key is deprecated.");

    NSData *_Nullable newIdentityKey = [self throws_newIdentityKey];
    if (!newIdentityKey) {
        OWSFailDebug(@"newIdentityKey is unexpectedly nil. Bad Prekey bundle?: %@", self.preKeyBundle);
        return;
    }

    [[OWSIdentityManager sharedManager] saveRemoteIdentity:newIdentityKey recipientId:self.recipientId];
}

- (nullable NSData *)throws_newIdentityKey
{
    return [self.preKeyBundle.identityKey throws_removeKeyType];
}

- (NSString *)theirSignalId
{
    return self.recipientId;
}

@end

NS_ASSUME_NONNULL_END
