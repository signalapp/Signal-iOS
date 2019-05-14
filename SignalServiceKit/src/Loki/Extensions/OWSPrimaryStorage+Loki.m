#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "OWSPrimaryStorage+SignedPreKeyStore.h"
#import "OWSDevice.h"
#import "OWSIdentityManager.h"
#import "TSAccountManager.h"
#import "TSPreKeyManager.h"
#import "YapDatabaseConnection+OWS.h"
#import <AxolotlKit/NSData+keyVersionByte.h>

#define LokiPreKeyContactCollection @"LokiPreKeyContactCollection"
#define LokiPreKeyBundleCollection @"LokiPreKeyBundleCollection"

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
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LokiPreKeyContactCollection];
    return preKeyId > 0;
}

- (PreKeyRecord *)getOrCreatePreKeyForContact:(NSString *)pubKey {
    OWSAssertDebug(pubKey.length > 0);
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LokiPreKeyContactCollection];
    
    // If we don't have an id then generate and store a new one
    if (preKeyId <= 0) {
        return [self generateAndStorePreKeyForContact:pubKey];
    }
    
    // Load the pre key otherwise just generate a new one
    @try {
        return [self throws_loadPreKey:preKeyId];
    } @catch (NSException *exception) {
        OWSLogWarn(@"[Loki] New prekey had to be generated for %@", pubKey);
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
    [self.dbReadWriteConnection setInt:record.Id forKey:pubKey inCollection:LokiPreKeyContactCollection];
    
    return record;
}

# pragma mark - PreKeyBundle

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey {
    // Check prekeys to make sure we have them for this function
    [TSPreKeyManager checkPreKeys];
    
    ECKeyPair *_Nullable keyPair = self.identityManager.identityKeyPair;
    OWSAssertDebug(keyPair);
    
    SignedPreKeyRecord *_Nullable signedPreKey = [self currentSignedPreKey];
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
    return [self.dbReadConnection preKeyBundleForKey:pubKey inCollection:LokiPreKeyBundleCollection];
}

- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction setObject:bundle
                    forKey:pubKey
              inCollection:LokiPreKeyBundleCollection];
}

- (void)removePreKeyBundleForContact:(NSString *)pubKey transaction:(YapDatabaseReadWriteTransaction *)transaction {
    [transaction removeObjectForKey:pubKey inCollection:LokiPreKeyBundleCollection];
}

@end
