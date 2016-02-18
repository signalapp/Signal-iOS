#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * This utility class is used by the YapDatabaseCloudKitRecordBlock.
 * It provides metadata about the CKRecord.
 *
 * There are only 4 properties, which can be broken up into 2 sections:
 * 
 * - Properties you can optionally SET (within the recordBlock):
 *
 *   - databaseIdentifier
 *   - originalValues
 * 
 * - Properties you need to CHECK (within the recordBlock):
 * 
 *   - keysToRestore
 *   - versionInfo
**/
@interface YDBCKRecordInfo : NSObject

/**
 * This property allows you to specify the associated CKDatabase for the record.
 * 
 * In order for YapDatabaseCloudKit to be able to upload the CKRecord to the cloud,
 * it must know which CKDatabase the record is associated with.
 * 
 * If unspecified, the private database of the app’s default container is used.
 * That is: [[CKContainer defaultContainer] privateCloudDatabase]
 * 
 * If you want to use a different CKDatabase,
 * then you need to set recordInfo.databaseIdentifier within your recordBlock.
 * 
 * Important:
 *   If you specify a databaseIdentifier here,
 *   then you MUST also configure the YapDatabaseCloudKit instance with a databaseIdentifier block.
 *   Failure to do so will result in an exception.
**/
@property (nonatomic, copy, readwrite, nullable) NSString *databaseIdentifier;

/**
 * If you make changes to the CKRecord, you can optionally choose to store the original key/value pairs.
 * That is, the original key/value pairs for the key(s) that were changed.
 *
 * This dictionary will be stored alongside the modified CKRecord within the queue.
 * And will be made available during merge operations via YDBCKMergeInfo.originalValues.
**/
@property (nonatomic, strong, readwrite, nullable) NSDictionary<NSString *, id> *originalValues;

/**
 * When this property is non-nil, the recordHandler MUST restore the specified keys.
 *
 * YapDatabaseCloudKit uses various storage optimization techniques to reduce disk IO,
 * and reduce the amount of duplicate data that gets stored in the database.
 * Essentially it skips storing any values that are already stored within the original database object(s).
 * And so, if the application quits before all uploads have made it to the CloudKit server,
 * then YapDatabaseCloudKit will need to restore some CKRecords, and may need to restore certain values.
 *
 * You MUST check for this property within your recordHandler implementation.
**/
@property (nonatomic, strong, readonly, nullable) NSArray<NSString *> *keysToRestore;

/**
 * This property comes directly from the [YapDatabaseCloudKit init...] method.
 * 
 * As your application evolves, there may be times that you need to change the CKRecord format.
 * And there are a couple ways in which you can achieve this.
 * 
 * 1. Simply wait until the corresponding object(s) are naturally updated,
 *    and then push the new fields to the cloud at that time.
 * 2. Push all the updated fields for all the objects right away.
 * 
 * The versionInfo is useful in achieving option #2.
 * Here's how it works:
 * 
 * You initialize YapDatabaseCloudKit with an bumped/incremented/changed versionTag,
 * and you also supply versionInfo that relays information you can use within the recordHandler.
 * 
 * When YapDatabaseCloudKit is initialized for the first time (first launch, not subsequent launch),
 * or its versionTag is changed, it will enumerate the objects in the database and invoke the recordHandler.
 * During this enumeration (and only this enumeration) the recordHandler will be passed the versionInfo
 * from the init method. Thus the recordHandler can discern between the initial population/repopulation,
 * and a normal user-initiated readWriteTransaction that's modifying an object in the database.
 * And it can then use the versionInfo to create the proper CKRecord.
**/
@property (nonatomic, strong, readonly) id versionInfo;

@end

NS_ASSUME_NONNULL_END
