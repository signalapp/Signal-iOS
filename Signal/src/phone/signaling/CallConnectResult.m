#import "CallConnectResult.h"

@interface CallConnectResult ()

@property (nonatomic, readwrite) NSString* shortAuthenticationString;
@property (nonatomic, readwrite) AudioSocket* audioSocket;

@end

@implementation CallConnectResult

- (instancetype)initWithShortAuthenticationString:(NSString*)shortAuthenticationString
                                   andAudioSocket:(AudioSocket*)audioSocket {
    self = [super init];
	
    if (self) {
        require(shortAuthenticationString != nil);
        require(audioSocket != nil);
        
        self.shortAuthenticationString = shortAuthenticationString;
        self.audioSocket = audioSocket;
    }
    
    return self;
}

@end
