#import "LKAddressMessage.h"
#import "NSDate+OWS.h"
#import "SignalRecipient.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

@interface LKAddressMessage ()

@property (nonatomic) NSString *address;
@property (nonatomic) uint port;

@end

@implementation LKAddressMessage

- (instancetype)initAddressMessageInThread:(nullable TSThread *)thread
                                   address:(NSString *)address
                                      port:(uint)port
{
    self = [super initOutgoingMessageWithTimestamp:NSDate.ows_millisecondTimeStamp inThread:thread messageBody:nil attachmentIds:[NSMutableArray<NSString *> new]
                                  expiresInSeconds:0 expireStartedAt:0 isVoiceMessage:NO groupMetaMessage:TSGroupMetaMessageUnspecified quotedMessage:nil contactShare:nil linkPreview:nil];
    if (!self) {
        return self;
    }
    
    _address = address;
    _port = port;
    
    return self;
}

- (SSKProtoContentBuilder *)contentBuilder:(SignalRecipient *)recipient {
    SSKProtoContentBuilder *contentBuilder = [super contentBuilder:recipient];
  
    // Se
    SSKProtoLokiAddressMessageBuilder *addressBuilder = SSKProtoLokiAddressMessage.builder;
    [addressBuilder setPtpAddress:self.address];
    [addressBuilder setPtpPort:self.port];
    
    NSError *error;
    SSKProtoLokiAddressMessage *addressMessage = [addressBuilder buildAndReturnError:&error];
    if (error || !addressMessage) {
        OWSFailDebug(@"Failed to build lokiAddressMessage for %@: %@", recipient.recipientId, error);
    } else {
        [contentBuilder setLokiAddressMessage:addressMessage];
    }

    return contentBuilder;
}

// We don't need to send any data message in this address message
- (nullable SSKProtoDataMessage *)buildDataMessage:(NSString *_Nullable)recipientId {
    return nil;
}

- (BOOL)shouldBeSaved { return false; }

- (uint)ttl {
    // Address messages should only last 1 minute
    return 1 * kMinuteInterval;
}

@end
