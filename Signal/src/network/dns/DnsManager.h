#import <Foundation/Foundation.h>
#import "FutureSource.h"
#import "CancelToken.h"
#import "IpAddress.h"

/**
 *
 * DnsManager implements utility methods for querying the addresses/CName associated with a domain name.
 *
 **/

@interface DnsManager : NSObject {
@private CFStreamError error;
@public FutureSource* futureResultSource;
}

/// Result has type Future(Array(IpAddress))
+(Future*) asyncQueryAddressesForDomainName:(NSString*)domainName
                            unlessCancelled:(id<CancelToken>)unlessCancelledToken;

@end
