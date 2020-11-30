#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"

#import "OWSIdentityManager.h"
#import "NSDate+OWS.h"
#import "TSAccountManager.h"
#import "TSPreKeyManager.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <SessionProtocolKit/NSData+keyVersionByte.h>
#import "NSObject+Casting.h"
#import <SignalUtilitiesKit/SignalUtilitiesKit-Swift.h>

@implementation OWSPrimaryStorage (Loki)

# pragma mark - Convenience

- (OWSIdentityManager *)identityManager {
    return OWSIdentityManager.sharedManager;
}

- (TSAccountManager *)accountManager {
    return TSAccountManager.sharedInstance;
}

# pragma mark - Pre Key Record Management

#define LKPreKeyContactCollection @"LKPreKeyContactCollection"
#define OWSPrimaryStoragePreKeyStoreCollection @"TSStorageManagerPreKeyStoreCollection"

- (BOOL)hasPreKeyRecordForContact:(NSString *)hexEncodedPublicKey {
    int preKeyId = [self.dbReadWriteConnection intForKey:hexEncodedPublicKey inCollection:LKPreKeyContactCollection];
    return preKeyId > 0;
}

- (PreKeyRecord *_Nullable)getPreKeyRecordForContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadTransaction *)transaction {
    OWSAssertDebug(hexEncodedPublicKey.length > 0);
    int preKeyID = [transaction intForKey:hexEncodedPublicKey inCollection:LKPreKeyContactCollection];

    if (preKeyID <= 0) { return nil; }
    
    // throws_loadPreKey doesn't allow us to pass transaction
    // FIXME: This seems like it could be a pretty big issue?
    return [transaction preKeyRecordForKey:[self keyFromInt:preKeyID] inCollection:OWSPrimaryStoragePreKeyStoreCollection];
}

- (PreKeyRecord *)getOrCreatePreKeyRecordForContact:(NSString *)hexEncodedPublicKey {
    OWSAssertDebug(hexEncodedPublicKey.length > 0);
    int preKeyID = [self.dbReadWriteConnection intForKey:hexEncodedPublicKey inCollection:LKPreKeyContactCollection];
    
    // If we don't have an ID then generate and store a new one
    if (preKeyID <= 0) {
        return [self generateAndStorePreKeyRecordForContact:hexEncodedPublicKey];
    }
    
    // Load existing pre key record if possible; generate a new one otherwise
    @try {
        return [self throws_loadPreKey:preKeyID];
    } @catch (NSException *exception) {
        return [self generateAndStorePreKeyRecordForContact:hexEncodedPublicKey];
    }
}

- (PreKeyRecord *)generateAndStorePreKeyRecordForContact:(NSString *)hexEncodedPublicKey {
    NSLog([NSString stringWithFormat:@"[Loki] Generating new pre key record for: %@.", hexEncodedPublicKey]);
    OWSAssertDebug(hexEncodedPublicKey.length > 0);
    
    NSArray<PreKeyRecord *> *records = [self generatePreKeyRecords:1];
    OWSAssertDebug(records.count > 0);
    [self storePreKeyRecords:records];

    PreKeyRecord *record = records.firstObject;
    [self.dbReadWriteConnection setInt:record.Id forKey:hexEncodedPublicKey inCollection:LKPreKeyContactCollection];
    
    return record;
}

# pragma mark - Pre Key Bundle Management

