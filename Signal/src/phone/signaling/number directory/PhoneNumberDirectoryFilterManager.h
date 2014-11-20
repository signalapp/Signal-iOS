#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "PhoneNumberDirectoryFilter.h"

/**
 *
 * PhoneNumberDirectoryFilterManager is responsible for periodically downloading the latest
 * bloom filter containing phone numbers considered to have RedPhone support.
 *
 */
@interface PhoneNumberDirectoryFilterManager : NSObject

- (instancetype)init;

- (void)forceUpdate;
- (void)startUntilCancelled:(TOCCancelToken*)cancelToken;
- (PhoneNumberDirectoryFilter*)getCurrentFilter;

@end
