#import "BenchmarkYapDatabase.h"
#import "YapDatabase.h"

#import <stdlib.h>


@implementation BenchmarkYapDatabase

static YapDatabase *database;
static YapDatabaseConnection *connection;

static NSMutableArray *keys;

+ (NSString *)databaseName
{
	return @"BenchmarkYapDatabase.sqlite";
}

+ (NSString *)databasePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	return [baseDir stringByAppendingPathComponent:[self databaseName]];
}

+ (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		uint32_t randomIndex = arc4random_uniform((uint32_t)alphabetLength);
		unichar c = [alphabet characterAtIndex:(NSUInteger)randomIndex];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

+ (void)generateKeys:(NSUInteger)count
{
	if (keys == nil)
		keys = [[NSMutableArray alloc] initWithCapacity:count];
	else
		[keys removeAllObjects];
	
	for (NSUInteger i = 0; i < count; i++)
	{
		[keys addObject:[self randomLetters:24]];
	}
}

+ (void)populateDatabase
{
	NSDate *start = [NSDate date];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (NSString *key in keys)
		{
			// For now, use key for object.
			// Later we need to test with bigger objects with more serialization overhead.
			
			[transaction setObject:key forKey:key inCollection:nil];
		}
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Populate database: total time: %.6f, added items: %lu", elapsed, (unsigned long)[keys count]);
}

+ (void)enumerateDatabase
{
	NSDate *start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[transaction enumerateKeysInAllCollectionsUsingBlock:^(NSString __unused *collection, NSString __unused *key, BOOL __unused *stop) {
			
			// Nothing to do, just testing overhead
		}];
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Enumerate keys: total time: %.6f, database count: %lu", elapsed, (unsigned long)[keys count]);
	
	start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[transaction enumerateKeysAndObjectsInAllCollectionsUsingBlock:
		    ^(NSString __unused *collection, NSString __unused *key, id __unused object, BOOL __unused *stop) {
			
			// Nothing to do, just testing overhead
		}];
	}];
	
	elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Enumerate keys & objects: total time: %.6f, database count: %lu", elapsed, (unsigned long)[keys count]);
}

+ (void)fetchValuesInLoop:(NSUInteger)loopCount withCacheHitPercentage:(float)hitPercentage
{
	// Generate a random list of keys to fetch which satisfies the requested hit percentage
	
	NSUInteger cacheSize = connection.objectCacheLimit;
	NSAssert(cacheSize < loopCount, @"Can't satisfy hitPercentage because cacheSize is too big");
	
	NSMutableOrderedSet *keysInCache = [NSMutableOrderedSet orderedSetWithCapacity:cacheSize];
	NSMutableArray *keysToFetch = [NSMutableArray arrayWithCapacity:loopCount];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		float rand = arc4random_uniform(1000) / 1000.0F;
		
		if ((rand < hitPercentage) && ([keysInCache count] > 0))
		{
			// Pick a random key in the cache
			
			uint32_t randomIndex = arc4random_uniform((uint32_t)[keysInCache count]);
			NSString *key = [keysInCache objectAtIndex:(NSUInteger)randomIndex];
			
			[keysToFetch addObject:key];
			
			[keysInCache removeObject:key];
			[keysInCache insertObject:key atIndex:0];
		}
		else
		{
			// Pick a random key NOT in the cache
			
			BOOL found = NO;
			do {
				
				uint32_t randomIndex = arc4random_uniform((uint32_t)[keys count]);
				NSString *key = [keys objectAtIndex:(NSUInteger)randomIndex];
				
				if (![keysInCache containsObject:key])
				{
					found = YES;
					
					[keysToFetch addObject:key];
					
					[keysInCache insertObject:key atIndex:0];
					if ([keysInCache count] > cacheSize) {
						[keysInCache removeObjectAtIndex:cacheSize];
					}
				}
				
			} while (!found);
		}
	}
	
	// Execute fetches
	
	NSDate *start = [NSDate date];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		for (NSString *key in keysToFetch)
		{
			(void)[transaction objectForKey:key inCollection:nil];
		}
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	
	double avg = (elapsed / loopCount);
	double perSec = 1.0 / avg;
	
	NSLog(@"Fetch %lu random objs (cache hit %%: %.2f): total time: %.6f, avg time per obj: %.6f, obj per sec: %.0f",
		  (unsigned long)loopCount, hitPercentage, elapsed, avg, perSec);
}

