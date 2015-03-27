#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseExtension.h"
#import "YapWhitelistBlacklist.h"

/**
 * WillInsert & DidInsert
 * 
 * An insert means that the collection/key tuple does not currently exist in the database.
 * So the object & metadata items are getting inserted / added.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
**/
typedef void (^YDBHooks_WillInsertObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object, id metadata);

typedef void (^YDBHooks_DidInsertObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object, id metadata);

/**
 * WillUpdate & DidUpdate
 * 
 * An update means that the collection/key tuple currently exists in the database.
 * So the object & metadata items are getting changed to the given values.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * - setObject:forKey:inCollection:withMetadata:serializedObject:serializedMetadata:
**/

typedef void (^YDBHooks_WillUpdateObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object, id metadata);

typedef void (^YDBHooks_DidUpdateObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object, id metadata);

/**
 * WillReplaceObject & DidReplaceObject
 *
 * Replace means that the collection/key tuple currently exists in the database.
 * Furthermore, only the object is getting changed.
 * Whatever value the metadata was before isn't being modified.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceObject:forKey:inCollection:
 * - replaceObject:forKey:inCollection:withSerializedObject:
**/

typedef void (^YDBHooks_WillReplaceObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object);

typedef void (^YDBHooks_DidReplaceObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id object);

/**
 * WillReplaceMetadata & DidReplaceMetadata
 * 
 * Replace means that the collection/key tuple currently exists in the database.
 * Furthermore, only the metadata is getting changed.
 * Whatever value the object was before isn't being modified.
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - replaceMetadata:forKey:inCollection:
 * - replaceMetadata:forKey:inCollection:withSerializedMetadata:
**/

typedef void (^YDBHooks_WillReplaceMetadata)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id metadata);

typedef void (^YDBHooks_DidReplaceMetadata)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key, id metadata);

/**
 * WillRemoveObject & DidRemoveObject
 * 
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectForKey:inCollection:
**/

typedef void (^YDBHooks_WillRemoveObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key);

typedef void (^YDBHooks_DidRemoveObject)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSString *key);

/**
 * WillRemoveObjects & DidRemoveObjects
 *
 * Note: If removeObjectsForKeys:inCollection: is invoked with a particularly large array,
 * then YapDatabase may invoke these methods multiple times because it may split the large array
 * into multiple smaller arrays.
 *
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeObjectsForKeys:inCollection:
 * - removeAllObjectsInCollection:
**/

typedef void (^YDBHooks_WillRemoveObjects)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSArray *keys);

typedef void (^YDBHooks_DidRemoveObjects)
  (YapDatabaseReadWriteTransaction *transaction, NSString *collection, NSArray *keys);

/**
 * Corresponds to the following method(s) in YapDatabaseReadWriteTransaction:
 * - removeAllObjectsInAllCollections
**/

typedef void (^YDBHooks_WillRemoveAllObjectsInAllCollections)
  (YapDatabaseReadWriteTransaction *transaction);

typedef void (^YDBHooks_DidRemoveAllObjectsInAllCollections)
  (YapDatabaseReadWriteTransaction *transaction);




@interface YapDatabaseHooks : YapDatabaseExtension

- (instancetype)init;

/**
 * All properties must be set BEFORE the extension is registered.
 * Once registered, the properties become immutable.
**/

@property (atomic, strong, readwrite) YapWhitelistBlacklist *allowedCollections;

@property (atomic, strong, readwrite) YDBHooks_WillInsertObject willInsertObject;
@property (atomic, strong, readwrite) YDBHooks_DidInsertObject   didInsertObject;

@property (atomic, strong, readwrite) YDBHooks_WillUpdateObject willUpdateObject;
@property (atomic, strong, readwrite) YDBHooks_DidInsertObject   didUpdateObject;

@property (atomic, strong, readwrite) YDBHooks_WillReplaceObject willReplaceObject;
@property (atomic, strong, readwrite) YDBHooks_DidReplaceObject   didReplaceObject;

@property (atomic, strong, readwrite) YDBHooks_WillReplaceMetadata willReplaceMetadata;
@property (atomic, strong, readwrite) YDBHooks_DidReplaceMetadata   didReplaceMetadata;

@property (atomic, strong, readwrite) YDBHooks_WillRemoveObject willRemoveObject;
@property (atomic, strong, readwrite) YDBHooks_DidRemoveObject   didRemoveObject;

@property (atomic, strong, readwrite) YDBHooks_WillRemoveObjects willRemoveObjects;
@property (atomic, strong, readwrite) YDBHooks_DidRemoveObjects   didRemoveObjects;

@property (atomic, strong, readwrite) YDBHooks_WillRemoveAllObjectsInAllCollections willRemoveAllObjectsInAllCollections;
@property (atomic, strong, readwrite) YDBHooks_DidRemoveAllObjectsInAllCollections didRemoveAllObjectsInAllCollections;

@end
