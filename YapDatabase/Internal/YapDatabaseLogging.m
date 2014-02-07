#import "YapDatabaseLogging.h"


#if YapDatabaseLoggingTechnique != YapDatabaseLoggingTechnique_Lumberjack

/**
 * This method is based on CocoaLumberjack's DDExtractFileNameWithoutExtension function.
 * The copy option has been removed, as we only use __FILE__ as the filePath parameter.
**/
NSString *YDBExtractFileNameWithoutExtension(const char *filePath)
{
	if (filePath == NULL) return nil;
	
	char *lastSlash = NULL;
	char *lastDot = NULL;
	
	char *p = (char *)filePath;
	
	while (*p != '\0')
	{
		if (*p == '/')
			lastSlash = p;
		else if (*p == '.')
			lastDot = p;
		
		p++;
	}
	
	char *subStr;
	NSUInteger subLen;
	
	if (lastSlash)
	{
		if (lastDot)
		{
			// lastSlash -> lastDot
			subStr = lastSlash + 1;
			subLen = lastDot - subStr;
		}
		else
		{
			// lastSlash -> endOfString
			subStr = lastSlash + 1;
			subLen = p - subStr;
		}
	}
	else
	{
		if (lastDot)
		{
			// startOfString -> lastDot
			subStr = (char *)filePath;
			subLen = lastDot - subStr;
		}
		else
		{
			// startOfString -> endOfString
			subStr = (char *)filePath;
			subLen = p - subStr;
		}
	}
	
	// We can take advantage of the fact that __FILE__ is a string literal.
	// Specifically, we don't need to waste time copying the string.
	// We can just tell NSString to point to a range within the string literal.
	
	return [[NSString alloc] initWithBytesNoCopy:subStr
	                                      length:subLen
	                                    encoding:NSUTF8StringEncoding
	                                freeWhenDone:NO];
}

#endif
