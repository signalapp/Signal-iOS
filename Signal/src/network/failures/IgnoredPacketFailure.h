#import <Foundation/Foundation.h>

/**
 *
 * Instances of IgnoredPacketFailure are used to indicate that a packet was ignored.
 *
 */
@interface IgnoredPacketFailure : NSObject {
@private NSString* reason;
}

+(IgnoredPacketFailure*) new:(NSString*)reason;

@end
