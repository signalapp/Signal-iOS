//
//  TSContactThread.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 16/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "SignalRecipient.h"
#import "TSThread.h"

@class IncomingPushMessageSignal;

@interface TSContactThread : TSThread

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction;
+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
                                    pushSignal:(IncomingPushMessageSignal *)pushSignal;

- (NSString *)contactIdentifier;

@end
