//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSTableViewController.h"
#import "Theme.h"
#import "UIFont+OWS.h"
#import "UIView+SignalUI.h"
#import <SignalUI/SignalUI-Swift.h>

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
        _hasSeparators = YES;
        _hasBackground = YES;
    }
    return self;
}

- (void)addItem:(OWSTableItem *)item
{
    OWSAssertDebug(item);

    [_items addObject:item];
}

- (void)addItems:(NSArray<OWSTableItem *> *)items
{
    for (OWSTableItem *item in items) {
        [self addItem:item];
    }
}

- (NSUInteger)itemCount
{
    return _items.count;
}

@end

#pragma mark -

@implementation OWSTableItemEditAction

+ (OWSTableItemEditAction *)actionWithTitle:(nullable NSString *)title block:(OWSTableActionBlock)block
{
    OWSTableItemEditAction *action = [OWSTableItemEditAction new];
    action.title = title;
    action.block = block;
    return action;
}

@end

#pragma mark -

@interface OWSTableItem ()

@property (nonatomic, nullable) NSString *title;
@property (nonatomic, nullable) OWSTableActionBlock actionBlock;

@property (nonatomic) OWSTableCustomCellBlock customCellBlock;
@property (nonatomic) OWSTableDequeueCellBlock dequeueCellBlock;

@end

#pragma mark -

@implementation OWSTableItem

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.customRowHeight = @(UITableViewAutomaticDimension);

    return self;
}

+ (UITableViewCell *)newCell
{
    UITableViewCell *cell = [UITableViewCell new];
    [self configureCell:cell];
    return cell;
}

+ (void)configureCellLabels:(UITableViewCell *)cell
{
    cell.textLabel.font = OWSTableItem.primaryLabelFont;
    cell.textLabel.textColor = Theme.primaryTextColor;
    cell.detailTextLabel.textColor = Theme.secondaryTextAndIconColor;
    cell.detailTextLabel.font = OWSTableItem.accessoryLabelFont;
}

+ (void)configureCell:(UITableViewCell *)cell
{
    UIView *selectedBackgroundView = [UIView new];
    cell.selectedBackgroundView = selectedBackgroundView;
    cell.backgroundColor = Theme.backgroundColor;
    cell.selectedBackgroundView.backgroundColor = Theme.tableCell2SelectedBackgroundColor;
    cell.multipleSelectionBackgroundView.backgroundColor = Theme.tableCell2MultiSelectedBackgroundColor;

    [self configureCellLabels:cell];
}

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(title.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithCustomCellBlock:customCellBlock
                         customRowHeight:UITableViewAutomaticDimension
                             actionBlock:actionBlock];
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customCellBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithDequeueCellBlock:(OWSTableDequeueCellBlock)dequeueCellBlock
                               actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.dequeueCellBlock = dequeueCellBlock;
    item.customRowHeight = @(UITableViewAutomaticDimension);
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryDisclosureIndicator];
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text
        accessibilityIdentifier:accessibilityIdentifier
                    actionBlock:actionBlock
                  accessoryType:UITableViewCellAccessoryDisclosureIndicator];
}

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self checkmarkItemWithText:text accessibilityIdentifier:nil actionBlock:actionBlock];
}

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text
                accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                            actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text
        accessibilityIdentifier:accessibilityIdentifier
                    actionBlock:actionBlock
                  accessoryType:UITableViewCellAccessoryCheckmark];
}

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType
{
    return [self itemWithText:text accessibilityIdentifier:nil actionBlock:actionBlock accessoryType:accessoryType];
}

