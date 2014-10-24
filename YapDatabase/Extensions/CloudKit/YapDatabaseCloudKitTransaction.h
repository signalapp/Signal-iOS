#import <Foundation/Foundation.h>
#import "YapDatabaseExtensionTransaction.h"


@interface YapDatabaseCloudKitTransaction : YapDatabaseExtensionTransaction

/**
 * This method is designed to assist in the migration process when switching to YapDatabaseCloudKit.
 * In particular, for the following situation:
 * 
 * - You have an existing object in the database that is associated with a CKRecord
 * - You've been handling CloudKit manually (not via YapDatabaseCloudKit)
 * - You have an existing CKRecord that is up-to-date
 * - And you know want YapDatabaseCloudKit to manage the CKRecord for you
 * 
 * Thus, this methods works as a simple "hand-off" of the CKRecord to the YapDatabaseCloudKit extension.
 *
 * In other words, YapDatbaseCloudKit will write the system fields of the given CKRecord to its internal table,
 * and associate it with the given collection/key tuple.
 * 
 * @param record
 *   The CKRecord to associate with the collection/key tuple.
 * 
 * @param databaseIdentifer
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseBlock.
 *
 * @param key
 *   The key of the row to associaed the record with.
 * 
 * @param collection
 *   The collection of the row to associate the record with.
 * 
 * @param shouldUpload
 *   If NO, then the record is simply associated with the collection/key,
 *     and YapDatabaseCloudKit doesn't attempt to push the record to the cloud.
 *   If YES, then the record is associated with the collection/key ,
 *     and YapDatabaseCloutKit assumes the given record is dirty and attempts to push the record to the cloud.
 * 
 * @return
 *   YES if the record was associated with the given collection/key.
 *   NO if one of the following errors occurred.
 * 
 * The following errors will prevent this method from succeeding:
 * - The given record is nil.
 * - The given collection/key doesn't exist.
 * - The given collection/key is already assiciated with another record.
 * - The recordID/databaseIdentifier is already associated with another collection/key.
 * 
 * Important: This method only works if within a readWriteTrasaction.
 * Invoking this method from within a read-only transaction will throw an exception.
**/
- (BOOL)attachRecord:(CKRecord *)record
  databaseIdentifier:(NSString *)databaseIdentifier
              forKey:(NSString *)key
        inCollection:(NSString *)collection
     andUploadRecord:(BOOL)shouldUpload;

/**
 * This method is designed to assist in various migrations, such as version migrations.
 * In particular, this method allows you to un-associate a row in the database with its current CKRecord,
 * while simultaneously telling YapDatabaseCloudKit NOT to push a delete of the record to the cloud.
 * 
 * For example, in version 2 of your app, you need to move a few CKRecords into a new zone.
 * So you might run this method first in order to drop the associated with the previous record.
 * And then you'd touch the objects in order to create the new CKRecords,
 * and have YapDatabaseCloudKit upload the new records.
**/
- (void)detachRecordForKey:(NSString *)key inCollection:(NSString *)collection;

/**
 * If the given recordID & databaseIdentifier are associated with row in the database,
 * then this method will return YES, and set the collectionPtr/keyPtr with the collection/key of the associated row.
 * 
 * @param keyPtr (optional)
 *   If non-null, and this method returns YES, then the keyPtr will be set to the associated row's key.
 * 
 * @param collectionPtr (optional)
 *   If non-null, and this method returns YES, then the collectionPtr will be set to the associated row's collection.
 * 
 * @param recordID
 *   The CKRecordID to look for.
 * 
 * @param databaseIdentifier
 *   The identifying string for the CKDatabase.
 *   @see YapDatabaseCloudKitDatabaseBlock.
 * 
 * @return
 *   YES if the given recordID & databaseIdentifier are associated with a row in the database.
 *   NO otherwise.
**/
- (BOOL)getKey:(NSString **)keyPtr collection:(NSString **)collectionPtr
                                  forRecordID:(CKRecordID *)recordID
                           databaseIdentifier:(NSString *)databaseIdentifier;

@end
