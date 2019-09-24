#import "TSOutgoingMessage.h"

NS_SWIFT_NAME(DeviceLinkingMessage)
@interface LKDeviceLinkingMessage : TSOutgoingMessage

@property (nonatomic, readonly) NSString *masterHexEncodedPublicKey;
@property (nonatomic, readonly) NSString *slaveHexEncodedPublicKey;
@property (nonatomic, readonly) NSData *masterSignature; // nil for device linking requests
@property (nonatomic, readonly) NSData *slaveSignature;

- (instancetype)initInThread:(TSThread *)thread masterHexEncodedPublicKey:(NSString *)masterHexEncodedPublicKey slaveHexEncodedPublicKey:(NSString *)slaveHexEncodedPublicKey masterSignature:(NSData *)masterSignature slaveSignature:(NSData *)slaveSignature;

@end
