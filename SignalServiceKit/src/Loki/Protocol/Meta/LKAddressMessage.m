#import "LKAddressMessage.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SessionServiceKit/SessionServiceKit-Swift.h>

@interface LKAddressMessage ()

@property (nonatomic) NSString *address;
@property (nonatomic) uint16_t port;
@property (nonatomic) BOOL isPing;

@end

@implementation LKAddressMessage

#pragma mark Initialization
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

#pragma mark Building
- (SSKProtoContentBuilder *)prepareCustomContentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = SSKProtoContent.builder;
    SSKProtoLokiAddressMessageBuilder *addressMessageBuilder = SSKProtoLokiAddressMessage.builder;
    [addressMessageBuilder setPtpAddress:self.address];
    uint32_t portAsUInt32 = self.port;
    [addressMessageBuilder setPtpPort:portAsUInt32];
    NSError *error;
    SSKProtoLokiAddressMessage *addressMessage = [addressMessageBuilder buildAndReturnError:&error];
    if (error || addressMessage == nil) {
        OWSFailDebug(@"Failed to build Loki address message for: %@ due to error: %@.", recipient.recipientId, error);
        return nil;
    } else {
        [contentBuilder setLokiAddressMessage:addressMessage];
    }
    return contentBuilder;
}

#pragma mark Settings
- (uint)ttl { return (uint)[LKTTLUtilities getTTLFor:LKMessageTypeAddress]; }

@end
