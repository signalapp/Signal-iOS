//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

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
    OWSAssert(section);
    
    [_sections addObject:section];
}

@end

#pragma mark -

@interface OWSTableSection ()

@property (nonatomic) NSMutableArray<OWSTableItem *> *items;

@end

#pragma mark -

@implementation OWSTableSection

+ (OWSTableSection *)sectionWithTitle:(NSString *)title items:(NSArray<OWSTableItem *> *)items
{
    OWSTableSection *section = [OWSTableSection new];
    section.title = title;
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
    OWSAssert(item);

    [_items addObject:item];
}

@end

#pragma mark -

@interface OWSTableItem ()

@property (nonatomic) OWSTableItemType itemType;
@property (nonatomic, nullable) NSString *title;
@property (nonatomic, nullable) OWSTableActionBlock actionBlock;

@property (nonatomic) OWSTableCustomCellBlock customCellBlock;
@property (nonatomic) UITableViewCell *customCell;
@property (nonatomic) NSNumber *customRowHeight;

@end

#pragma mark -

@implementation OWSTableItem

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(title.length > 0);
    
    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCell);
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = (actionBlock != nil ? OWSTableItemTypeAction : OWSTableItemTypeDefault);
    item.actionBlock = actionBlock;
    item.customCell = customCell;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCellBlock);
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = (actionBlock != nil ? OWSTableItemTypeAction : OWSTableItemTypeDefault);
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCellBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = (actionBlock != nil ? OWSTableItemTypeAction : OWSTableItemTypeDefault);
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    return item;
}

- (UITableViewCell *)customCell
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

NSString * const kOWSTableCellIdentifier = @"kOWSTableCellIdentifier";

@implementation OWSTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];
}

- (instancetype)init
{
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)loadView
{
    [super loadView];
    
    OWSAssert(self.contents);

    self.title = self.contents.title;
    
    OWSAssert(self.tableView);
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOWSTableCellIdentifier];
}

- (OWSTableSection *)sectionForIndex:(NSInteger)sectionIndex
{
    OWSAssert(self.contents);
    OWSAssert(sectionIndex >= 0 && sectionIndex < (NSInteger) self.contents.sections.count);
    
    OWSTableSection *section = self.contents.sections[(NSUInteger) sectionIndex];
    return section;
}

- (OWSTableItem *)itemForIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert(self.contents);
    OWSAssert(indexPath.section >= 0 && indexPath.section < (NSInteger) self.contents.sections.count);
    
    OWSTableSection *section = self.contents.sections[(NSUInteger) indexPath.section];
    OWSAssert(indexPath.item >= 0 && indexPath.item < (NSInteger) section.items.count);
    OWSTableItem *item = section.items[(NSUInteger) indexPath.item];
    
    return item;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    OWSAssert(self.contents);

    OWSAssert(self.contents.sections.count > 0);
    return (NSInteger) self.contents.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    OWSAssert(section.items.count > 0);
    return (NSInteger) section.items.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];

    UITableViewCell *customCell = [item customCell];
    if (customCell) {
        return customCell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOWSTableCellIdentifier];
    OWSAssert(cell);
    
    cell.textLabel.text = item.title;
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.customRowHeight) {
        return [item.customRowHeight floatValue];
    }
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
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

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController
{
    OWSAssert(fromViewController);
    
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                                          target:self
                                                                                          action:@selector(donePressed:)];
    
    [fromViewController presentViewController:navigationController
                                     animated:YES
                                   completion:nil];
}

- (void)donePressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

NS_ASSUME_NONNULL_END
