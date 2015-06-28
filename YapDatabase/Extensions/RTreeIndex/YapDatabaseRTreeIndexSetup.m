#import "YapDatabaseRTreeIndexSetup.h"
#import "YapDatabaseLogging.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

/**
 * Define log level for this file: OFF, ERROR, WARN, INFO, VERBOSE
 * See YapDatabaseLogging.h for more information.
 **/
#if DEBUG
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#else
  static const int ydbLogLevel = YDB_LOG_LEVEL_WARN;
#endif


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseRTreeIndexSetup
{
	NSMutableArray *setup;
}

- (id)init
{
	return [self initWithCapacity:0];
}

- (id)initWithCapacity:(NSUInteger)capacity
{
	if ((self = [super init]))
	{
		if (capacity > 0)
			setup = [[NSMutableArray alloc] initWithCapacity:capacity];
		else
			setup = [[NSMutableArray alloc] init];
	}
	return self;
}

- (id)initForCopy
{
	self = [super init];
	return self;
}

- (BOOL)isReservedName:(NSString *)columnName
{
	if ([columnName caseInsensitiveCompare:@"rowid"] == NSOrderedSame)
		return YES;

	if ([columnName caseInsensitiveCompare:@"oid"] == NSOrderedSame)
		return YES;

	if ([columnName caseInsensitiveCompare:@"_rowid_"] == NSOrderedSame)
		return YES;

	return NO;
}

- (BOOL)isExistingName:(NSString *)columnName
{
	// SQLite column names are not case sensitive.

	for (NSString *existingColumnName in setup)
	{
		if ([existingColumnName caseInsensitiveCompare:columnName] == NSOrderedSame)
		{
			return YES;
		}
	}

	return NO;
}

- (void)setColumns:(NSArray *)columnNames
{
	if (columnNames == nil)
	{
		NSAssert(NO, @"Invalid columnNames: nil");

		YDBLogError(@"%@: Invalid columnNames: nil", THIS_METHOD);
		return;
	}

    if (columnNames.count % 2 != 0 || columnNames.count < 2 || columnNames.count > 10) {
        NSAssert(NO, @"Invalid columnNames: columnNames should have 2 to 10 columns, and be even");
        
        YDBLogError(@"Invalid columnNames: columnNames should have 2 to 10 columns, and be even");
        return;
    }
    
    for (id columnName in columnNames) {
        if (![columnName isKindOfClass:[NSString class]]) {
            NSAssert(NO, @"Invalid columnName: columnName must be a string");
            
            YDBLogError(@"Invalid columnName: columnName must be a string");
            return;
        }

        if ([self isReservedName:columnName])
        {
            NSAssert(NO, @"Invalid columnName: columnName is reserved");
            
            YDBLogError(@"Invalid columnName: columnName is reserved");
            return;
        }
        
        if ([self isExistingName:columnName])
        {
            NSAssert(NO, @"Invalid columnName: columnName already exists");
            
            YDBLogError(@"Invalid columnName: columnName already exists");
            return;
        }
    }

    [setup setArray:columnNames];
}

- (NSUInteger)count
{
    return [setup count];
}

- (NSArray *)columnNames
{
	return [setup copy];
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseRTreeIndexSetup *copy = [[YapDatabaseRTreeIndexSetup alloc] initForCopy];
	copy->setup = [setup mutableCopy];

	return copy;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state
                                  objects:(__unsafe_unretained id [])buffer
                                    count:(NSUInteger)length
{
	return [setup countByEnumeratingWithState:state objects:buffer count:length];
}

/**
 * The columns parameter comes from:
 * [YapDatabase columnNamesAndAffinityForTable:using:]
**/
- (BOOL)matchesExistingColumnNamesAndAffinity:(NSDictionary *)columns
{
	// The columns parameter will include the 'rowid' column, which we need to ignore.

	if (([setup count] + 1) != [columns count])
	{
		return NO;
	}

	for (NSString *columnName in setup)
	{
		NSString *existingAffinity = [columns objectForKey:columnName];
		if (existingAffinity == nil)
		{
			return NO;
		}
		else
		{
            if ([existingAffinity caseInsensitiveCompare:@"REAL"] != NSOrderedSame)
                return NO;
		}
	}

	return YES;
}

@end
