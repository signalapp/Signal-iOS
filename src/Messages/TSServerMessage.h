//
//  TSServerMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 18/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Mantle/Mantle.h>
#import "TSConstants.h"

@interface TSServerMessage : MTLModel <MTLJSONSerializing>

- (instancetype)initWithType:(TSWhisperMessageType)type
                 destination:(NSString *)destination
                      device:(int)deviceId
                        body:(NSData *)body
              registrationId:(int)registrationId;

@end
