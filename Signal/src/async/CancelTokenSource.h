#import <Foundation/Foundation.h>
#import "CancelToken.h"

@class CancelTokenSourceToken;

/**
 *
 * CancelTokenSource is used to create and manage cancel tokens.
 *
 */
@interface CancelTokenSource : NSObject {
@private CancelTokenSourceToken* token;
}

+(CancelTokenSource*) cancelTokenSource;
-(void) cancel;
-(id<CancelToken>) getToken;

@end
