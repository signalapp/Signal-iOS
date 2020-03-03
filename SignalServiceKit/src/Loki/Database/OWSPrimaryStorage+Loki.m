#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSPrimaryStorage+keyFromIntLong.h"
#import "OWSDevice.h"
#import "OWSIdentityManager.h"
#import "NSDate+OWS.h"
#import "TSAccountManager.h"
#import "TSPreKeyManager.h"
#import "YapDatabaseConnection+OWS.h"
#import "YapDatabaseTransaction+OWS.h"
#import <AxolotlKit/NSData+keyVersionByte.h>
#import "NSObject+Casting.h"

@implementation OWSPrimaryStorage (Loki)

# pragma mark - Convenience

#define OWSPrimaryStoragePreKeyStoreCollection @"TSStorageManagerPreKeyStoreCollection"
#define LKPreKeyContactCollection @"LKPreKeyContactCollection"

- (OWSIdentityManager *)identityManager {
    return OWSIdentityManager.sharedManager;
}

- (TSAccountManager *)accountManager {
    return TSAccountManager.sharedInstance;
}

# pragma mark - Pre Key for Contact

- (BOOL)hasPreKeyForContact:(NSString *)pubKey {
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LKPreKeyContactCollection];
    return preKeyId > 0;
}

- (PreKeyRecord *_Nullable)getPreKeyForContact:(NSString *)pubKey transaction:(YapDatabaseReadTransaction *)transaction {
    OWSAssertDebug(pubKey.length > 0);
    int preKeyId = [transaction intForKey:pubKey inCollection:LKPreKeyContactCollection];
    
    // If we don't have an id then return nil
    if (preKeyId <= 0) { return nil; }
    
    /// throws_loadPreKey doesn't allow us to pass transaction ;(
    return [transaction preKeyRecordForKey:[self keyFromInt:preKeyId] inCollection:OWSPrimaryStoragePreKeyStoreCollection];
}

- (PreKeyRecord *)getOrCreatePreKeyForContact:(NSString *)pubKey {
    OWSAssertDebug(pubKey.length > 0);
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LKPreKeyContactCollection];
    
    // If we don't have an id then generate and store a new one
    if (preKeyId <= 0) {
        return [self generateAndStorePreKeyForContact:pubKey];
    }
    
    // Load the prekey otherwise just generate a new one
    @try {
        return [self throws_loadPreKey:preKeyId];
    } @catch (NSException *exception) {
        NSLog(@"[Loki] New pre key generated for %@.", pubKey);
        return [self generateAndStorePreKeyForContact:pubKey];
    }
}

/// Generate prekey for a contact and store it
- (PreKeyRecord *)generateAndStorePreKeyForContact:(NSString *)pubKey {
    OWSAssertDebug(pubKey.length > 0);
    
    NSArray<PreKeyRecord *> *records = [self generatePreKeyRecords:1];
    [self storePreKeyRecords:records];
    
    OWSAssertDebug(records.count > 0);
    PreKeyRecord *record = records.firstObject;
    [self.dbReadWriteConnection setInt:record.Id forKey:pubKey inCollection:LKPreKeyContactCollection];
    
    return record;
}

# pragma mark - Pre Key Bundle

