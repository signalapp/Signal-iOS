#import <Foundation/Foundation.h>
#import "NetworkEndPoint.h"
#import "HostNameEndPoint.h"
#import "IpEndPoint.h"
#import "Certificate.h"

/**
 *
 * SecureEndPoint combines a hostname end point with a verifiable cryptographic identity.
 *
 * SecureEndPoint is responsible for resolving and authenticating SSL connections.
 *
 **/

@interface SecureEndPoint : NSObject<NetworkEndPoint> {
@private id<NetworkEndPoint> optionalMoreSpecificEndPoint;
}
@property (nonatomic, readonly) Certificate* certificate;
@property (nonatomic, readonly) HostNameEndPoint* hostNameEndPoint;

+(SecureEndPoint*) secureEndPointForHost:(HostNameEndPoint*)host
                 identifiedByCertificate:(Certificate*)certificate;

@end
