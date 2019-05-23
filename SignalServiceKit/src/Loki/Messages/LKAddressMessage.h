
#import "LKEphemeralMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(LokiAddressMessage)
@interface LKAddressMessage : LKEphemeralMessage

- (instancetype)initInThread:(nullable TSThread *)thread
                                   address:(NSString *)address
                                      port:(uint)port;

@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) uint port;

@end

NS_ASSUME_NONNULL_END
