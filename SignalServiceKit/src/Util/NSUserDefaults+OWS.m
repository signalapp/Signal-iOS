//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSUserDefaults+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSUserDefaults (OWS)

+ (NSUserDefaults *)appUserDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:@"group.org.whispersystems.signal.group"];
}

+ (void)migrateToSharedUserDefaults
{
    NSUserDefaults *appUserDefaults = self.appUserDefaults;

    NSDictionary<NSString *, id> *dictionary = [NSUserDefaults standardUserDefaults].dictionaryRepresentation;
    for (NSString *key in dictionary) {
        id value = dictionary[key];
        OWSAssert(value);
        [appUserDefaults setObject:value forKey:key];
    }
}

+ (void)removeAll
{
    NSString *appDomain = NSBundle.mainBundle.bundleIdentifier;
    [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
    // TODO: How to clear the shared user defaults?
}

@end

NS_ASSUME_NONNULL_END
