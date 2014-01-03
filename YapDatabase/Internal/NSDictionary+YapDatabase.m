#import "NSDictionary+YapDatabase.h"


@implementation NSDictionary (YapDatabase)

/**
 * Originally I named this method simply 'containsKey:'.
 * But then immediately got a stack overflow when using the category.
 * 
 * Apparently Apple's code actually registers the 'containsKey:' method in the objective-c space.
 * And invoking CFDictionaryContainsKey results in a method call back to our 'containsKey:' method,
 * and thus we get an infinite loop.
**/
- (BOOL)ydb_containsKey:(id)key
{
	return CFDictionaryContainsKey((CFDictionaryRef)self, (const void *)key);
}

@end
