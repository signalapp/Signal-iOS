/// Loki: Refer to Docs/SessionReset.md for explanations

#import "SessionCipher+Loki.h"
#import "NSNotificationCenter+OWS.h"
#import "PreKeyWhisperMessage.h"
#import "OWSPrimaryStorage+Loki.h"
#import "TSContactThread.h"
#import <YapDatabase/YapDatabase.h>

NSString *const kNSNotificationName_SessionAdopted = @"kNSNotificationName_SessionAdopted";
NSString *const kNSNotificationKey_ContactPubKey = @"kNSNotificationKey_ContactPubKey";

@interface SessionCipher ()

@property (nonatomic, readonly) NSString *recipientId;
@property (nonatomic, readonly) int deviceId;

@property (nonatomic, readonly) id<SessionStore> sessionStore;
@property (nonatomic, readonly) id<PreKeyStore> prekeyStore;

@end

@implementation SessionCipher (Loki)

- (NSData *)throws_lokiDecrypt:(id<CipherMessage>)whisperMessage protocolContext:(nullable id)protocolContext
{
    // Our state before we decrypt the message
    SessionState *_Nullable state = [self getCurrentState:protocolContext];
    
    // While decrypting our state may change internally
    NSData *plainText = [self throws_decrypt:whisperMessage protocolContext:protocolContext];
    
    // Loki: Verify incoming friend request messages
    if (!state) {
        [self throws_verifyFriendRequestAcceptPreKeyForMessage:whisperMessage protocolContext:protocolContext];
    }
   
    // Loki: Handle any session resets
    [self handleSessionReset:whisperMessage previousState:state protocolContext:protocolContext];
    
    return plainText;
}

/// Get the current session state
- (SessionState *_Nullable)getCurrentState:(nullable id)protocolContext {
    SessionRecord *record = [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    SessionState *state = record.sessionState;
    
    // Check if session is initialized
    if (!state.hasSenderChain) {
        return nil;
    }
    
    return state;
}

/// Handle any loki session reset stuff
- (void)handleSessionReset:(id<CipherMessage>)whisperMessage
             previousState:(SessionState *_Nullable)previousState
           protocolContext:(nullable id)protocolContext
{
    // Don't bother doing anything if we didn't have a session before
    if (!previousState) {
        return;
    }
    
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadWriteTransaction class]]);
    YapDatabaseReadWriteTransaction *transaction = protocolContext;
    
    // Get the thread
    TSContactThread *thread = [TSContactThread getThreadWithContactId:self.recipientId transaction:transaction];
    if (!thread) {
        return;
    }
    
    // Bail early if no session reset is in progress
    if (thread.sessionResetState == TSContactThreadSessionResetStateNone) {
        return;
    }
    
    BOOL sessionResetReceived = thread.sessionResetState == TSContactThreadSessionResetStateRequestReceived;
    SessionState *_Nullable currentState = [self getCurrentState:protocolContext];
    
    // Check if our previous state and our current state differ
    if (!currentState || ![currentState.aliceBaseKey isEqualToData:previousState.aliceBaseKey]) {
        
        if (sessionResetReceived) {
            // The other user used an old session to contact us.
            // Wait for them to use a new one
            [self restoreSession:previousState protocolContext:protocolContext];
        } else {
            // Our session reset went through successfully
            // We had initiated a session reset and got a different session back from the user
            [self deleteAllSessionsExcept:currentState protocolContext:protocolContext];
            [self notifySessionAdopted];
        }
        
    } else if (sessionResetReceived) {
        // Our session reset went through successfully
        // We got a message with the same session from the other user
        [self deleteAllSessionsExcept:previousState protocolContext:protocolContext];
        [self notifySessionAdopted];
    }
}

/// Send a notification about a new session being adopted
- (void)notifySessionAdopted
{
    [[NSNotificationCenter defaultCenter]
     postNotificationNameAsync:kNSNotificationName_SessionAdopted
     object:nil
     userInfo:@{
                kNSNotificationKey_ContactPubKey : self.recipientId,
                }];
}

/// Delete all other sessions except the given one
- (void)deleteAllSessionsExcept:(SessionState *)state protocolContext:(nullable id)protocolContext
{
    SessionRecord *record = [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    [record removePreviousSessionStates];
    [record setState:state];
    
    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:record
                    protocolContext:protocolContext];
}

/// Set the given session as the active one while archiving the old one
- (void)restoreSession:(SessionState *)state protocolContext:(nullable id)protocolContext
{
    SessionRecord *record = [self.sessionStore loadSession:self.recipientId deviceId:self.deviceId protocolContext:protocolContext];
    
    // Remove the state from previous session states
    [record.previousSessionStates enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(SessionState *obj, NSUInteger idx, BOOL *stop) {
        if ([state.aliceBaseKey isEqualToData:obj.aliceBaseKey]) {
            [record.previousSessionStates removeObjectAtIndex:idx];
            *stop = true;
        }
    }];
    
    // Promote it so the previous state gets archived
    [record promoteState:state];
    
    [self.sessionStore storeSession:self.recipientId
                           deviceId:self.deviceId
                            session:record
                    protocolContext:protocolContext];
}

/// Check that we have matching prekeys in the case of a `PreKeyWhisperMessage`
/// This is so that we don't trigger a false friend request accept on unknown contacts
- (void)throws_verifyFriendRequestAcceptPreKeyForMessage:(id<CipherMessage>)whisperMessage protocolContext:(nullable id)protocolContext {
    OWSAssertDebug([protocolContext isKindOfClass:[YapDatabaseReadTransaction class]]);
    YapDatabaseReadTransaction *transaction = protocolContext;
    
    /// We only want to look at `PreKeyWhisperMessage`
    if (![whisperMessage isKindOfClass:[PreKeyWhisperMessage class]]) {
        return;
    }

    /// We need the primary storage to access contact prekeys
    if (![self.prekeyStore isKindOfClass:[OWSPrimaryStorage class]]) {
        return;
    }
    
    PreKeyWhisperMessage *preKeyMessage = whisperMessage;
    OWSPrimaryStorage *primaryStorage = self.prekeyStore;
    
    PreKeyRecord *_Nullable storedPreKey = [primaryStorage getPreKeyForContact:self.recipientId transaction:transaction];
    if(!storedPreKey) {
        OWSRaiseException(@"LokiInvalidPreKey", @"Received a friend request from a pubkey for which no prekey bundle was created");
    }
    
    if (storedPreKey.Id != preKeyMessage.prekeyID) {
        OWSRaiseException(@"LokiPreKeyIdsDontMatch", @"Received a preKeyWhisperMessage (friend request accept) from an unknown source");
    }
}

@end
