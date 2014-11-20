#import <Foundation/Foundation.h>

/**
 *
 * Instances of UnrecognizedRequestFailure are used to indicate that a request could not be handled due to being strange.
 *
 */
@interface UnrecognizedRequestFailure : NSObject

- (instancetype)initWithReason:(NSString*)reason;

@end
