#import <Foundation/Foundation.h>
#import "CancelToken.h"

/**
 *
 * A cancel token that has already been cancelled.
 *
 */
@interface CancelledToken : NSObject<CancelToken>
+(CancelledToken*) cancelledToken;
@end
