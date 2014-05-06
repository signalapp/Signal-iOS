#import <Foundation/Foundation.h>
#import "SignalUtil.h"
#import "CancelToken.h"

/**
 *
 * PhoneNumberDirectoryFilterManager is responsible for periodically downloading the latest
 * bloom filter containing phone numbers considered to have RedPhone support.
 *
 */
@interface PhoneNumberDirectoryFilterManager : NSObject {
@private PhoneNumberDirectoryFilter* phoneNumberDirectoryFilter;
@private id<CancelToken> lifetimeToken;
}

-(void) forceUpdate;
-(void) startUntilCancelled:(id<CancelToken>)cancelToken;
-(PhoneNumberDirectoryFilter*) getCurrentFilter;

@end
