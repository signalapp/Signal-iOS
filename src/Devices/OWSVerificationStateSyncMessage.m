//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateSyncMessage.h"
#import "Cryptography.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSVerificationStateTuple : NSObject

@property (nonatomic) OWSVerificationState verificationState;
@property (nonatomic) NSData *identityKey;
@property (nonatomic) NSString *recipientId;

@end

#pragma mark -

@implementation OWSVerificationStateTuple

@end

#pragma mark -

@interface OWSVerificationStateSyncMessage ()

@property (nonatomic, readonly) NSMutableArray<OWSVerificationStateTuple *> *tuples;

@end

#pragma mark -

@implementation OWSVerificationStateSyncMessage

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }
    
    _tuples = [NSMutableArray new];
    
    return self;
}

- (void)addVerificationState:(OWSVerificationState)verificationState
                 identityKey:(NSData *)identityKey
                 recipientId:(NSString *)recipientId
{
    OWSAssert(identityKey.length > 0);
    OWSAssert(recipientId.length > 0);
    OWSAssert(self.tuples);

    OWSVerificationStateTuple *tuple = [OWSVerificationStateTuple new];
    tuple.verificationState = verificationState;
    tuple.identityKey = identityKey;
    tuple.recipientId = recipientId;
    [self.tuples addObject:tuple];
}

- (OWSSignalServiceProtosSyncMessage *)buildSyncMessage
{
    OWSAssert(self.tuples.count > 0);
    
    OWSSignalServiceProtosSyncMessageBuilder *syncMessageBuilder = [OWSSignalServiceProtosSyncMessageBuilder new];
    for (OWSVerificationStateTuple *tuple in self.tuples) {
        OWSSignalServiceProtosSyncMessageVerifiedBuilder *verifiedBuilder = [OWSSignalServiceProtosSyncMessageVerifiedBuilder new];
        verifiedBuilder.destination = tuple.recipientId;
        verifiedBuilder.identityKey = tuple.identityKey;
        switch (tuple.verificationState) {
            case OWSVerificationStateDefault:
                verifiedBuilder.state = OWSSignalServiceProtosSyncMessageVerifiedStateDefault;
                break;
            case OWSVerificationStateVerified:
                verifiedBuilder.state = OWSSignalServiceProtosSyncMessageVerifiedStateVerified;
                break;
            case OWSVerificationStateNoLongerVerified:
                verifiedBuilder.state = OWSSignalServiceProtosSyncMessageVerifiedStateUnverified;
                break;
        }
        [syncMessageBuilder addVerified:[verifiedBuilder build]];
    }

    // Add 1-512 bytes of random padding bytes.
    size_t paddingLengthBytes = arc4random_uniform(512) + 1;
    [syncMessageBuilder setPadding:[Cryptography generateRandomBytes:paddingLengthBytes]];

    return [syncMessageBuilder build];
}

- (NSArray<NSString *> *)recipientIds
{
    NSMutableArray<NSString *> *result = [NSMutableArray new];
    for (OWSVerificationStateTuple *tuple in self.tuples) {
        OWSAssert(tuple.recipientId.length > 0);
        [result addObject:tuple.recipientId];
    }

    return [result copy];
}

@end

NS_ASSUME_NONNULL_END