#define LKPreKeyBundleCollection @"LKPreKeyBundleCollection"

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey forceClean:(BOOL)forceClean {
    // Check pre keys to make sure we have them
    [TSPreKeyManager checkPreKeys];
    
    ECKeyPair *_Nullable keyPair = self.identityManager.identityKeyPair;
    OWSAssertDebug(keyPair);
    

    // Refresh the signed pre key if needed
    if (self.currentSignedPreKey == nil || forceClean) {
        SignedPreKeyRecord *signedPreKeyRecord = [self generateRandomSignedRecord];
        [signedPreKeyRecord markAsAcceptedByService];
        [self storeSignedPreKey:signedPreKeyRecord.Id signedPreKeyRecord:signedPreKeyRecord];
        [self setCurrentSignedPrekeyId:signedPreKeyRecord.Id];
        NSLog(@"[Loki] Pre keys refreshed successfully.");
    }

    SignedPreKeyRecord *_Nullable signedPreKey = self.currentSignedPreKey;
    if (!signedPreKey) {
        OWSFailDebug(@"Signed pre key is null.");
    }
    
    PreKeyRecord *preKey = [self getOrCreatePreKeyForContact:pubKey];
    uint32_t registrationId = [self.accountManager getOrGenerateRegistrationId];
    
    PreKeyBundle *bundle = [[PreKeyBundle alloc] initWithRegistrationId:registrationId
                                                               deviceId:OWSDevicePrimaryDeviceId
                                                               preKeyId:preKey.Id
                                                           preKeyPublic:preKey.keyPair.publicKey.prependKeyType
                                                     signedPreKeyPublic:signedPreKey.keyPair.publicKey.prependKeyType
                                                         signedPreKeyId:signedPreKey.Id
                                                  signedPreKeySignature:signedPreKey.signature
                                                            identityKey:keyPair.publicKey.prependKeyType];
    return bundle;
}

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey {
    NSInteger failureCount = 0;
    BOOL forceClean = NO;
    while (failureCount < 3) {
        @try {
            PreKeyBundle *preKeyBundle = [self generatePreKeyBundleForContact:pubKey forceClean:forceClean];
            if (![Ed25519 throws_verifySignature:preKeyBundle.signedPreKeySignature
                                       publicKey:preKeyBundle.identityKey.throws_removeKeyType
                                            data:preKeyBundle.signedPreKeyPublic]) {
                @throw [NSException exceptionWithName:InvalidKeyException reason:@"KeyIsNotValidlySigned" userInfo:nil];
            }
            return preKeyBundle;
        } @catch (NSException *exception) {
            failureCount++;
            forceClean = YES;
        }
    }
    OWSLogWarn(@"[Loki] Failed to generate a valid pre key bundle for: %@.", pubKey);
    return nil;
}

- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)pubKey {
    return [self.dbReadConnection preKeyBundleForKey:pubKey inCollection:LKPreKeyBundleCollection];
}

- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction setObject:bundle forKey:pubKey inCollection:LKPreKeyBundleCollection];
    [transaction.connection flushTransactionsWithCompletionQueue:dispatch_get_main_queue() completionBlock:^{ }];
}

- (void)removePreKeyBundleForContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction removeObjectForKey:pubKey inCollection:LKPreKeyBundleCollection];
}

# pragma mark - Last Message Hash

#define LKLastMessageHashCollection @"LKLastMessageHashCollection"

- (NSString *_Nullable)getLastMessageHashForServiceNode:(NSString *)serviceNode transaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSDictionary *_Nullable dict = [transaction objectForKey:serviceNode inCollection:LKLastMessageHashCollection];
    if (!dict) { return nil; }
    
    NSString *_Nullable hash = dict[@"hash"];
    if (!hash) { return nil; }
    
    // Check if the hash isn't expired
    uint64_t now = NSDate.ows_millisecondTimeStamp;
    NSNumber *_Nullable expiresAt = dict[@"expiresAt"];
    if (expiresAt && expiresAt.unsignedLongLongValue <= now) {
        // The last message has expired from the storage server
        [self removeLastMessageHashForServiceNode:serviceNode transaction:transaction];
        return nil;
    }
    
    return hash;
}

- (void)setLastMessageHashForServiceNode:(NSString *)serviceNode hash:(NSString *)hash expiresAt:(u_int64_t)expiresAt transaction:(YapDatabaseReadWriteTransaction *)transaction {
    NSDictionary *dict = @{ @"hash" : hash, @"expiresAt": @(expiresAt) };
    [transaction setObject:dict forKey:serviceNode inCollection:LKLastMessageHashCollection];
}

- (void)removeLastMessageHashForServiceNode:(NSString *)serviceNode transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction removeObjectForKey:serviceNode inCollection:LKLastMessageHashCollection];
}

# pragma mark - Group Chat

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

# pragma mark - Restoration

#define LKGeneralCollection @"Loki"

- (void)setRestorationTime:(NSTimeInterval)time {
    [self.dbReadWriteConnection setDouble:time forKey:@"restoration_time" inCollection:LKGeneralCollection];
}

- (NSTimeInterval)getRestorationTime {
    return [self.dbReadConnection doubleForKey:@"restoration_time" inCollection:LKGeneralCollection defaultValue:0];
}

@end
