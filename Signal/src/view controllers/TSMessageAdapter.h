//
//  TSMessageAdapter.h
//  Signal
//
//  Created by Frederic Jacobs on 24/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <JSQMessagesViewController/JSQMessageData.h>

#import "TSMessageAdapter.h"
#import "TSInteraction.h"
#import "TSThread.h"

@interface TSMessageAdapter : NSObject <JSQMessageData>

+ (instancetype)messageViewDataWithInteraction:(TSInteraction*)interaction inThread:(TSThread*)thread;

@end
