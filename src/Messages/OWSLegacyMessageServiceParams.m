//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSLegacyMessageServiceParams.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSLegacyMessageServiceParams

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    NSMutableDictionary *keys = [[super JSONKeyPathsByPropertyKey] mutableCopy];
    [keys setObject:@"body" forKey:@"content"];
    return [keys copy];
}

- (instancetype)initWithType:(TSWhisperMessageType)type
                 recipientId:(NSString *)destination
                      device:(int)deviceId
                        body:(NSData *)body
              registrationId:(int)registrationId
{
    self = [super initWithType:type recipientId:destination device:deviceId content:body registrationId:registrationId];
    if (!self) {
        return self;
    }

    return self;
}


@end

NS_ASSUME_NONNULL_END
