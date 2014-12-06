//
//  TSGroupMessageManager.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "IncomingPushMessageSignal.pb.h"

@interface TSGroupMessageManager : NSObject

+ (void)processGroupMessage:(IncomingPushMessageSignal*)pushMessage content:(PushMessageContent*)content;

@end
