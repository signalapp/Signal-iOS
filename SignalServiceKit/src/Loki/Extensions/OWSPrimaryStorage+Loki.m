#import "OWSPrimaryStorage+Loki.h"
#import "OWSPrimaryStorage+PreKeyStore.h"
#import "YapDatabaseConnection+OWS.h"

#define LokiPreKeyContactCollection @"LokiPreKeyContactCollection"

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

@end
