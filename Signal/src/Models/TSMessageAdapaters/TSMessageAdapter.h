//
//  TSMessageAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageData.h"
#import "OWSMessageEditing.h"

NS_ASSUME_NONNULL_BEGIN

@class TSInteraction;
@class TSThread;

#define ME_MESSAGE_IDENTIFIER @"Me";

@interface TSMessageAdapter : NSObject <OWSMessageData>

+ (id<OWSMessageData>)messageViewDataWithInteraction:(TSInteraction *)interaction inThread:(TSThread *)thread;

@property TSInteraction *interaction;

@end

NS_ASSUME_NONNULL_END
