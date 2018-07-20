//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <SignalMessaging/OWSViewController.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSTable_DefaultCellHeight;

@class OWSTableItem;
@class OWSTableSection;

@interface OWSTableContents : NSObject

@property (nonatomic) NSString *title;
@property (nonatomic, nullable) NSInteger (^sectionForSectionIndexTitleBlock)(NSString *title, NSInteger index);
@property (nonatomic, nullable) NSArray<NSString *> * (^sectionIndexTitlesForTableViewBlock)(void);

@property (nonatomic, readonly) NSArray<OWSTableSection *> *sections;
- (void)addSection:(OWSTableSection *)section;

@end

#pragma mark -

@interface OWSTableSection : NSObject

@property (nonatomic, nullable) NSString *headerTitle;
@property (nonatomic, nullable) NSString *footerTitle;

@property (nonatomic, nullable) UIView *customHeaderView;
@property (nonatomic, nullable) UIView *customFooterView;
@property (nonatomic, nullable) NSNumber *customHeaderHeight;
@property (nonatomic, nullable) NSNumber *customFooterHeight;

+ (OWSTableSection *)sectionWithTitle:(nullable NSString *)title items:(NSArray<OWSTableItem *> *)items;

- (void)addItem:(OWSTableItem *)item;

- (NSUInteger)itemCount;

@end

#pragma mark -

typedef void (^OWSTableActionBlock)(void);
typedef void (^OWSTableSubPageBlock)(UIViewController *viewController);
typedef UITableViewCell *_Nonnull (^OWSTableCustomCellBlock)(void);

@interface OWSTableItem : NSObject

@property (nonatomic, weak) UIViewController *tableViewController;

+ (UITableViewCell *)newCell;
+ (void)configureCell:(UITableViewCell *)cell;

+ (OWSTableItem *)itemWithTitle:(NSString *)title
                    actionBlock:(nullable OWSTableActionBlock)actionBlock NS_SWIFT_NAME(init(title:actionBlock:));

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType;

+ (OWSTableItem *)subPageItemWithText:(NSString *)text actionBlock:(nullable OWSTableSubPageBlock)actionBlock;

+ (OWSTableItem *)subPageItemWithText:(NSString *)text
                      customRowHeight:(CGFloat)customRowHeight
                          actionBlock:(nullable OWSTableSubPageBlock)actionBlock;

+ (OWSTableItem *)actionItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text;

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text customRowHeight:(CGFloat)customRowHeight;

+ (OWSTableItem *)labelItemWithText:(NSString *)text;

+ (OWSTableItem *)labelItemWithText:(NSString *)text accessoryText:(NSString *)accessoryText;

+ (OWSTableItem *)switchItemWithText:(NSString *)text isOn:(BOOL)isOn target:(id)target selector:(SEL)selector;

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                                isOn:(BOOL)isOn
                           isEnabled:(BOOL)isEnabled
                              target:(id)target
                            selector:(SEL)selector;

- (nullable UITableViewCell *)customCell;
- (NSNumber *)customRowHeight;

@end

#pragma mark -

@protocol OWSTableViewControllerDelegate <NSObject>

- (void)tableViewWillBeginDragging;

@end

#pragma mark -

@interface OWSTableViewController : OWSViewController

@property (nonatomic, weak) id<OWSTableViewControllerDelegate> delegate;

@property (nonatomic) OWSTableContents *contents;
@property (nonatomic, readonly) UITableView *tableView;

@property (nonatomic) UITableViewStyle tableViewStyle;

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController;

@end

NS_ASSUME_NONNULL_END
