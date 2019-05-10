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

# pragma mark - Prekey for contacts

- (BOOL)hasPreKeyForContact:(NSString *)pubKey {
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LokiPreKeyContactCollection];
    return preKeyId > 0;
}

- (PreKeyRecord *)getPreKeyForContact:(NSString *)pubKey {
    OWSAssertDebug(pubKey.length > 0);
    int preKeyId = [self.dbReadWriteConnection intForKey:pubKey inCollection:LokiPreKeyContactCollection];
    
    // If we don't have an id then generate and store a new one
    if (preKeyId < 1) {
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
    PreKeyRecord *record = [records firstObject];
    [self.dbReadWriteConnection setInt:record.Id forKey:pubKey inCollection:LokiPreKeyContactCollection];
    
    return record;
}

# pragma mark - PreKeyBundle

- (PreKeyBundle *)generatePreKeyBundleForContact:(NSString *)pubKey {
    // Check prekeys to make sure we have them for this function
    [TSPreKeyManager checkPreKeys];
    
    ECKeyPair *_Nullable myKeyPair = [[OWSIdentityManager sharedManager] identityKeyPair];
    OWSAssertDebug(myKeyPair);
    
    SignedPreKeyRecord *_Nullable signedPreKey = [self currentSignedPreKey];
    if (!signedPreKey) {
        OWSFailDebug(@"Signed prekey is null");
    }
    
    PreKeyRecord *preKey = [self getPreKeyForContact:pubKey];
    uint32_t registrationId = [[TSAccountManager sharedInstance] getOrGenerateRegistrationId];
    
    PreKeyBundle *bundle = [[PreKeyBundle alloc] initWithRegistrationId:registrationId
                                                               deviceId:OWSDevicePrimaryDeviceId
                                                               preKeyId:preKey.Id
                                                           preKeyPublic:preKey.keyPair.publicKey.prependKeyType
                                                     signedPreKeyPublic:signedPreKey.keyPair.publicKey.prependKeyType
                                                         signedPreKeyId:signedPreKey.Id
                                                  signedPreKeySignature:signedPreKey.signature
                                                            identityKey:myKeyPair.publicKey.prependKeyType];
    return bundle;
}

- (PreKeyBundle *_Nullable)getPreKeyBundleForContact:(NSString *)pubKey {
    PreKeyBundle *bundle = [self.dbReadWriteConnection preKeyBundleForKey:pubKey inCollection:LokiPreKeyBundleCollection];
    return bundle;
}

- (void)setPreKeyBundle:(PreKeyBundle *)bundle forContact:(NSString *)pubKey {
    [self.dbReadWriteConnection setObject:bundle
                                   forKey:pubKey
                             inCollection:LokiPreKeyBundleCollection];
}

@end
