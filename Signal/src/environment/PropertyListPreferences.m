#import "PropertyListPreferences.h"
#import "Constraints.h"

@implementation PropertyListPreferences

+(PropertyListPreferences*) propertyListPreferencesWithName:(NSString*)name {
    PropertyListPreferences* p = [PropertyListPreferences new];
    p->plistName = name;
    p->dictionary = [[PropertyListPreferences readPlist:name] mutableCopy];
    return p;
}

-(void) clear {
    @synchronized(self) {
        dictionary = [NSMutableDictionary dictionary];
        [PropertyListPreferences writePlist:dictionary withName:plistName];
    }
}
+(NSDictionary*) readPlist:(NSString*)name {require(name != nil);
    NSString* documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"/Documents/"];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist", documentsDirectory, name];
    
    NSData *plistData = [NSData dataWithContentsOfFile:path];
    // assume empty dictionary, if no data
    if (plistData == nil) return @{};
    
    NSString *error;
    NSPropertyListFormat format;
    id plist = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
    checkOperationDescribe(plist != nil, ([NSString stringWithFormat:@"Error parsing plist data: %@", error]));
    checkOperationDescribe([plist isKindOfClass:[NSDictionary class]], @"Plist file didn't contain a dictionary");
    
    return plist;
}  
+(void) writePlist:(NSDictionary*)plist withName:(NSString*)name {
    NSString *errorDesc;
    NSData* xmlData = [NSPropertyListSerialization dataFromPropertyList:plist format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorDesc];
    checkOperationDescribe(xmlData != nil, ([NSString stringWithFormat:@"Error serializing plist: %@", errorDesc]));

    NSError* error;
    NSString* documentsDirectory = [NSHomeDirectory() stringByAppendingPathComponent:@"/Documents/"];
    NSString *path = [NSString stringWithFormat:@"%@/%@.plist",documentsDirectory,name];
    bool written = [xmlData writeToFile:path options:NSDataWritingAtomic error:&error];
    checkOperationDescribe(written, ([NSString stringWithFormat:@"Error atomically writing plist to file: %@", error]));
}

-(id) tryGetValueForKey:(NSString *)key {
    require(key != nil);
    @synchronized(self) {
        return [dictionary objectForKey:key];
    }
}
-(void) setValueForKey:(NSString *)key toValue:(id)value {
    require(key != nil);
    @synchronized(self) {
        if (value == nil) {
            [dictionary removeObjectForKey:key];
        } else {
            [dictionary setObject:value forKey:key];
        }
        [PropertyListPreferences writePlist:dictionary withName:plistName];
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

@end
