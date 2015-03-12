#import "YDBCKRecordKeysRow.h"
#import <CommonCrypto/CommonDigest.h>


@implementation YDBCKRecordKeysRow

+ (YDBCKRecordKeysRow *)hashRecordKeys:(CKRecord *)record
{
	NSArray *allKeys = record.allKeys;
	
	if (allKeys.count == 0) {
		return nil;
	}
	
	allKeys = [allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *str1, NSString *str2) {
		
		return [str1 compare:str2 options:NSLiteralSearch];
	}];
	
	NSUInteger maxLen = 0;
	
	for (NSString *key in allKeys)
	{
		maxLen = MAX(maxLen, [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
	}
	
	int maxStackSize = 1024 * 2;
	
	uint8_t bufferStack[maxStackSize];
	void *buffer = NULL;
	
	if (maxLen <= maxStackSize)
		buffer = bufferStack;
	else
		buffer = malloc((size_t)maxLen);
	
	CC_SHA1_CTX ctx;
	CC_SHA1_Init(&ctx);
	
	for (NSString *key in allKeys)
	{
		NSUInteger used = 0;
		
		[key getBytes:buffer
		    maxLength:maxLen
		   usedLength:&used
		     encoding:NSUTF8StringEncoding
		      options:0
		        range:NSMakeRange(0, key.length) remainingRange:NULL];
		
		CC_SHA1_Update(&ctx, buffer, (CC_LONG)used);
	}
	
	unsigned char hashBytes[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1_Final(hashBytes, &ctx);
	
	NSData *hashData = [NSData dataWithBytesNoCopy:(void *)hashBytes length:CC_SHA1_DIGEST_LENGTH freeWhenDone:NO];
	NSString *hash = [hashData base64EncodedStringWithOptions:0];
	
	if (maxLen > maxStackSize) {
		free(buffer);
	}
	
	YDBCKRecordKeysRow *row = [[YDBCKRecordKeysRow alloc] initWithHash:hash keys:allKeys];
	return row;
}

@synthesize hash = hash;
@synthesize keys = keys;
@synthesize needsInsert = needsInsert;

- (instancetype)initWithHash:(NSString *)inHash keys:(NSArray *)inKeys
{
	if ((self = [super init]))
	{
		hash = inHash;
		keys = inKeys;
		
		needsInsert = YES;
	}
	return self;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<YDBCKRecordKeysRow[%p] hash=%@ keys=%@>", self, hash, keys];
}

@end
