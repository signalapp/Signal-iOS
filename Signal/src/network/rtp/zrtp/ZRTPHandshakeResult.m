#import "ZRTPHandshakeResult.h"

@interface ZRTPHandshakeResult ()

@property (strong, readwrite, nonatomic) SRTPSocket* secureRTPSocket;
@property (strong, readwrite, nonatomic) MasterSecret* masterSecret;

@end

@implementation ZRTPHandshakeResult

- (instancetype)initWithSecureChannel:(SRTPSocket*)secureRTPSocket
                      andMasterSecret:(MasterSecret*)masterSecret {
    if (self = [super init]) {
        require(secureRTPSocket != nil);
        require(masterSecret != nil);
        
        self.masterSecret = masterSecret;
        self.secureRTPSocket = secureRTPSocket;
    }
    
    return self;
}

@end
