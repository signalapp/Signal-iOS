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

#define OWSPrimaryStoragePreKeyStoreCollection @"TSStorageManagerPreKeyStoreCollection"
#define LKPreKeyContactCollection @"LKPreKeyContactCollection"
#define LKPreKeyBundleCollection @"LKPreKeyBundleCollection"
#define LKLastMessageHashCollection @"LKLastMessageHashCollection"
#define LKReceivedMessageHashesKey @"LKReceivedMessageHashesKey"
#define LKReceivedMessageHashesCollection @"LKReceivedMessageHashesCollection"

@implementation OWSPrimaryStorage (Loki)

# pragma mark - Dependencies

- (OWSIdentityManager *)identityManager {
    return OWSIdentityManager.sharedManager;
}

- (TSAccountManager *)accountManager {
    return TSAccountManager.sharedInstance;
}

# pragma mark - Prekey for Contact

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
        NSLog(@"[Loki] New prekey generated for %@.", pubKey);
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

# pragma mark - PreKeyBundle

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey {
    // Check prekeys to make sure we have them for this function
    [TSPreKeyManager checkPreKeys];
    
    ECKeyPair *_Nullable keyPair = self.identityManager.identityKeyPair;
    OWSAssertDebug(keyPair);
    
    SignedPreKeyRecord *_Nullable signedPreKey = self.currentSignedPreKey;
    if (!signedPreKey) {
        OWSFailDebug(@"Signed prekey is null");
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

- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)pubKey {
    return [self.dbReadConnection preKeyBundleForKey:pubKey inCollection:LKPreKeyBundleCollection];
}

- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction setObject:bundle
                    forKey:pubKey
              inCollection:LKPreKeyBundleCollection];
}

- (void)removePreKeyBundleForContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction removeObjectForKey:pubKey inCollection:LKPreKeyBundleCollection];
}

# pragma mark - Last Hash

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

@end
