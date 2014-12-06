//
//  TSRecipient.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 17/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

@interface TSRecipient : TSYapDatabaseObject

- (instancetype)initWithTextSecureIdentifier:(NSString*)textSecureIdentifier relay:(NSString*)relay;

+ (instancetype)recipientWithTextSecureIdentifier:(NSString*)textSecureIdentifier withTransaction:(YapDatabaseReadTransaction*)transaction;

- (NSSet*)devices; //NSNumbers

- (void)addDevices:(NSSet *)set;

- (void)removeDevices:(NSSet *)set;

#pragma mark Fingerprint verification

- (BOOL)hasVerifiedFingerprint;

- (void)setFingerPrintVerified:(BOOL)verified transaction:(YapDatabaseReadTransaction*)transaction;

@property (nonatomic, readonly) NSString *relay;

@end
