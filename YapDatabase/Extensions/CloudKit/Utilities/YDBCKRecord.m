#import "YDBCKRecord.h"

@implementation CKRecord (YapDatabaseCloudKit)

/**
 * Returns a "sanitized" copy of the given record.
 * That is, a copy that ONLY includes the "system fields" of the record.
 * It will NOT contain any key/value pairs from the original record.
**/
- (id)sanitizedCopy
{
	// This is the ONLY way in which I know how to accomplish this task.
	//
	// Other techniques, such as making a copy and removing all the values,
	// ends up giving us a record with a bunch of changedKeys. Not what we want.
	
	return [YDBCKRecord deserializeRecord:[YDBCKRecord serializeRecord:self]];
}

/**
 * Calling [ckRecord copy] is COMPLETELY BROKEN.
 * This is a MAJOR BUG in Apple's CloudKit framework (as I see it).
 *
 * Until this is fixed, we're forced to use this workaround.
**/
- (id)safeCopy
{
	NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
	return [NSKeyedUnarchiver unarchiveObjectWithData:archive];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation YDBCKRecord

/**
 * This method serializes just the "system fields" of the given record.
 * That is, it won't store any of the user-created key/value pairs.
 * It only stores the CloudKit specific stuff, such as the versioning info, syncing info, etc.
**/
+ (NSData *)serializeRecord:(CKRecord *)record
{
	if (record == nil) return nil;
	
	YDBCKRecord *recordWrapper = [[YDBCKRecord alloc] initWithRecord:record];
	return [NSKeyedArchiver archivedDataWithRootObject:recordWrapper];
}

/**
 * Deserialized the given record data.
 *
 * If the record data came from [YDBCKRecord serializeRecord:],
 * then the returned record will only contain the "system fields".
**/
+ (CKRecord *)deserializeRecord:(NSData *)data
{
	if (data)
		return [NSKeyedUnarchiver unarchiveObjectWithData:data];
	else
		return nil;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark YDBCKRecord Class
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize record = record;

- (instancetype)initWithRecord:(CKRecord *)inRecord
{
	if ((self = [super init]))
	{
		record = inRecord;
	}
	return self;
}

- (id)initWithCoder:(NSCoder *)decoder
{
	return nil; // This shouldn't happen, as obj will be decoded as a straight CKRecord object.
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[record encodeSystemFieldsWithCoder:coder];
}

/**
 * When this object is decoded, it should decode it as a straight CKRecord object.
**/
- (Class)classForKeyedArchiver
{
	return [CKRecord class];
}

/**
 * I think this method is largely replaced by classForKeyedArchiver.
 * But it may be used by other 'coders', so it's included just in case.
**/
- (Class)classForCoder
{
	return [CKRecord class];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//#pragma mark YDBCKRecord_KeyedUnarchiver
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//
// This technique can be used to clear the changedKeys property of a CKRecord.
//
/*
@interface YDBCKRecord_KeyedUnarchiver : NSKeyedUnarchiver
@end

@implementation YDBCKRecord_KeyedUnarchiver

+ (id)unarchiveObjectWithData:(NSData *)data
{
	YDBCKRecord_KeyedUnarchiver *unarchiver = [[YDBCKRecord_KeyedUnarchiver alloc] initForReadingWithData:data];
	
	id obj = [unarchiver decodeObjectForKey:NSKeyedArchiveRootObjectKey];
	[unarchiver finishDecoding];
	
	return obj;
}

- (id)decodeObjectForKey:(NSString *)key
{
//	NSLog(@"decodeObjectForKey: %@", key);
	
	if ([key isEqualToString:@"ChangedKeys"])
	{
		// At the time of this writing,
		// CKRecord.changedKeys is a NSMutableSet.
		
		id obj = [super decodeObjectForKey:key];
		return [[[obj class] alloc] init];
	}
	else
	{
		return [super decodeObjectForKey:key];
	}
}

@end
*/
