//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateSyncMessage.h"
#import "Cryptography.h"
#import "OWSIdentityManager.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

//@interface OWSVerificationStateTuple : NSObject
//
//@property (nonatomic) OWSVerificationState verificationState;
//@property (nonatomic) NSData *identityKey;
//@property (nonatomic) NSString *recipientId;
//
//@end
//
//#pragma mark -
//
//@implementation OWSVerificationStateTuple
//
//@end

#pragma mark -

@interface OWSVerificationStateSyncMessage ()

//@property (nonatomic, readonly) NSMutableArray<OWSVerificationStateTuple *> *tuples;
@property (nonatomic, readonly) OWSVerificationState verificationState;
@property (nonatomic, readonly) NSData *identityKey;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage
//
//- (instancetype)init
//{
//    self = [super init];
//    if (!self) {
//        return self;
//    }
//
//    _tuples = [NSMutableArray new];
//
//    return self;
//}

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

    return self;
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    //    OWSAssert(self.tuples.count > 0);

    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];

    //    for (OWSVerificationStateTuple *tuple in self.tuples) {
    //        OWSSignalServiceProtosVerifiedBuilder *verifiedBuilder = [OWSSignalServiceProtosVerifiedBuilder new];
    //        verifiedBuilder.destination = tuple.recipientId;
    //        verifiedBuilder.identityKey = tuple.identityKey;
    //        switch (tuple.verificationState) {
    //            case OWSVerificationStateDefault:
    //                verifiedBuilder.state = OWSSignalServiceProtosVerifiedStateDefault;
    //                break;
    //            case OWSVerificationStateVerified:
    //                verifiedBuilder.state = OWSSignalServiceProtosVerifiedStateVerified;
    //                break;
    //            case OWSVerificationStateNoLongerVerified:
    //                verifiedBuilder.state = OWSSignalServiceProtosVerifiedStateUnverified;
    //                break;
    //        }
    //        [syncMessageBuilder addVerified:[verifiedBuilder build]];
    //    }
    //

    OWSSignalServiceProtosVerifiedBuilder *verifiedBuilder = [OWSSignalServiceProtosVerifiedBuilder new];
    verifiedBuilder.destination = self.verificationForRecipientId;
    verifiedBuilder.identityKey = self.identityKey;
    verifiedBuilder.state = ^{
        switch (self.verificationState) {
            case OWSVerificationStateDefault:
                return OWSSignalServiceProtosVerifiedStateDefault;
            case OWSVerificationStateVerified:
                return OWSSignalServiceProtosVerifiedStateVerified;
            case OWSVerificationStateNoLongerVerified:
                return OWSSignalServiceProtosVerifiedStateUnverified;
        }
    }();

    // Add 1-512 bytes of random padding bytes.
    size_t paddingLengthBytes = arc4random_uniform(512) + 1;
    syncMessageBuilder.padding = [Cryptography generateRandomBytes:paddingLengthBytes];

    return [syncMessageBuilder build];
}

//- (NSArray<NSString *> *)recipientIds
//{
//    NSMutableArray<NSString *> *result = [NSMutableArray new];
//    for (OWSVerificationStateTuple *tuple in self.tuples) {
//        OWSAssert(tuple.recipientId.length > 0);
//        [result addObject:tuple.recipientId];
//    }
//
//    return [result copy];
//}

@end

NS_ASSUME_NONNULL_END
