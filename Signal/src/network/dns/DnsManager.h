#import <Foundation/Foundation.h>
#import "CollapsingFutures.h"
#import "IpAddress.h"

/**
 *
 * DnsManager implements utility methods for querying the addresses/CName associated with a domain name.
 *
 **/

@interface DnsManager : NSObject {
@private CFStreamError error;
@public TOCFutureSource* futureResultSource;
}

/// Result has type Future(Array(IpAddress))
+(TOCFuture*) asyncQueryAddressesForDomainName:(NSString*)domainName
                               unlessCancelled:(TOCCancelToken*)unlessCancelledToken;

@end