#define LKPreKeyBundleCollection @"LKPreKeyBundleCollection"

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)hexEncodedPublicKey forceClean:(BOOL)forceClean {
    // Refresh signed pre key if needed
    [TSPreKeyManager checkPreKeys];
    
    ECKeyPair *_Nullable keyPair = self.identityManager.identityKeyPair;
    OWSAssertDebug(keyPair);

    // Refresh signed pre key if needed
    if (self.currentSignedPreKey == nil || forceClean) { // TODO: Is the self.currentSignedPreKey == nil check needed?
        SignedPreKeyRecord *signedPreKeyRecord = [self generateRandomSignedRecord];
        [signedPreKeyRecord markAsAcceptedByService];
        [self storeSignedPreKey:signedPreKeyRecord.Id signedPreKeyRecord:signedPreKeyRecord];
        [self setCurrentSignedPrekeyId:signedPreKeyRecord.Id];
        NSLog(@"[Loki] Signed pre key refreshed successfully.");
    }

    SignedPreKeyRecord *_Nullable signedPreKey = self.currentSignedPreKey;
    if (signedPreKey == nil) {
        OWSFailDebug(@"Signed pre key is nil.");
    }
    
    PreKeyRecord *preKey = [self getOrCreatePreKeyRecordForContact:hexEncodedPublicKey];
    uint32_t registrationID = [self.accountManager getOrGenerateRegistrationId];
    
    PreKeyBundle *bundle = [[PreKeyBundle alloc] initWithRegistrationId:registrationID
                                                               deviceId:(uint32_t)1
                                                               preKeyId:preKey.Id
                                                           preKeyPublic:preKey.keyPair.publicKey.prependKeyType
                                                     signedPreKeyPublic:signedPreKey.keyPair.publicKey.prependKeyType
                                                         signedPreKeyId:signedPreKey.Id
                                                  signedPreKeySignature:signedPreKey.signature
                                                            identityKey:keyPair.publicKey.prependKeyType];
    return bundle;
}

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)hexEncodedPublicKey {
    NSInteger failureCount = 0;
    BOOL forceClean = NO;
    while (failureCount < 3) {
        @try {
            PreKeyBundle *preKeyBundle = [self generatePreKeyBundleForContact:hexEncodedPublicKey forceClean:forceClean];
            if (![Ed25519 throws_verifySignature:preKeyBundle.signedPreKeySignature
                                       publicKey:preKeyBundle.identityKey.throws_removeKeyType
                                            data:preKeyBundle.signedPreKeyPublic]) {
                @throw [NSException exceptionWithName:InvalidKeyException reason:@"KeyIsNotValidlySigned" userInfo:nil];
            }
            NSLog([NSString stringWithFormat:@"[Loki] Generated a new pre key bundle for: %@.", hexEncodedPublicKey]);
            return preKeyBundle;
        } @catch (NSException *exception) {
            failureCount += 1;
            forceClean = YES;
        }
    }
    NSLog([NSString stringWithFormat:@"[Loki] Failed to generate a valid pre key bundle for: %@.", hexEncodedPublicKey]);
    return nil;
}

- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)hexEncodedPublicKey {
    return [self.dbReadConnection preKeyBundleForKey:hexEncodedPublicKey inCollection:LKPreKeyBundleCollection];
}

- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction setObject:bundle forKey:hexEncodedPublicKey inCollection:LKPreKeyBundleCollection];
    NSLog([NSString stringWithFormat:@"[Loki] Stored pre key bundle from: %@.", hexEncodedPublicKey]);
    // FIXME: I don't think the line below is good for anything
    [transaction.connection flushTransactionsWithCompletionQueue:dispatch_get_main_queue() completionBlock:^{ }];
}

- (void)removePreKeyBundleForContact:(NSString *)hexEncodedPublicKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction removeObjectForKey:hexEncodedPublicKey inCollection:LKPreKeyBundleCollection];
    NSLog([NSString stringWithFormat:@"[Loki] Removed pre key bundle from: %@.", hexEncodedPublicKey]);
}

# pragma mark - Open Groups

#define LKMessageIDCollection @"LKMessageIDCollection"

- (void)setIDForMessageWithServerID:(NSUInteger)serverID to:(NSString *)messageID in:(YapDatabaseReadWriteTransaction *)transaction {
    NSString *key = [NSString stringWithFormat:@"%@", @(serverID)];
    [transaction setObject:messageID forKey:key inCollection:LKMessageIDCollection];
}

- (NSString *_Nullable)getIDForMessageWithServerID:(NSUInteger)serverID in:(YapDatabaseReadTransaction *)transaction {
    NSString *key = [NSString stringWithFormat:@"%@", @(serverID)];
    return [transaction objectForKey:key inCollection:LKMessageIDCollection];
}

- (void)updateMessageIDCollectionByPruningMessagesWithIDs:(NSSet<NSString *> *)targetMessageIDs in:(YapDatabaseReadWriteTransaction *)transaction {
    NSMutableArray<NSString *> *serverIDs = [NSMutableArray new];
    [transaction enumerateRowsInCollection:LKMessageIDCollection usingBlock:^(NSString *key, id object, id metadata, BOOL *stop) {
        if (![object isKindOfClass:NSString.class]) { return; }
        NSString *messageID = (NSString *)object;
        if (![targetMessageIDs containsObject:messageID]) { return; }
        [serverIDs addObject:key];
    }];
    [transaction removeObjectsForKeys:serverIDs inCollection:LKMessageIDCollection];
}

# pragma mark - Restoration from Seed

#define LKGeneralCollection @"Loki"

- (void)setRestorationTime:(NSTimeInterval)time {
    [self.dbReadWriteConnection setDouble:time forKey:@"restoration_time" inCollection:LKGeneralCollection];
}

- (NSTimeInterval)getRestorationTime {
    return [self.dbReadConnection doubleForKey:@"restoration_time" inCollection:LKGeneralCollection defaultValue:0];
}

@end
