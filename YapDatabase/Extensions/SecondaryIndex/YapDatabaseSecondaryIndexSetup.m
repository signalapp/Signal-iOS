#import "YapDatabaseSecondaryIndexSetup.h"
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
#pragma unused(ydbLogLevel)


NSString* NSStringFromYapDatabaseSecondaryIndexType(YapDatabaseSecondaryIndexType type)
{
	switch (type)
	{
		case YapDatabaseSecondaryIndexTypeInteger : return @"INTEGER";
		case YapDatabaseSecondaryIndexTypeReal    : return @"REAL";
		case YapDatabaseSecondaryIndexTypeNumeric : return @"NUMERIC";
		case YapDatabaseSecondaryIndexTypeText    : return @"TEXT";
		case YapDatabaseSecondaryIndexTypeBlob    : return @"BLOB";
		default                                   : return @"UNKNOWN";
	}
}

@interface YapDatabaseSecondaryIndexColumn ()
- (id)initWithName:(NSString *)name type:(YapDatabaseSecondaryIndexType)type;
@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseSecondaryIndexSetup
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
	
	for (YapDatabaseSecondaryIndexColumn *column in setup)
	{
		if ([column.name caseInsensitiveCompare:columnName] == NSOrderedSame)
		{
			return YES;
		}
	}
	
	return NO;
}

- (void)addColumn:(NSString *)columnName withType:(YapDatabaseSecondaryIndexType)type
{
	if (columnName == nil)
	{
		NSAssert(NO, @"Invalid columnName: nil");
		
		YDBLogError(@"%@: Invalid columnName: nil", THIS_METHOD);
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
	
	if (type != YapDatabaseSecondaryIndexTypeInteger &&
	    type != YapDatabaseSecondaryIndexTypeReal    &&
	    type != YapDatabaseSecondaryIndexTypeNumeric &&
	    type != YapDatabaseSecondaryIndexTypeText    &&
	    type != YapDatabaseSecondaryIndexTypeBlob     )
	{
		NSAssert(NO, @"Invalid type");
		
		YDBLogError(@"%@: Invalid type", THIS_METHOD);
		return;
	}
	
	YapDatabaseSecondaryIndexColumn *column =
	    [[YapDatabaseSecondaryIndexColumn alloc] initWithName:columnName type:type];
	
	[setup addObject:column];
}

- (NSUInteger)count
{
	return [setup count];
}

- (YapDatabaseSecondaryIndexColumn *)columnAtIndex:(NSUInteger)index
{
	if (index < [setup count])
		return [setup objectAtIndex:index];
	else
		return nil;
}

- (NSArray *)columnNames
{
	NSMutableArray *columnNames = [NSMutableArray arrayWithCapacity:[setup count]];
	
	for (YapDatabaseSecondaryIndexColumn *column in setup)
	{
		[columnNames addObject:column.name];
	}
	
	return [columnNames copy];
}

- (id)copyWithZone:(NSZone __unused *)zone
{
	YapDatabaseSecondaryIndexSetup *copy = [[YapDatabaseSecondaryIndexSetup alloc] initForCopy];
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
	
	for (YapDatabaseSecondaryIndexColumn *setupColumn in setup)
	{
		NSString *existingAffinity = [columns objectForKey:setupColumn.name];
		if (existingAffinity == nil)
		{
			return NO;
		}
		else
		{
			if (setupColumn.type == YapDatabaseSecondaryIndexTypeInteger)
			{
				if ([existingAffinity caseInsensitiveCompare:@"INTEGER"] != NSOrderedSame)
					return NO;
			}
			else if (setupColumn.type == YapDatabaseSecondaryIndexTypeReal)
			{
				if ([existingAffinity caseInsensitiveCompare:@"REAL"] != NSOrderedSame)
					return NO;
			}
			else if (setupColumn.type == YapDatabaseSecondaryIndexTypeNumeric)
			{
				if ([existingAffinity caseInsensitiveCompare:@"NUMERIC"] != NSOrderedSame)
					return NO;
			}
			else if (setupColumn.type == YapDatabaseSecondaryIndexTypeText)
			{
				if ([existingAffinity caseInsensitiveCompare:@"TEXT"] != NSOrderedSame)
					return NO;
			}
			else if (setupColumn.type == YapDatabaseSecondaryIndexTypeBlob)
			{
				if ([existingAffinity caseInsensitiveCompare:@"BLOB"] != NSOrderedSame)
					return NO;
			}
		}
	}
	
	return YES;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YapDatabaseSecondaryIndexColumn

@synthesize name = name;
@synthesize type = type;

- (id)initWithName:(NSString *)inName type:(YapDatabaseSecondaryIndexType)inType
{
	if ((self = [super init]))
	{
		name = [inName copy];
		type = inType;
	}
	return self;
}

- (NSString *)description
{
	NSString *typeStr = NSStringFromYapDatabaseSecondaryIndexType(type);
	
	return [NSString stringWithFormat:@"<YapDatabaseSecondaryIndexColumn: name(%@), type(%@)>", name, typeStr];
}

@end
