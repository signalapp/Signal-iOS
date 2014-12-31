//
//  TSInvalidIdentityKeyErrorMessage.m
//  Signal
//
//  Created by Frederic Jacobs on 31/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <YapDatabase/YapDatabaseTransaction.h>
#import <YapDatabase/YapDatabaseView.h>

#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSErrorMessage_privateConstructor.h"
#import "TSDatabaseView.h"
#import "TSStorageManager.h"
#import "TSStorageManager+IdentityKeyStore.h"
#import <AxolotlKit/PreKeyWhisperMessage.h>
#import <AxolotlKit/NSData+keyVersionByte.h>
#import "TSMessagesManager.h"
#import "TSFingerprintGenerator.h"

@implementation TSInvalidIdentityKeyErrorMessage

- (instancetype)initForUnknownIdentityKeyWithTimestamp:(uint64_t)timestamp inThread:(TSThread *)thread incomingPushSignal:(NSData*)signal{
    self = [self initWithTimestamp:timestamp inThread:thread failedMessageType:TSErrorMessageWrongTrustedIdentityKey];
    
    if (self) {
        self.pushSignal = signal;
    }
    
    return self;
}

+ (instancetype)untrustedKeyWithSignal:(IncomingPushMessageSignal*)preKeyMessage withTransaction:(YapDatabaseReadWriteTransaction*)transaction{
    TSContactThread *contactThread = [TSContactThread getOrCreateThreadWithContactId:preKeyMessage.source transaction:transaction];
    TSInvalidIdentityKeyErrorMessage *errorMessage = [[self alloc] initForUnknownIdentityKeyWithTimestamp:preKeyMessage.timestamp inThread:contactThread incomingPushSignal:preKeyMessage.data];
    return errorMessage;
}

- (void)acceptNewIdentityKey{
    if (self.errorType != TSErrorMessageWrongTrustedIdentityKey || !self.pushSignal) {
        return;
    }

    TSStorageManager *storage         = [TSStorageManager sharedManager];
    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:self.pushSignal];
    PreKeyWhisperMessage *message     = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *newKey                    = [message.identityKey removeKeyType];
    
    [storage saveRemoteIdentity:newKey recipientId:signal.source];
    
    [[TSMessagesManager sharedManager] handleMessageSignal:signal];
    
    __block NSMutableSet *messagesToDecrypt = [NSMutableSet set];
    
    [[TSStorageManager sharedManager].dbConnection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
        [[transaction ext:TSMessageDatabaseViewExtensionName]enumerateKeysAndObjectsInGroup:self.uniqueThreadId withOptions:NSEnumerationReverse usingBlock:^(NSString *collection, NSString *key, id object, NSUInteger index, BOOL *stop) {
            TSInteraction *interaction = (TSInteraction*)object;
            
            DDLogVerbose(@"Interaction type: %@", interaction.description);
            
            if ([interaction isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
                TSInvalidIdentityKeyErrorMessage *invalidKeyMessage = (TSInvalidIdentityKeyErrorMessage*)interaction;
                IncomingPushMessageSignal *invalidMessageSignal = [IncomingPushMessageSignal parseFromData:invalidKeyMessage.pushSignal];
                PreKeyWhisperMessage *pkwm     = [[PreKeyWhisperMessage alloc] initWithData:invalidMessageSignal.message];
                NSData *newKeyCandidate        = [pkwm.identityKey removeKeyType];
                
                if ([newKeyCandidate isEqualToData:newKey]) {
                    [messagesToDecrypt addObject:invalidMessageSignal];
                }
            }
        }];
    }];
    
    for (IncomingPushMessageSignal *aSignal in messagesToDecrypt) {
        [[TSMessagesManager sharedManager] handleMessageSignal:aSignal];
    }
}

- (NSString *)newIdentityKey{
    if (self.errorType != TSErrorMessageWrongTrustedIdentityKey || !self.pushSignal) {
        return @"";
    }
    
    IncomingPushMessageSignal *signal = [IncomingPushMessageSignal parseFromData:self.pushSignal];
    PreKeyWhisperMessage *message     = [[PreKeyWhisperMessage alloc] initWithData:signal.message];
    NSData *identityKey               = [message.identityKey removeKeyType];
    
    return [TSFingerprintGenerator getFingerprintForDisplay:identityKey];
}

@end
