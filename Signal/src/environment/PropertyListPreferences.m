#import "PropertyListPreferences.h"
#import "Constraints.h"
#import <UICKeyChainStore/UICKeyChainStore.h>

@implementation PropertyListPreferences

-(void) clear {
    @synchronized(self) {
        NSString *appDomain = NSBundle.mainBundle.bundleIdentifier;
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
    }
}

-(id) tryGetValueForKey:(NSString *)key {
    require(key != nil);
    @synchronized(self) {
        return [NSUserDefaults.standardUserDefaults objectForKey:key];
    }
}
-(void) setValueForKey:(NSString *)key toValue:(id)value {
    require(key != nil);
    @synchronized(self) {
        NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
        [userDefaults setObject:value forKey:key];
        [userDefaults synchronize];
    }
}
-(id) adjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id))adjuster {
    require(key != nil);
    require(adjuster != nil);
    @synchronized(self) {
        id oldValue = [self tryGetValueForKey:key];
        id newValue = adjuster(oldValue);
        [self setValueForKey:key toValue:newValue];
        return newValue;
    }
}

#pragma mark KeyChain store

-(void) secureTrySetValueForKey:(NSString *)key toValue:(id)value {
    require(key != nil);
    @synchronized(self) {
        if (value == nil) {
            [UICKeyChainStore removeItemForKey:key];
            DDLogWarn(@"Removing object for key: %@", key);
        } else {
            if ([value isKindOfClass:NSData.class]) {
                [UICKeyChainStore setData:value forKey:key];
            } else if ([value isKindOfClass:NSString.class]){
                [UICKeyChainStore setString:value forKey:key];
            } else{
                DDLogError(@"Unexpected class stored in the Keychain.");
            }
        }
    }
}

-(NSData*) secureTryGetDataForKey:(NSString *)key {
    require(key != nil);
    @synchronized(self) {
        return [UICKeyChainStore dataForKey:key];
    }
}

-(NSString*) secureTryGetStringForKey:(NSString *)key {
    require(key != nil);
    @synchronized(self) {
        return [UICKeyChainStore stringForKey:key];
    }
}

-(NSData*) secureDataStoreAdjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id))adjuster {
    require(key != nil);
    require(adjuster != nil);
    @synchronized(self) {
        NSData* oldValue = [self secureTryGetDataForKey:key];
        NSData* newValue = adjuster(oldValue);
        [UICKeyChainStore setData:newValue forKey:key];
        return newValue;
    }
}

-(NSString*) secureStringStoreAdjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id))adjuster {
    require(key != nil);
    require(adjuster != nil);
    @synchronized(self) {
        NSString *oldValue = [self secureTryGetStringForKey:key];
        NSString *newValue = adjuster(oldValue);
        [UICKeyChainStore setString:newValue forKey:key];
        return newValue;
    }
}


@end
