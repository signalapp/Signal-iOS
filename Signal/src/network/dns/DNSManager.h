#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "IPAddress.h"

/**
 *
 * DNSManager implements utility methods for querying the addresses/CName associated with a domain name.
 *
 **/

@interface DNSManager : NSObject

@property (strong, nonatomic) TOCFutureSource* futureResultSource;

/// Result has type Future(Array(IPAddress))
+ (TOCFuture*)asyncQueryAddressesForDomainName:(NSString*)domainName
                               unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

@end
