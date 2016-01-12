#import "AppDelegate.h"

#import "BenchmarkYapCache.h"
#import "BenchmarkYapDatabase.h"

#import <YapDatabase/YapDatabase.h>
#import <YapDatabase/YapDatabaseRelationshipPrivate.h>


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	
}

@synthesize databaseBenchmarksButton = databaseBenchmarksButton;
@synthesize cacheBenchmarksButton = cacheBenchmarksButton;

- (IBAction)runDatabaseBenchmarks:(id)sender
{
	databaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapDatabase runTestsWithCompletion:^{
			
			databaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

- (IBAction)runCacheBenchmarks:(id)sender
{
	databaseBenchmarksButton.enabled = NO;
	cacheBenchmarksButton.enabled = NO;
	
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		
		[BenchmarkYapCache runTestsWithCompletion:^{
			
			databaseBenchmarksButton.enabled = YES;
			cacheBenchmarksButton.enabled = YES;
		}];
	});
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Debugging
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)databaseFilePath
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (appName == nil) {
		appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
	}
	
	NSString *appSupportDir = [basePath stringByAppendingPathComponent:appName];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (![fileManager fileExistsAtPath:appSupportDir])
	{
		[fileManager createDirectoryAtPath:appSupportDir withIntermediateDirectories:YES attributes:nil error:nil];
	}
	
	NSString *fileName = @"test.sqlite";
	return [appSupportDir stringByAppendingPathComponent:fileName];
}

- (NSString *)randomLetters:(NSUInteger)length
{
	NSString *alphabet = @"abcdefghijklmnopqrstuvwxyz";
	NSUInteger alphabetLength = [alphabet length];
	
	NSMutableString *result = [NSMutableString stringWithCapacity:length];
	
	NSUInteger i;
	for (i = 0; i < length; i++)
	{
		unichar c = [alphabet characterAtIndex:(NSUInteger)arc4random_uniform((uint32_t)alphabetLength)];
		
		[result appendFormat:@"%C", c];
	}
	
	return result;
}

- (NSURL *)generateRandomFile
{
	NSURL *baseURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory
	                                                        inDomain:NSUserDomainMask
	                                               appropriateForURL:nil
	                                                          create:YES
	                                                           error:NULL];
	
	NSString *fileName = [self randomLetters:16];
	NSURL *fileURL = [baseURL URLByAppendingPathComponent:fileName isDirectory:NO];
	
	// Create the temp file
	[[NSFileManager defaultManager] createFileAtPath:[fileURL path] contents:nil attributes:nil];
	
	return fileURL;
}

- (void)testRelationshipMigration
{
	NSString *databaseFilePath = [self databaseFilePath];
	NSLog(@"databaseFilePath: %@", databaseFilePath);
	
	[[NSFileManager defaultManager] removeItemAtPath:databaseFilePath error:NULL];
	
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databaseFilePath];
	YapDatabaseConnection *connection = [database newConnection];
	
	NSString *rowA = @"a";
	NSString *rowB = @"b";
	NSString *rowC = @"c";
	NSString *rowD = @"d";
	
	#pragma unused(rowB)
	#pragma unused(rowC)
	#pragma unused(rowD)
	
#if YAP_DATABASE_RELATIONSHIP_CLASS_VERSION < 4
	
	NSURL *fileC = [self generateRandomFile];
	NSURL *fileD = [self generateRandomFile];
	
#endif
	
	// rowA -> rowB
	// rowC -> fileC
	// rowD -> fileD
	
	YapDatabaseRelationshipOptions *options = [[YapDatabaseRelationshipOptions alloc] init];
	
	YapDatabaseRelationship *relationship = [[YapDatabaseRelationship alloc] initWithVersionTag:nil options:options];
	
	BOOL result = [database registerExtension:relationship withName:@"relationhip"];
	if (!result)
	{
		NSLog(@"Oops !");
		return;
	}
	
#if YAP_DATABASE_RELATIONSHIP_CLASS_VERSION < 4
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		[transaction setObject:rowA forKey:rowA inCollection:nil];
		[transaction setObject:rowB forKey:rowB inCollection:nil];
		[transaction setObject:rowC forKey:rowC inCollection:nil];
		[transaction setObject:rowD forKey:rowD inCollection:nil];
		
		YapDatabaseRelationshipEdge *edgeAB =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:rowA
		                                 collection:nil
		                             destinationKey:rowB
		                                 collection:nil
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		YapDatabaseRelationshipEdge *edgeC =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:rowC
		                                 collection:nil
		                         destinationFileURL:fileC
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		YapDatabaseRelationshipEdge *edgeD =
		  [YapDatabaseRelationshipEdge edgeWithName:@"child"
		                                  sourceKey:rowD
		                                 collection:nil
		                         destinationFileURL:fileD
		                            nodeDeleteRules:YDB_DeleteDestinationIfSourceDeleted];
		
		[[transaction ext:@"relationhip"] addEdge:edgeAB];
		[[transaction ext:@"relationhip"] addEdge:edgeC];
		[[transaction ext:@"relationhip"] addEdge:edgeD];
	}];
	
#else
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		[[transaction ext:@"relationship"] enumerateEdgesWithName:@"child"
		                                                sourceKey:rowA
		                                               collection:nil
		                                               usingBlock:^(YapDatabaseRelationshipEdge *edge, BOOL *stop)
		{
			NSLog(@"edge: %@", edge);
		}];
	}];
	
#endif
}

@end
