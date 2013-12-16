#import <Foundation/Foundation.h>

enum {
	YDB_NotifyIfSourceDeleted      = 1 << 0,
	YDB_NotifyIfDestinationDeleted = 1 << 1,
	
	// one-to-one
	YDB_DeleteSourceIfDestinationDeleted = 1 << 2,
	YDB_DeleteDestinationIfSourceDeleted = 1 << 3,
	
	// one-to-many & many-to-many
	YDB_DeleteSourceIfAllDestinationsDeleted = 1 << 4,
	YDB_DeleteDestinationIfAllSourcesDeleted = 1 << 5,
};
typedef int YDB_NodeDeleteRules;


@interface YapDatabaseRelationshipEdge : NSObject <NSCoding, NSCopying>

+ (instancetype)edgeWithName:(NSString *)name
              destinationKey:(NSString *)key
                  collection:(NSString *)collection
             nodeDeleteRules:(YDB_NodeDeleteRules)rules;

- (id)initWithName:(NSString *)name
    destinationKey:(NSString *)key
        collection:(NSString *)collection
   nodeDeleteRules:(YDB_NodeDeleteRules)rules;

@property (nonatomic, copy, readonly) NSString *name;

@property (nonatomic, copy, readonly) NSString *sourceKey;
@property (nonatomic, copy, readonly) NSString *sourceCollection;

@property (nonatomic, copy, readonly) NSString *destinationKey;
@property (nonatomic, copy, readonly) NSString *destinationCollection;

@property (nonatomic, assign, readonly) YDB_NodeDeleteRules nodeDeleteRules;

@end
