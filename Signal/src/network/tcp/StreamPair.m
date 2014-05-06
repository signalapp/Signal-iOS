#import "StreamPair.h"
#import "Constraints.h"

@implementation StreamPair
@synthesize inputStream, outputStream;

+(StreamPair*) streamPairWithInput:(NSInputStream*)input andOutput:(NSOutputStream*)output {
    require(input != nil);
    require(output != nil);

    StreamPair* r = [StreamPair new];
    r->inputStream = input;
    r->outputStream = output;
    
    [r->inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    [r->outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    return r;
}

@end
