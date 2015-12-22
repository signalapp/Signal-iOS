#import <Foundation/Foundation.h>

@interface PropertyListPreferences : NSObject

- (id)tryGetValueForKey:(NSString *)key;
- (void)setValueForKey:(NSString *)key toValue:(id)value;
- (id)adjustAndTryGetNewValueForKey:(NSString *)key afterAdjuster:(id (^)(id oldValue))adjuster;
- (void)clear;

@end