+ (OWSTableItem *)itemWithText:(NSString *)text
       accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        return [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                           textColor:nil
                                                       accessoryText:nil
                                                       accessoryType:accessoryType
                                                      accessoryImage:nil
                                             accessibilityIdentifier:accessibilityIdentifier];
    };
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self disclosureItemWithText:text
                accessibilityIdentifier:nil
                        customRowHeight:customRowHeight
                            actionBlock:actionBlock];
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(customRowHeight > 0 || customRowHeight == UITableViewAutomaticDimension);

    OWSTableItem *item = [self disclosureItemWithText:text
                              accessibilityIdentifier:accessibilityIdentifier
                                          actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self disclosureItemWithText:text detailText:detailText accessibilityIdentifier:nil actionBlock:actionBlock];
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                              detailText:(NSString *)detailText
                 accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        return [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                           textColor:nil
                                                       accessoryText:detailText
                                                       accessoryType:UITableViewCellAccessoryDisclosureIndicator
                                                      accessoryImage:nil
                                             accessibilityIdentifier:accessibilityIdentifier];
    };
    item.customRowHeight = @(UITableViewAutomaticDimension);
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
        return [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                           textColor:nil
                                                       accessoryText:nil
                                                       accessoryType:UITableViewCellAccessoryDisclosureIndicator
                                                      accessoryImage:nil
                                             accessibilityIdentifier:nil];
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
    return [self actionItemWithText:text accessibilityIdentifier:nil actionBlock:actionBlock];
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self actionItemWithText:text
                          textColor:nil
            accessibilityIdentifier:accessibilityIdentifier
                        actionBlock:actionBlock];
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text
                           textColor:(nullable UIColor *)textColor
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        return [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                           textColor:textColor
                                                       accessoryText:nil
                                                       accessoryType:UITableViewCellAccessoryNone
                                                      accessoryImage:nil
                                             accessibilityIdentifier:accessibilityIdentifier];
    };
    return item;
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text
                      accessoryImage:(UIImage *)accessoryImage
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(accessoryImage);

    OWSTableItem *item = [OWSTableItem new];
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        return [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                           textColor:nil
                                                       accessoryText:nil
                                                       accessoryType:UITableViewCellAccessoryNone
                                                      accessoryImage:accessoryImage
                                             accessibilityIdentifier:accessibilityIdentifier];
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text
{
    OWSAssertDebug(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];
        UILabel *textLabel = [UILabel new];
        textLabel.text = text;
        // These cells look quite different.
        //
        // Smaller font.
        textLabel.font = OWSTableItem.primaryLabelFont;
        // Soft color.
        // TODO: Theme, review with design.
        textLabel.textColor = Theme.middleGrayColor;
        // Centered.
        textLabel.textAlignment = NSTextAlignmentCenter;
        [cell.contentView addSubview:textLabel];
        [textLabel autoPinEdgesToSuperviewMargins];
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
        UITableViewCell *cell = [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                                            textColor:nil
                                                                        accessoryText:nil
                                                                        accessoryType:UITableViewCellAccessoryNone
                                                                       accessoryImage:nil
                                                              accessibilityIdentifier:nil];
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
        UITableViewCell *cell = [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                                            textColor:nil
                                                                        accessoryText:accessoryText
                                                                        accessoryType:UITableViewCellAccessoryNone
                                                                       accessoryImage:nil
                                                              accessibilityIdentifier:nil];
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)longDisclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssertDebug(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem newCell];

        UILabel *textLabel = [UILabel new];
        textLabel.text = text;
        textLabel.numberOfLines = 0;
        textLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [cell.contentView addSubview:textLabel];
        [textLabel autoPinEdgesToSuperviewMargins];

        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        return cell;
    };
    item.customRowHeight = @(UITableViewAutomaticDimension);
    item.actionBlock = actionBlock;
    return item;
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                              target:(id)target
                            selector:(SEL)selector
{
    return [self switchItemWithText:text
                          isOnBlock:(OWSTableSwitchBlock)isOnBlock
                     isEnabledBlock:^{ return YES; }
                             target:target
                           selector:selector];
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                      isEnabledBlock:(OWSTableSwitchBlock)isEnabledBlock
                              target:(id)target
                            selector:(SEL)selector
{
    return [self switchItemWithText:text
            accessibilityIdentifier:nil
                          isOnBlock:isOnBlock
                     isEnabledBlock:isEnabledBlock
                             target:target
                           selector:selector];
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
             accessibilityIdentifier:(nullable NSString *)accessibilityIdentifier
                           isOnBlock:(OWSTableSwitchBlock)isOnBlock
                      isEnabledBlock:(OWSTableSwitchBlock)isEnabledBlock
                              target:(id)target
                            selector:(SEL)selector
{
    OWSAssertDebug(text.length > 0);
    OWSAssertDebug(target);
    OWSAssertDebug(selector);

    OWSTableItem *item = [OWSTableItem new];
    __weak id weakTarget = target;
    item.customCellBlock = ^{
        UITableViewCell *cell = [OWSTableItem buildCellWithAccessoryLabelWithItemName:text
                                                                            textColor:nil
                                                                        accessoryText:nil
                                                                        accessoryType:UITableViewCellAccessoryNone
                                                                       accessoryImage:nil
                                                              accessibilityIdentifier:accessibilityIdentifier];

        UISwitch *cellSwitch = [UISwitch new];
        cell.accessoryView = cellSwitch;
        [cellSwitch setOn:isOnBlock()];
        [cellSwitch addTarget:weakTarget action:selector forControlEvents:UIControlEventValueChanged];
        cellSwitch.enabled = isEnabledBlock();
        cellSwitch.accessibilityIdentifier = accessibilityIdentifier;

        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        return cell;
    };
    item.customRowHeight = @(UITableViewAutomaticDimension);
    return item;
}

- (nullable UITableViewCell *)getOrBuildCustomCell:(UITableView *)tableView
{
    if (_customCellBlock) {
        OWSAssertDebug(_dequeueCellBlock == nil);
        return _customCellBlock();
    }
    if (_dequeueCellBlock) {
        return _dequeueCellBlock(tableView);
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

    _contents = [OWSTableContents new];

    return self;
}

- (void)loadView
{
    [super loadView];

    OWSAssertDebug(self.contents);

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

    [self.view addSubview:self.tableView];

    if (self.shouldAvoidKeyboard) {
        [self.tableView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsZero excludingEdge:ALEdgeBottom];
        [self autoPinViewToBottomOfViewControllerOrKeyboard:self.tableView avoidNotch:YES];
    } else {
        [self.tableView autoPinEdgesToSuperviewEdges];
    }

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOWSTableCellIdentifier];

    [self configureTableLayoutMargins];
    [self applyContents];
    [self applyTheme];

    // Reload when dynamic type settings change.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(uiContentSizeCategoryDidChange:)
                                                 name:UIContentSizeCategoryDidChangeNotification
                                               object:nil];
}

- (void)uiContentSizeCategoryDidChange:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    [self applyContents];
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

    if (contents != _contents) {
        _contents = contents;
        [self applyContents];
    }
}

