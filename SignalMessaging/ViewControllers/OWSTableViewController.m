//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"
#import "OWSNavigationController.h"
#import "Theme.h"
#import "UIColor+OWS.h"
#import "UIFont+OWS.h"
#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSTable_DefaultCellHeight = 45.f;

@interface OWSTableContents ()

@property (nonatomic) NSMutableArray<OWSTableSection *> *sections;

@end

#pragma mark -

@implementation OWSTableContents

- (instancetype)init
{
    if (self = [super init]) {
        _sections = [NSMutableArray new];
    }
    return self;
}

- (void)addSection:(OWSTableSection *)section
{
    OWSAssertDebug(section);

    [_sections addObject:section];
}

@end

#pragma mark -

@interface OWSTableSection ()

@property (nonatomic) NSMutableArray<OWSTableItem *> *items;

@end

#pragma mark -

@implementation OWSTableSection

+ (OWSTableSection *)sectionWithTitle:(nullable NSString *)title items:(NSArray<OWSTableItem *> *)items
{
    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = title;
    section.items = [items mutableCopy];
    return section;
}

- (instancetype)init
{
    if (self = [super init]) {
        _items = [NSMutableArray new];
    }
    return self;
}

- (void)addItem:(OWSTableItem *)item
{
    OWSAssertDebug(item);

    [_items addObject:item];
}

- (NSUInteger)itemCount
{
    return _items.count;
}

@end

#pragma mark -

@interface OWSTableItem ()

@property (nonatomic, nullable) NSString *title;
@property (nonatomic, nullable) OWSTableActionBlock actionBlock;

@property (nonatomic) OWSTableCustomCellBlock customCellBlock;
@property (nonatomic) UITableViewCell *customCell;
@property (nonatomic) NSNumber *customRowHeight;

@end

#pragma mark -

@implementation OWSTableItem

+ (UITableViewCell *)newCell
{
    UITableViewCell *cell = [UITableViewCell new];
    [self configureCell:cell];
    return cell;
}

+ (void)configureCell:(UITableViewCell *)cell
{
    cell.backgroundColor = [Theme backgroundColor];
    cell.contentView.backgroundColor = [Theme backgroundColor];
    cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
    cell.textLabel.textColor = [Theme primaryColor];
    cell.detailTextLabel.textColor = [Theme secondaryColor];

    UIView *selectedBackgroundView = [UIView new];
    selectedBackgroundView.backgroundColor = Theme.cellSelectedColor;
    cell.selectedBackgroundView = selectedBackgroundView;
}

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(title.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customCell);
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCell = customCell;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self itemWithCustomCellBlock:customCellBlock actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customCellBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryDisclosureIndicator];
}

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryCheckmark];
}

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.accessoryType = accessoryType;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self disclosureItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                       reuseIdentifier:@"UITableViewCellStyleValue1"];
        [OWSTableItem configureCell:cell];
        cell.textLabel.text = text;
        cell.detailTextLabel.text = detailText;
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        return cell;
    };
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    __weak OWSTableItem *weakItem = item;
    item.actionBlock = ^{
        OWSTableItem *strongItem = weakItem;
        OWSAssertDebug(strongItem);
        OWSAssertDebug(strongItem.tableViewController);

        if (actionBlock) {
            actionBlock(strongItem.tableViewController);
        }
    };
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text
                      customRowHeight:(CGFloat)customRowHeight
                          actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self subPageItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text
{
    OWSAssertDebug(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        // These cells look quite different.
        //
        // Smaller font.
        cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
        // Soft color.
        // TODO: Theme, review with design.
        cell.textLabel.textColor = Theme.middleGrayColor;
        // Centered.
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text customRowHeight:(CGFloat)customRowHeight
{
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self softCenterLabelItemWithText:text];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text
{
    OWSAssertDebug(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text accessoryText:(NSString *)accessoryText
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(accessoryText.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;

        UILabel *accessoryLabel = [UILabel new];
        accessoryLabel.text = accessoryText;
        accessoryLabel.textColor = [Theme secondaryColor];
        accessoryLabel.font = [UIFont ows_regularFontWithSize:16.0f];
        accessoryLabel.textAlignment = NSTextAlignmentRight;
        [accessoryLabel sizeToFit];
        cell.accessoryView = accessoryLabel;

        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text isOn:(BOOL)isOn target:(id)target selector:(SEL)selector
{
    return [self switchItemWithText:text isOn:isOn isEnabled:YES target:target selector:selector];
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                                isOn:(BOOL)isOn
                           isEnabled:(BOOL)isEnabled
                              target:(id)target
                            selector:(SEL)selector
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(target);
    OWSAssertDebug(selector);

    OWSTableItem *item = [OWSTableItem new];
    __weak id weakTarget = target;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        cell.textLabel.text = text;

        UISwitch *cellSwitch = [UISwitch new];
        cell.accessoryView = cellSwitch;
        [cellSwitch setOn:isOn];
        [cellSwitch addTarget:weakTarget action:selector forControlEvents:UIControlEventValueChanged];
        cellSwitch.enabled = isEnabled;

        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        return cell;
    };
    return item;
}

- (nullable UITableViewCell *)customCell
{
    if (_customCell) {
        return _customCell;
    }
    if (_customCellBlock) {
        return _customCellBlock();
    }
    return nil;
}

@end

#pragma mark -

@interface OWSTableViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic) UITableView *tableView;

@end

#pragma mark -

NSString *const kOWSTableCellIdentifier = @"kOWSTableCellIdentifier";

@implementation OWSTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (void)owsTableCommonInit
{
    _contents = [OWSTableContents new];
    self.tableViewStyle = UITableViewStyleGrouped;
}

- (void)loadView
{
    [super loadView];

    OWSAssertDebug(self.contents);

    if (self.contents.title.length > 0) {
        self.title = self.contents.title;
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:self.tableViewStyle];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    [self.view addSubview:self.tableView];

    if ([self.tableView applyScrollViewInsetsFix]) {
        // if applyScrollViewInsetsFix disables contentInsetAdjustmentBehavior,
        // we need to pin to the top and bottom layout guides since UIKit
        // won't adjust our content insets.
        [self.tableView autoPinToTopLayoutGuideOfViewController:self withInset:0];
        [self.tableView autoPinToBottomLayoutGuideOfViewController:self withInset:0];
        [self.tableView autoPinWidthToSuperview];

        // We don't need a top or bottom insets, since we pin to the top and bottom layout guides.
        self.automaticallyAdjustsScrollViewInsets = NO;
    } else {
        [self.tableView autoPinEdgesToSuperviewEdges];
    }

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOWSTableCellIdentifier];

    [self applyTheme];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange:)
                                                 name:ThemeDidChangeNotification
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (OWSTableSection *)sectionForIndex:(NSInteger)sectionIndex
{
    OWSAssertDebug(self.contents);
    OWSAssertDebug(sectionIndex >= 0 && sectionIndex < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)sectionIndex];
    return section;
}

- (OWSTableItem *)itemForIndexPath:(NSIndexPath *)indexPath
{
    OWSAssertDebug(self.contents);
    OWSAssertDebug(indexPath.section >= 0 && indexPath.section < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)indexPath.section];
    OWSAssertDebug(indexPath.item >= 0 && indexPath.item < (NSInteger)section.items.count);
    OWSTableItem *item = section.items[(NSUInteger)indexPath.item];

    return item;
}

