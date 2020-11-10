#import "TSOutgoingMessage.h"

typedef NS_ENUM(NSUInteger, LKDeviceLinkMessageKind) {
    LKDeviceLinkMessageKindRequest = 1,
    LKDeviceLinkMessageKindAuthorization = 2,
};

NS_SWIFT_NAME(DeviceLinkMessage)
@interface LKDeviceLinkMessage : TSOutgoingMessage

@property (nonatomic, readonly) NSString *masterPublicKey;
@property (nonatomic, readonly) NSString *slavePublicKey;
@property (nonatomic, readonly) NSData *masterSignature; // nil for device linking requests
@property (nonatomic, readonly) NSData *slaveSignature;
@property (nonatomic, readonly) LKDeviceLinkMessageKind kind;

- (instancetype)initInThread:(TSThread *)thread masterPublicKey:(NSString *)masterHexEncodedPublicKey slavePublicKey:(NSString *)slaveHexEncodedPublicKey masterSignature:(NSData * _Nullable)masterSignature slaveSignature:(NSData *)slaveSignature;

@end
