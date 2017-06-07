//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSVerificationStateSyncMessage.h"
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
        OWSSignalServiceProtosSyncMessageVerificationBuilder *verificationBuilder = [OWSSignalServiceProtosSyncMessageVerificationBuilder new];
        verificationBuilder.destination = tuple.recipientId;
        verificationBuilder.identityKey = tuple.identityKey;
        switch (tuple.verificationState) {
            case OWSVerificationStateDefault:
                verificationBuilder.state = OWSSignalServiceProtosSyncMessageVerificationStateDefault;
                break;
            case OWSVerificationStateVerified:
                verificationBuilder.state = OWSSignalServiceProtosSyncMessageVerificationStateVerified;
                break;
            case OWSVerificationStateNoLongerVerified:
                verificationBuilder.state = OWSSignalServiceProtosSyncMessageVerificationStateNoLongerVerified;
                break;
        }
        [syncMessageBuilder addVerification:[verificationBuilder build]];
    }
    
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