+ (void)readTransactionOverhead:(NSUInteger)loopCount withLongLivedReadTransaction:(BOOL)useLongLivedReadTransaction
{
	if (useLongLivedReadTransaction) {
		[connection beginLongLivedReadTransaction];
	}
	
	NSDate *start = [NSDate date];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		[connection readWithBlock:^(YapDatabaseReadTransaction __unused *transaction) {
			
			// Nothing to do, just testing overhead
		}];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	if (useLongLivedReadTransaction)
		NSLog(@"ReadOnly transaction overhead : %.8f  (using longLivedReadTransaction)", (elapsed / loopCount));
	else
		NSLog(@"ReadOnly transaction overhead : %.8f", (elapsed / loopCount));
	
	if (useLongLivedReadTransaction) {
		[connection endLongLivedReadTransaction];
	}
}

+ (void)readWriteTransactionOverhead:(NSUInteger)loopCount
{
	NSDate *start = [NSDate date];
	
	for (NSUInteger i = 0; i < loopCount; i++)
	{
		[connection readWriteWithBlock:^(YapDatabaseReadTransaction __unused *transaction) {
			
			// Nothing to do, just testing overhead
		}];
	}
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"ReadWrite transaction overhead: %.8f", (elapsed / loopCount));
}

+ (void)removeAllValues
{
	NSDate *start = [NSDate date];
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction removeAllObjectsInAllCollections];
	}];
	
	NSTimeInterval elapsed = [start timeIntervalSinceNow] * -1.0;
	NSLog(@"Remove all transaction: total time: %.6f", elapsed);
}

+ (void)runTestsWithCompletion:(dispatch_block_t)completionBlock
{
	NSString *databasePath = [self databasePath];
	
	// Delete old database file (if exists)
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	
	// Create database
	YapDatabaseOptions *options = [[YapDatabaseOptions alloc] init];
//	options.pragmaSynchronous = YapDatabasePragmaSynchronous_Normal; // Use for faster speed
//	options.pragmaSynchronous = YapDatabasePragmaSynchronous_Off;    // Use for fastest speed

	options.pragmaMMapSize = (1024 * 1024 * 25); // full file size, with max of 25 MB
	
	database = [[YapDatabase alloc] initWithPath:databasePath
	                                  serializer:NULL
	                                deserializer:NULL
	                                     options:options];
	
	// Create database connection (can have multiple for concurrency)
	connection = [database newConnection];
	connection.objectCacheLimit = 250; // default size
	
	// Setup
	[self generateKeys:1000];
	
	// Run tests
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSString *pragmaSynchronousStr;
		switch(options.pragmaSynchronous)
		{
			case YapDatabasePragmaSynchronous_Off    : pragmaSynchronousStr = @"Off";     break;
			case YapDatabasePragmaSynchronous_Normal : pragmaSynchronousStr = @"Normal";  break;
			case YapDatabasePragmaSynchronous_Full   : pragmaSynchronousStr = @"Full";    break;
			default                                  : pragmaSynchronousStr = @"Unknown"; break;
		}
		
		NSLog(@" \n\n\n ");
		NSLog(@"YapDatabase Benchmarks:");
		NSLog(@" - sqlite version     = %@", database.sqliteVersion);
		NSLog(@" - pragma synchronous = %@", pragmaSynchronousStr);
		NSLog(@" - pragma mmap_size   = %ld", (long)[connection pragmaMMapSize]);
		NSLog(@"====================================================");
		NSLog(@"POPULATE DATABASE");
		
		[self populateDatabase];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"ENUMERATE DATABASE");
		
		[self enumerateDatabase];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"FETCH DATABASE");
		
		[self fetchValuesInLoop:500 withCacheHitPercentage:0.05f];
		[self fetchValuesInLoop:500 withCacheHitPercentage:0.25f];
		[self fetchValuesInLoop:500 withCacheHitPercentage:0.50f];
		[self fetchValuesInLoop:500 withCacheHitPercentage:0.75f];
		[self fetchValuesInLoop:500 withCacheHitPercentage:0.95f];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"TRANSACTION OVERHEAD");
		
		[self readTransactionOverhead:1000 withLongLivedReadTransaction:YES];
		[self readTransactionOverhead:1000 withLongLivedReadTransaction:NO];
		[self readWriteTransactionOverhead:1000];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		NSLog(@"REMOVE ALL");
		
		[self removeAllValues];
		
		NSLog(@"====================================================");
	});
	dispatch_async(dispatch_get_main_queue(), ^{
		
		database = nil;
		connection = nil;
		keys = nil;
		
		completionBlock();
	});
}

@end
