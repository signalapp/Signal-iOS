#import "NSDictionary+YapDatabase.h"


@implementation NSDictionary (YapDatabase)

- (BOOL)containsKey:(id)key
{
	return CFDictionaryContainsKey((CFDictionaryRef)self, (const void *)key);
}

@end
