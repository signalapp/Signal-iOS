
#import "LKEphemeralMessage.h"

NS_ASSUME_NONNULL_BEGIN

NS_SWIFT_NAME(LokiAddressMessage)
@interface LKAddressMessage : LKEphemeralMessage

- (instancetype)initInThread:(nullable TSThread *)thread
                     address:(NSString *)address
                        port:(uint)port
                      isPing:(BOOL)isPing;

@property (nonatomic, readonly) NSString *address;
@property (nonatomic, readonly) uint port;
@property (nonatomic, readonly) BOOL isPing;

@end

NS_ASSUME_NONNULL_END
