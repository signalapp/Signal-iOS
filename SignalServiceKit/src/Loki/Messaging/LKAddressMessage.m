#import "LKAddressMessage.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface LKAddressMessage ()

@property (nonatomic) NSString *address;
@property (nonatomic) uint16_t port;
@property (nonatomic) BOOL isPing;

@end

@implementation LKAddressMessage

- (instancetype)initInThread:(nullable TSThread *)thread address:(NSString *)address port:(uint16_t)port isPing:(bool)isPing
{
    self = [super initInThread:thread];
    if (self) {
        _address = address;
        _port = port;
        _isPing = isPing;
    }
    return self;
}

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
  
    SSKProtoLokiAddressMessageBuilder *addressBuilder = [SSKProtoLokiAddressMessage builder];
    [addressBuilder setPtpAddress:self.address];
    uint32_t portAsUInt32 = self.port;
    [addressBuilder setPtpPort:portAsUInt32];
    
    NSError *error;
    SSKProtoLokiAddressMessage *addressMessage = [addressBuilder buildAndReturnError:&error];
    if (error || !addressMessage) {
        OWSFailDebug(@"Failed to build LokiAddressMessage for %@: %@.", recipient.recipientId, error);
    } else {
        [contentBuilder setLokiAddressMessage:addressMessage];
    }

    return contentBuilder;
}

- (uint)ttl {
    // Address messages should only last 1 minute
    return 1 * kMinuteInMs;
}

@end
