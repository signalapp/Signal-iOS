#import <Foundation/Foundation.h>

/**
 *
 * Instances of IgnoredPacketFailure are used to indicate that a packet was ignored.
 *
 */
@interface IgnoredPacketFailure : NSObject

- (instancetype)initWithReason:(NSString*)reason;

@end
