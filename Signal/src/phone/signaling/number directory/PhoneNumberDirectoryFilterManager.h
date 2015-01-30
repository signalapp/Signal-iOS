#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "PhoneNumberDirectoryFilter.h"

/**
 *
 * PhoneNumberDirectoryFilterManager is responsible for periodically downloading the latest
 * bloom filter containing phone numbers considered to have RedPhone support.
 *
 */
@interface PhoneNumberDirectoryFilterManager : NSObject {
@private PhoneNumberDirectoryFilter* phoneNumberDirectoryFilter;
@private TOCCancelToken* lifetimeToken;
}

-(void) forceUpdate;
-(void) startUntilCancelled:(TOCCancelToken*)cancelToken;
-(PhoneNumberDirectoryFilter*) getCurrentFilter;

@property BOOL isRefreshing;

@end
