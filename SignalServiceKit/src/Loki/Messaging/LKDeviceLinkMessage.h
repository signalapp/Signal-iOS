#import "TSOutgoingMessage.h"

typedef NS_ENUM(NSUInteger, LKDeviceLinkMessageKind) {
    LKDeviceLinkMessageKindRequest = 1,
    LKDeviceLinkMessageKindAuthorization = 2,
    LKDeviceLinkMessageKindRevocation = 3
};

NS_SWIFT_NAME(DeviceLinkMessage)
@interface LKDeviceLinkMessage : TSOutgoingMessage

@property (nonatomic, readonly) NSString *masterHexEncodedPublicKey;
@property (nonatomic, readonly) NSString *slaveHexEncodedPublicKey;
@property (nonatomic, readonly) NSData *masterSignature; // nil for device linking requests
@property (nonatomic, readonly) NSData *slaveSignature;
@property (nonatomic, readonly) LKDeviceLinkMessageKind kind;

- (instancetype)initInThread:(TSThread *)thread masterHexEncodedPublicKey:(NSString *)masterHexEncodedPublicKey slaveHexEncodedPublicKey:(NSString *)slaveHexEncodedPublicKey
    masterSignature:(NSData *)masterSignature slaveSignature:(NSData *)slaveSignature kind:(LKDeviceLinkMessageKind)kind;

@end
