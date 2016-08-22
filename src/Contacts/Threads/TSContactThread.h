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

@class OWSSignalServiceProtosEnvelope;

@interface TSContactThread : TSThread

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (instancetype)getOrCreateThreadWithContactId:(NSString *)contactId
                                   transaction:(YapDatabaseReadWriteTransaction *)transaction
                                      envelope:(OWSSignalServiceProtosEnvelope *)envelope;

- (NSString *)contactIdentifier;

@end
