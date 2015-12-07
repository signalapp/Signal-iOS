//
//  TSRecipient.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

@interface SignalRecipient : TSYapDatabaseObject

- (instancetype)initWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                       relay:(NSString *)relay
                               supportsVoice:(BOOL)voiceCapable;

+ (instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                  withTransaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevices:(NSSet *)set;

- (void)removeDevices:(NSSet *)set;

@property (nonatomic) NSString *relay;
@property (nonatomic, retain) NSMutableOrderedSet *devices;
@property BOOL supportsVoice;

@end
