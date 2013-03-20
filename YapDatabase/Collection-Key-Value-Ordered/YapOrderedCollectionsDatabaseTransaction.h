#import <Foundation/Foundation.h>


/**
 * The implementation of this protocol will wrap YapCollectionsDatabaseReadTransaction.
 * So you'll have access to all the methods in YapCollectionsDatabaseReadTransaction.
**/
@protocol YapOrderedCollectionsReadTransaction <NSObject>

#pragma mark Count

/**
 * Returns a full list of keys, sorted by the order in which the keys were explicitly appended/prepended/inserted.
 * 
 * This method is similar to allKeysInCollection, but ordered.
**/
- (NSArray *)orderedKeysInCollection:(NSString *)collection;

/**
 * Equivalent to calling [[transaction orderedKeysInCollection:collection] count],
 * but performs faster.
**/
- (NSUInteger)orderedKeysCountInCollection:(NSString *)collection;

/**
 * Equivalent to calling [[transaction orderedKeysInCollection:collection] subarrayWithRange:range],
 * but performs faster.
**/
- (NSArray *)keysInRange:(NSRange)range collection:(NSString *)collection;

#pragma mark Index

/**
 * Returns the key/object/metadata at the index in the given collection.
**/
- (NSString *)keyAtIndex:(NSUInteger)index inCollection:(NSString *)collection;
- (id)objectAtIndex:(NSUInteger)index inCollection:(NSString *)collection;
- (id)metadataAtIndex:(NSUInteger)index inCollection:(NSString *)collection;

#pragma mark Enumerate

/**
 * Extremely fast in-memory enumeration over keys (in their set order) and associated metadata in the database.
 * You can enumerate all key/metadata pairs, or only a given range.
 * 
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
**/
- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                        withOptions:(NSEnumerationOptions)options
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndMetadataOrderedInCollection:(NSString *)collection
                                              range:(NSRange)range
                                        withOptions:(NSEnumerationOptions)options
                                         usingBlock:
                (void (^)(NSUInteger index, NSString *key, id metadata, BOOL *stop))block;

/**
 * Allows you to enumerate the objects in their set order.
 * You can enumerate all key/object pairs, or only a given range.
 * 
 * Reverse enumeration is supported by passing NSEnumerationReverse. (No other enumeration options are supported.)
 * 
 * Note: If order does NOT matter, you can get a small performance increase by using the
 * non-ordered enumeration methods in the superclass (YapDatabase).
**/
- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                       withOptions:(NSEnumerationOptions)options
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

- (void)enumerateKeysAndObjectsOrderedInCollection:(NSString *)collection
                                             range:(NSRange)range
                                       withOptions:(NSEnumerationOptions)options
                                        usingBlock:
                (void (^)(NSUInteger index, NSString *key, id object, id metadata, BOOL *stop))block;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Implementations of this protocol will wrap YapCollectionsDatabaseReadWriteTransaction.
 * So you'll have access to all the methods in YapCollectionsDatabaseReadWriteTransaction,
 * with the exception of the following:
 * 
 * - setObject:forKey:inCollection:
 * - setObject:forKey:inCollection:withMetadata:
 * 
 * Invoking these methods will throw a MethodNotAvailable exception as they don't provide ordering information.
 * These methods have been replaced with:
 * 
 * - appendObject:forKey:withMetadata:
 * - prependObject:forKey:withMetadata:
 * - insertObject:atIndex:forKey:withMetadata:
 * - updateObject:forKey:withMetadata:
**/
@protocol YapOrderedCollectionsReadWriteTransaction <YapOrderedCollectionsReadTransaction>

/**
 * These methods replace setObject:forKey:inCollection:, and allow you to specify ordering information.
 *
 * Append  - adds the object to the end of the list.
 * Prepend - adds the object to the beginning of the list.
 * Insert  - adds the object at the given index of the list.
 * Update  - updates in-place the object. If given key/collection pair doesn't already exist, does nothing.
**/
- (void)appendObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)appendObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata;

- (void)prependObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)prependObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata;

- (void)insertObject:(id)object atIndex:(NSUInteger)index forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)insertObject:(id)object
             atIndex:(NSUInteger)index
              forKey:(NSString *)key
        inCollection:(NSString *)collection
        withMetadata:(id)metadata;

- (void)updateObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection;
- (void)updateObject:(id)object forKey:(NSString *)key inCollection:(NSString *)collection withMetadata:(id)metadata;

/**
 * Allows you to remove objects with ordering information (using indexes).
**/
- (void)removeObjectAtIndex:(NSUInteger)index inCollection:(NSString *)collection;
- (void)removeObjectsInRange:(NSRange)range collection:(NSString *)collection;

@end
