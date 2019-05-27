#import "LKEphemeralMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(LokiAddressMessage)
@interface LKAddressMessage : LKEphemeralMessage

@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) BOOL isPing;

- (instancetype)initInThread:(nullable TSThread *)thread address:(NSString *)address port:(uint16_t)port isPing:(BOOL)isPing;

@end

NS_ASSUME_NONNULL_END
