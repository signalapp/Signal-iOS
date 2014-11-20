#import "HostNameEndPoint.h"
#import "DNSManager.h"
#import "IPEndPoint.h"
#import "ThreadManager.h"
#import "Util.h"

@interface HostNameEndPoint ()

@property (nonatomic, readwrite) in_port_t port;
@property (strong, nonatomic, readwrite) NSString* hostname;

@end

@implementation HostNameEndPoint

- (instancetype)initWithHostName:(NSString*)hostname
                         andPort:(in_port_t)port {
    self = [super init];
	
    if (self) {
        require(hostname != nil);
        require(port > 0);
        self.hostname = hostname;
        self.port = port;
    }
    
    return self;
}

- (void)handleStreamsOpened:(StreamPair*)streamPair {
    // no work needed
}

- (TOCFuture*)asyncHandleStreamsConnected:(StreamPair*)streamPair {
    return [TOCFuture futureWithResult:@YES];
}

- (StreamPair*)createStreamPair {
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)self.hostname, self.port, &readStream, &writeStream);
    return [[StreamPair alloc] initWithInput:(__bridge_transfer NSInputStream*)readStream
                                   andOutput:(__bridge_transfer NSOutputStream*)writeStream];
}

- (TOCFuture*)asyncResolveToSpecificEndPointsUnlessCancelled:(TOCCancelToken*)unlessCancelledToken {
    TOCFuture* futureDnsResult = [DNSManager asyncQueryAddressesForDomainName:self.hostname
                                                              unlessCancelled:unlessCancelledToken];
    return [futureDnsResult thenTry:^(NSArray* ipAddresses) {
        return [ipAddresses map:^(IPAddress* address) {
            return [[IPEndPoint alloc] initWithAddress:address onPort:self.port];
        }];
    }];
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@:%d", self.hostname, self.port];
}

@end
