//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kOWSTable_DefaultCellHeight;

@class OWSTableItem;
@class OWSTableSection;

@interface OWSTableContents : NSObject

@property (nonatomic) NSString *title;

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

typedef NS_ENUM(NSInteger, OWSTableItemType) {
    OWSTableItemTypeDefault,
    OWSTableItemTypeAction,
};

typedef void (^OWSTableActionBlock)();
typedef UITableViewCell *_Nonnull (^OWSTableCustomCellBlock)();

@interface OWSTableItem : NSObject

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock;

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
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock;

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

- (void)tableViewDidScroll;

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