- (void)setContents:(OWSTableContents *)contents
{
    OWSAssertDebug(contents);
    OWSAssertIsOnMainThread();

    _contents = contents;

    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    OWSAssertDebug(self.contents);
    return (NSInteger)self.contents.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    OWSAssertDebug(section.items);
    return (NSInteger)section.items.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.headerTitle;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.footerTitle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];

    item.tableViewController = self;

    UITableViewCell *customCell = [item customCell];
    if (customCell) {
        return customCell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOWSTableCellIdentifier];
    OWSAssertDebug(cell);
    [OWSTableItem configureCell:cell];

    cell.textLabel.text = item.title;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.customRowHeight) {
        return [item.customRowHeight floatValue];
    }
    return kOWSTable_DefaultCellHeight;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customHeaderView;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customFooterView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];

    if (!section) {
        OWSFailDebug(@"Section index out of bounds.");
        return 0;
    }

    if (section.customHeaderHeight) {
        OWSAssertDebug([section.customHeaderHeight floatValue] > 0);
        return [section.customHeaderHeight floatValue];
    } else if (section.headerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];
    if (!section) {
        OWSFailDebug(@"Section index out of bounds.");
        return 0;
    }

    if (section.customFooterHeight) {
        OWSAssertDebug([section.customFooterHeight floatValue] > 0);
        return [section.customFooterHeight floatValue];
    } else if (section.footerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (!item.actionBlock) {
        return nil;
    }

    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.actionBlock) {
        item.actionBlock();
    }
}

#pragma mark Index

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    if (self.contents.sectionForSectionIndexTitleBlock) {
        return self.contents.sectionForSectionIndexTitleBlock(title, index);
    } else {
        return 0;
    }
}

- (nullable NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if (self.contents.sectionIndexTitlesForTableViewBlock) {
        return self.contents.sectionIndexTitlesForTableViewBlock();
    } else {
        return 0;
    }
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController
{
    OWSAssertDebug(fromViewController);

    OWSNavigationController *navigationController = [[OWSNavigationController alloc] initWithRootViewController:self];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(donePressed:)];

    [fromViewController presentViewController:navigationController animated:YES completion:nil];
}

- (void)donePressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.delegate tableViewWillBeginDragging];
}

#pragma mark - Theme

- (void)themeDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyTheme];
    [self.tableView reloadData];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    self.view.backgroundColor = Theme.backgroundColor;
    self.tableView.backgroundColor = Theme.backgroundColor;
    self.tableView.separatorColor = Theme.cellSeparatorColor;
}

@end

NS_ASSUME_NONNULL_END
