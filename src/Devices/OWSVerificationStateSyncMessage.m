//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateSyncMessage.h"
#import "Cryptography.h"
#import "OWSIdentityManager.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark -

@interface OWSVerificationStateSyncMessage ()

@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) NSData *identityKey;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage

- (instancetype)initWithVerificationState:(OWSVerificationState)verificationState
                              identityKey:(NSData *)identityKey
               verificationForRecipientId:(NSString *)verificationForRecipientId
{

    OWSAssert(identityKey.length == kIdentityKeyLength);
    OWSAssert(verificationForRecipientId.length > 0);
    // we only sync user's marking as un/verified. Never sync the conflicted state, the sibling device
    // will figure that out on it's own.
    OWSAssert(verificationState != OWSVerificationStateNoLongerVerified);

    self = [super init];
    if (!self) {
        return self;
    }

    _verificationState = verificationState;
    _identityKey = identityKey;
    _verificationForRecipientId = verificationForRecipientId;
    
    // This sync message should be 1-512 bytes longer than the corresponding NullMessage
    // we store this values so the corresponding NullMessage can subtract it from the total length.
    _paddingBytesLength = arc4random_uniform(512) + 1;

    return self;
}

- (OWSSignalServiceProtosSyncMessageBuilder *)syncMessageBuilder
{
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];

    OWSSignalServiceProtosVerifiedBuilder *verifiedBuilder = [OWSSignalServiceProtosVerifiedBuilder new];
    verifiedBuilder.destination = self.verificationForRecipientId;
    verifiedBuilder.identityKey = self.identityKey;
    verifiedBuilder.state = OWSVerificationStateToProtoState(self.verificationState);

    OWSAssert(self.paddingBytesLength != 0);
    verifiedBuilder.nullMessage = [Cryptography generateRandomBytes:self.paddingBytesLength];
    
    syncMessageBuilder.verifiedBuilder = verifiedBuilder;
    
    return syncMessageBuilder;
}

@end

NS_ASSUME_NONNULL_END
