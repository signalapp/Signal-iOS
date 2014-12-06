//
//  TSInfoMessage.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSMessage.h"

@interface TSInfoMessage : TSMessage

typedef NS_ENUM(NSInteger, TSInfoMessageType){
    TSInfoMessageTypeSessionDidEnd
};

@property TSInfoMessageType messageType;

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSContactThread *)contact messageType:(TSInfoMessageType)infoMessage;

@end
