//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

@property (nonatomic, nullable) NSAttributedString *headerAttributedTitle;
@property (nonatomic, nullable) NSAttributedString *footerAttributedTitle;

@property (nonatomic, nullable) UIView *customHeaderView;
@property (nonatomic, nullable) UIView *customFooterView;
@property (nonatomic, nullable) NSNumber *customHeaderHeight;
@property (nonatomic, nullable) NSNumber *customFooterHeight;

+ (OWSTableSection *)sectionWithTitle:(nullable NSString *)title items:(NSArray<OWSTableItem *> *)items;

- (void)addItem:(OWSTableItem *)item;

- (void)addItems:(NSArray<OWSTableItem *> *)items;

- (NSUInteger)itemCount;

@end

#pragma mark -

typedef void (^OWSTableActionBlock)(void);
typedef void (^OWSTableSubPageBlock)(UIViewController *viewController);
typedef UITableViewCell *_Nonnull (^OWSTableCustomCellBlock)(void);
typedef BOOL (^OWSTableSwitchBlock)(void);

@interface OWSTableItemEditAction : NSObject

@property (nonatomic) OWSTableActionBlock block;
@property (nonatomic) NSString *title;

+ (OWSTableItemEditAction *)actionWithTitle:(nullable NSString *)title block:(OWSTableActionBlock)block;

@end

#pragma mark -

@interface OWSTableItem : NSObject

@property (nonatomic, weak) UIViewController *tableViewController;
@property (nonatomic, nullable) OWSTableItemEditAction *deleteAction;
@property (nonatomic, nullable) NSNumber *customRowHeight;

+ (UITableViewCell *)newCell;
+ (void)configureCell:(UITableViewCell *)cell;

+ (OWSTableItem *)itemWithTitle:(NSString *)title
                    actionBlock:(nullable OWSTableActionBlock)actionBlock NS_SWIFT_NAME(init(title:actionBlock:));

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text
                accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                            actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType;

+ (OWSTableItem *)subPageItemWithText:(NSString *)text actionBlock:(nullable OWSTableSubPageBlock)actionBlock;

+ (OWSTableItem *)subPageItemWithText:(NSString *)text
                      customRowHeight:(CGFloat)customRowHeight
                          actionBlock:(nullable OWSTableSubPageBlock)actionBlock;

+ (OWSTableItem *)actionItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)actionItemWithText:(NSString *)text
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)actionItemWithText:(NSString *)text
                           textColor:(nullable UIColor *)textColor
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)actionItemWithText:(NSString *)text
                      accessoryImage:(UIImage *)accessoryImage
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text;

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text customRowHeight:(CGFloat)customRowHeight;

+ (OWSTableItem *)labelItemWithText:(NSString *)text;

+ (OWSTableItem *)labelItemWithText:(NSString *)text accessoryText:(NSString *)accessoryText;

+ (OWSTableItem *)longDisclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock;

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                              target:(id)target
                            selector:(SEL)selector;

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                      isEnabledBlock:(OWSTableSwitchBlock)isEnabledBlock
                              target:(id)target
                            selector:(SEL)selector;

+ (OWSTableItem *)switchItemWithText:(NSString *)text
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                      isEnabledBlock:(OWSTableSwitchBlock)isEnabledBlock
                              target:(id)target
                            selector:(SEL)selector;

- (nullable UITableViewCell *)customCell;

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

@property (nonatomic) BOOL useThemeBackgroundColors;

@property (nonatomic, nullable) UIColor *customSectionHeaderFooterBackgroundColor;

- (instancetype)init NS_DESIGNATED_INITIALIZER;

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController;

- (void)applyTheme;

@end

NS_ASSUME_NONNULL_END