- (void)applyContents
{
    if (self.contents.title.length > 0) {
        self.title = self.contents.title;
    }
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

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];

    item.tableViewController = self;

    UITableViewCell *_Nullable customCell = [item getOrBuildCustomCell:self.tableView];
    if (customCell != nil) {
        if (self.useThemeBackgroundColors) {
            customCell.backgroundColor = Theme.tableCellBackgroundColor;
        }
        return customCell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOWSTableCellIdentifier];
    OWSAssertDebug(cell);
    [OWSTableItem configureCell:cell];

    cell.textLabel.text = item.title;

    if (self.useThemeBackgroundColors) {
        customCell.backgroundColor = Theme.tableCellBackgroundColor;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.customRowHeight != nil) {
        return [item.customRowHeight floatValue];
    }
    return kOWSTable_DefaultCellHeight;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];

    if (section.customHeaderView) {
        return section.customHeaderView;
    } else if (section.headerTitle.length > 0 || section.headerAttributedTitle.length > 0) {
        UITextView *textView = [LinkingTextView new];
        textView.textColor = Theme.secondaryTextAndIconColor;
        textView.font = UIFont.ows_dynamicTypeCaption1Font;
        if (section.headerAttributedTitle.length > 0) {
            textView.attributedText = section.headerAttributedTitle;
        } else {
            textView.text = [section.headerTitle uppercaseString];
        }

        UIView *sectionView = [[UIView alloc] init];
        [sectionView addSubview:textView];
        [textView autoPinHeightToSuperview];

        if (self.layoutMarginsRelativeTableContent) {
            sectionView.preservesSuperviewLayoutMargins = YES;
            [textView autoPinWidthToSuperviewMargins];
            textView.textContainerInset = UIEdgeInsetsMake(16, 0, 6, 0);
        } else {
            [textView autoPinWidthToSuperview];
            CGFloat tableEdgeInsets = UIDevice.currentDevice.isPlusSizePhone ? 20 : 16;
            textView.textContainerInset = UIEdgeInsetsMake(16, tableEdgeInsets, 6, tableEdgeInsets);
        }
        return sectionView;
    }

    return nil;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];

    if (section.customFooterView) {
        return section.customFooterView;
    } else if (section.footerTitle.length > 0 || section.footerAttributedTitle.length > 0) {
        UITextView *textView = [LinkingTextView new];
        textView.textColor = UIColor.ows_gray45Color;
        textView.font = UIFont.ows_dynamicTypeCaption1Font;
        textView.linkTextAttributes = @{
            NSForegroundColorAttributeName : Theme.accentBlueColor,
            NSUnderlineStyleAttributeName : @(NSUnderlineStyleNone),
            NSFontAttributeName : UIFont.ows_dynamicTypeCaption1Font,
        };

        if (section.footerAttributedTitle.length > 0) {
            textView.attributedText = section.footerAttributedTitle;
        } else {
            textView.text = section.footerTitle;
        }

        UIView *sectionView = [[UIView alloc] init];
        [sectionView addSubview:textView];
        [textView autoPinHeightToSuperview];

        if (self.layoutMarginsRelativeTableContent) {
            sectionView.preservesSuperviewLayoutMargins = YES;
            [textView autoPinWidthToSuperviewMargins];
            textView.textContainerInset = UIEdgeInsetsMake(6, 0, 12, 0);
        } else {
            [textView autoPinWidthToSuperview];
            CGFloat tableEdgeInsets = UIDevice.currentDevice.isPlusSizePhone ? 20 : 16;
            textView.textContainerInset = UIEdgeInsetsMake(6, tableEdgeInsets, 12, tableEdgeInsets);
        }
        return sectionView;
    }

    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];

    if (!section) {
        OWSFailDebug(@"Section index out of bounds.");
        return 0;
    }

    if (section.customHeaderHeight) {
        OWSAssertDebug([section.customHeaderHeight floatValue] > 0 ||
            [section.customHeaderHeight floatValue] == UITableViewAutomaticDimension);
        return [section.customHeaderHeight floatValue];
    } else {
        UIView *_Nullable view = [self tableView:tableView viewForHeaderInSection:sectionIndex];
        if (view) {
            return UITableViewAutomaticDimension;
        } else {
            return 0;
        }
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
        OWSAssertDebug([section.customFooterHeight floatValue] > 0 ||
            [section.customFooterHeight floatValue] == UITableViewAutomaticDimension);
        return [section.customFooterHeight floatValue];
    } else {
        UIView *_Nullable view = [self tableView:tableView viewForFooterInSection:sectionIndex];
        if (view) {
            return UITableViewAutomaticDimension;
        } else {
            return 0;
        }
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

- (void)themeDidChange
{
    OWSAssertIsOnMainThread();

    [super themeDidChange];

    [self.tableView reloadData];
}

- (void)setUseThemeBackgroundColors:(BOOL)useThemeBackgroundColors
{
    _useThemeBackgroundColors = useThemeBackgroundColors;

    [self applyTheme];
}

- (void)applyTheme
{
    OWSAssertIsOnMainThread();

    [super applyTheme];

    UIColor *backgroundColor = (self.useThemeBackgroundColors ? Theme.tableViewBackgroundColor : Theme.backgroundColor);
    self.view.backgroundColor = backgroundColor;
    self.tableView.backgroundColor = backgroundColor;
    self.tableView.separatorColor = Theme.cellSeparatorColor;
}

- (void)configureTableLayoutMargins
{
    if (!self.layoutMarginsRelativeTableContent) {
        return;
    }
    self.tableView.preservesSuperviewLayoutMargins = YES;
    self.tableView.layoutMargins = UIEdgeInsetsZero;
}

#pragma mark - Editing

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.deleteAction != nil) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    return item.deleteAction != nil;
}

- (nullable NSString *)tableView:(UITableView *)tableView
    titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    return item.deleteAction.title;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (editingStyle == UITableViewCellEditingStyleDelete && item.deleteAction != nil) {
        item.deleteAction.block();
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated
{
    [super setEditing:editing animated:animated];
    [self.tableView setEditing:editing animated:animated];
}

- (void)setEditing:(BOOL)editing
{
    [super setEditing:editing];
    [self.tableView setEditing:editing];
}

@end

NS_ASSUME_NONNULL_END
