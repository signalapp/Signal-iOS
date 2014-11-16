#import <Foundation/Foundation.h>
#import "NetworkEndPoint.h"
#import "HostNameEndPoint.h"
#import "IPEndPoint.h"
#import "Certificate.h"

/**
 *
 * SecureEndPoint combines a hostname end point with a verifiable cryptographic identity.
 *
 * SecureEndPoint is responsible for resolving and authenticating SSL connections.
 *
 **/

@interface SecureEndPoint : NSObject <NetworkEndPoint>

@property (strong, readonly, nonatomic) Certificate* certificate;
@property (strong, readonly, nonatomic) HostNameEndPoint* hostNameEndPoint;

- (instancetype)initWithHost:(HostNameEndPoint*)host
     identifiedByCertificate:(Certificate*)certificate;

@end
