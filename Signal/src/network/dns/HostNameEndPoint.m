#import "HostNameEndPoint.h"
#import "DnsManager.h"
#import "IpEndPoint.h"
#import "Util.h"

@implementation HostNameEndPoint
@synthesize hostname, port;

+(HostNameEndPoint*) hostNameEndPointWithHostName:(NSString*)hostname
                                          andPort:(in_port_t)port {
    ows_require(hostname != nil);
    ows_require(port > 0);
    
    HostNameEndPoint* h = [HostNameEndPoint new];
    h->hostname = hostname.copy; // avoid mutability
    h->port = port;
    return h;
}

-(void) handleStreamsOpened:(StreamPair *)streamPair {
    // no work needed
}
-(TOCFuture*)asyncHandleStreamsConnected:(StreamPair *)streamPair {
    return [TOCFuture futureWithResult:@YES];
}

-(StreamPair*)createStreamPair {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)hostname, port, &readStream, &writeStream);
    return [StreamPair streamPairWithInput:(__bridge_transfer NSInputStream*)readStream
                                 andOutput:(__bridge_transfer NSOutputStream*)writeStream];
}

-(TOCFuture*) asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    TOCFuture* futureDnsResult = [DnsManager asyncQueryAddressesForDomainName:hostname
                                                              unlessCancelled:unlessCancelledToken];
    return [futureDnsResult thenTry:^(NSArray* ipAddresses) {
        return [ipAddresses map:^(IpAddress* address) {
            return [IpEndPoint ipEndPointAtAddress:address onPort:port];
        }];
    }];
}

-(NSString*) description {
    return [NSString stringWithFormat:@"%@:%d", hostname, port];
}

@end
