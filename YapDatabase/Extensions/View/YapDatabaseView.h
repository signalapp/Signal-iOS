#import <Foundation/Foundation.h>

#import "YapDatabase.h"
#import "YapDatabaseExtension.h"

#import "YapDatabaseViewConnection.h"
#import "YapDatabaseViewTransaction.h"
#import "YapDatabaseViewOptions.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * YapDatabaseView is an abstract class that implements the underlying logic for several subclasses:
 *
 * - YapDatabaseAutoView
 * - YapDatabaseManualView
 * - YapDatabaseMultiView
**/
@interface YapDatabaseView : YapDatabaseExtension

/**
 * The versionTag assists you in updating the view configuration.
 *
 * For example, if you need to change the groupingBlock or sortingBlock,
 * then simply pass a different versionTag during the init method, and the view will automatically update itself.
 * 
 * If you want to keep things simple, you can use something like @"1",
 * representing version 1 of my groupingBlock & sortingBlock.
 * 
 * For more advanced applications, you may also include within the versionTag string:
 * - localization information (if you're using localized sorting routines)
 * - configuration information (if your sorting routine is based on some in-app configuration)
 *
 * For example, if you're sorting strings using a localized string compare method, then embedding the localization
 * information into your versionTag means the view will automatically re-populate itself (re-sort)
 * if the user launches the app in a different language than last time.
 * 
 * NSString *localeIdentifier = [[NSLocale currentLocale] localeIdentifier];
 * NSString *versionTag = [NSString stringWithFormat:@"1-%@", localeIdentifier];
 * 
 * The groupingBlock/sortingBlock/versionTag can me changed after the view has been created.
 * See YapDatabaseViewTransaction(ReadWrite).
 * 
 * Note:
 * - [YapDatabaseView versionTag]            = versionTag of most recent commit
 * - [YapDatabaseViewTransaction versionTag] = versionTag of this commit
**/
@property (nonatomic, copy, readonly) NSString *versionTag;

/**
 * The options allow you to specify things like creating an in-memory-only view (non persistent).
**/
@property (nonatomic, copy, readonly) YapDatabaseViewOptions *options;

/**
 * Allows you to fetch the versionTag from a view that was registered during the last app launch.
 * 
 * For example, let's say you have a view that sorts contacts.
 * And you support 2 different sort options:
 * - First, Last
 * - Last, First
 * 
 * To support this, you use 2 different versionTags:
 * - "First,Last"
 * - "Last,First"
 * 
 * And you want to ensure that when you first register the view (during app launch),
 * you choose the same block & versionTag from a previous app launch (if possible).
 * This prevents the view from enumerating the database & re-populating itself
 * during registration if the versionTag is different from last time.
 * 
 * So you can use this method to fetch the previous versionTag.
**/
+ (NSString *)previousVersionTagForRegisteredViewName:(NSString *)name
                                      withTransaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END