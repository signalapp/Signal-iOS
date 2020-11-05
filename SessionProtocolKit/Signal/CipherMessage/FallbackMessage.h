#import "CipherMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface FallbackMessage : NSObject<CipherMessage>

@property (nonatomic, readonly) NSData *serialized;

- (instancetype)init_throws_withData:(NSData *)serialized;

@end

NS_ASSUME_NONNULL_END
