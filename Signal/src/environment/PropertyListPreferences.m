#import "PropertyListPreferences.h"
#import "Constraints.h"
#import "TSStorageManager.h"

#define SignalDatabaseCollection @"SignalPreferences"

@implementation PropertyListPreferences

-(void) clear {
    @synchronized(self) {
        NSString *appDomain = NSBundle.mainBundle.bundleIdentifier;
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
    }
}

- (id)tryGetValueForKey:(NSString *)key {
    require(key != nil);
    return [TSStorageManager.sharedManager objectForKey:key inCollection:SignalDatabaseCollection];
}
- (void)setValueForKey:(NSString *)key toValue:(id)value {
    require(key != nil);
    
    [TSStorageManager.sharedManager setObject:value forKey:key inCollection:SignalDatabaseCollection];
}
- (id)adjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id))adjuster {
    require(key != nil);
    require(adjuster != nil);
    @synchronized(self) {
        id oldValue = [self tryGetValueForKey:key];
        id newValue = adjuster(oldValue);
        [self setValueForKey:key toValue:newValue];
        return newValue;
    }
}



@end
