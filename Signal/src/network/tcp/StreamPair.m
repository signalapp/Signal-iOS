#import "StreamPair.h"
#import "Constraints.h"

@interface StreamPair ()

@property (strong, readwrite, nonatomic) NSInputStream* inputStream;
@property (strong, readwrite, nonatomic) NSOutputStream* outputStream;

@end

@implementation StreamPair

- (instancetype)initWithInput:(NSInputStream*)input andOutput:(NSOutputStream*)output {
    if (self = [super init]) {
        require(input != nil);
        require(output != nil);

        self.inputStream = input;
        self.outputStream = output;
        
        [self.inputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
        [self.outputStream setProperty:NSStreamNetworkServiceTypeVoIP forKey:NSStreamNetworkServiceType];
    }
    
    return self;
}

@end
