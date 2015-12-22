#import "Constraints.h"
#import "PropertyListPreferences.h"
#import "TSStorageHeaders.h"

#define SignalDatabaseCollection @"SignalPreferences"


@implementation PropertyListPreferences

- (void)clear {
    @synchronized(self) {
        NSString *appDomain = NSBundle.mainBundle.bundleIdentifier;
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
    }
}

- (id)tryGetValueForKey:(NSString *)key {
    ows_require(key != nil);
    return [TSStorageManager.sharedManager objectForKey:key inCollection:SignalDatabaseCollection];
}
- (void)setValueForKey:(NSString *)key toValue:(id)value {
    ows_require(key != nil);

    [TSStorageManager.sharedManager setObject:value forKey:key inCollection:SignalDatabaseCollection];
}
- (id)adjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id))adjuster {
    ows_require(key != nil);
    ows_require(adjuster != nil);
    @synchronized(self) {
        id oldValue = [self tryGetValueForKey:key];
        id newValue = adjuster(oldValue);
        [self setValueForKey:key toValue:newValue];
        return newValue;
    }
}

@end
