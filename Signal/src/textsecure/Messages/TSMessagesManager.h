//
//  TSMessagesHandler.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 11/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "IncomingPushMessageSignal.pb.h"
#import "TSOutgoingMessage.h"

@interface TSMessagesManager : NSObject

+ (instancetype)sharedManager;

@property (readonly) YapDatabaseConnection *dbConnection;

- (void)handleMessageSignal:(IncomingPushMessageSignal*)messageSignal;

- (void)processException:(NSException*)exception outgoingMessage:(TSOutgoingMessage*)message;

@end
