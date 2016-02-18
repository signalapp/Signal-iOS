#import "YDBCKRecord.h"
#import <Availability.h>

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
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	
	// iOS only
	//
	// I *know* this bug was fixed in iOS 9.
	// I *think* it might have been fixed in iOS 8.X (where X is definitely > 0),
	// I just don't know exactly what the value of X is.
	
	#ifndef __IPHONE_9_0
	#define __IPHONE_9_0 90000
	#endif
	
	#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_9_0
	
		BOOL isIOS9orLater = YES;
	
	#else
	
		NSOperatingSystemVersion ios9_0_0 = (NSOperatingSystemVersion){9, 0, 0};
		BOOL isIOS9orLater = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:ios9_0_0];
	
	#endif
	
	if (isIOS9orLater)
	{
		// iOS 9+
		return [self copy];
	}
	else
	{
		// iOS 8.X
		NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
		return [NSKeyedUnarchiver unarchiveObjectWithData:archive];
	}
	
#elif !TARGET_OS_EMBEDDED
	
	// Mac OS X
	//
	// I *know* this bug was fixed in 10.11.
	// It may have been fixed much earlier than this, but I have no way of testing it.
	
	#ifndef __MAC_10_11
	#define __MAC_10_11 101100
	#endif
	
	#if __MAC_OS_X_VERSION_MIN_REQUIRED >= __MAC_10_11
	
		BOOL isMacOSX10_11orLater = YES;
	
	#else
	
		NSOperatingSystemVersion macosx10_11_0 = (NSOperatingSystemVersion){10, 11, 0};
		BOOL isMacOSX10_11orLater = [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:macosx10_11_0];
	
	#endif
	
	if (isMacOSX10_11orLater)
	{
		// Mac OS X 10.11+
		return [self copy];
	}
	else
	{
		// Mac OS X 10.10.X and below
		NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
		return [NSKeyedUnarchiver unarchiveObjectWithData:archive];
	}
	
#else
	
	NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:self];
	return [NSKeyedUnarchiver unarchiveObjectWithData:archive];

#endif
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
