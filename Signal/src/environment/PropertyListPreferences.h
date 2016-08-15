@interface PropertyListPreferences : NSObject

- (id)tryGetValueForKey:(NSString *)key;
- (void)setValueForKey:(NSString *)key toValue:(id)value;
- (void)clear;

@end
