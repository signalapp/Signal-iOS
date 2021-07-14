//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class HVTableDataSource: NSObject {
    fileprivate let viewState: HVViewState

    @objc
    public required init(viewState: HVViewState) {
        self.viewState = viewState
    }
}

// MARK: -

@objc
public enum HomeViewSection: Int {
    case reminders
    case pinned
    case unpinned
    case archiveButton
}
// typedef NS_ENUM(NSInteger, HomeViewSection) {
//    HomeViewSectionReminders,
//    HomeViewSectionPinned,
//    HomeViewSectionUnpinned,
//    HomeViewSectionArchiveButton,
// };

// MARK: -

extension HVTableDataSource: UITableViewDelegate {

//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, didEndDisplayingHeaderView view: UIView, forSection section: Int)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, didEndDisplayingFooterView view: UIView, forSection section: Int)
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat
//
//    @available(iOS 7.0, *)
//    optional func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat
//
//    @available(iOS 7.0, *)
//    optional func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat
//
//    @available(iOS 7.0, *)
//    optional func tableView(_ tableView: UITableView, estimatedHeightForFooterInSection section: Int) -> CGFloat
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView?
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView?
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath)
//
//    @available(iOS 6.0, *)
//    optional func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath)
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath?
//
//    @available(iOS 3.0, *)
//    optional func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath?
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
//
//    @available(iOS 3.0, *)
//    optional func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath)
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle
//
//    @available(iOS 3.0, *)
//    optional func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String?
//
//    @available(iOS, introduced: 8.0, deprecated: 13.0)
//    optional func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]?
//
//    @available(iOS 11.0, *)
//    optional func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
//
//    @available(iOS 11.0, *)
//    optional func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration?
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath)
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?)
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int
//
//    @available(iOS, introduced: 5.0, deprecated: 13.0)
//    optional func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool
//
//    @available(iOS, introduced: 5.0, deprecated: 13.0)
//    optional func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool
//
//    @available(iOS, introduced: 5.0, deprecated: 13.0)
//    optional func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?)
//
//    @available(iOS 9.0, *)
//    optional func tableView(_ tableView: UITableView, canFocusRowAt indexPath: IndexPath) -> Bool
//
//    @available(iOS 9.0, *)
//    optional func tableView(_ tableView: UITableView, shouldUpdateFocusIn context: UITableViewFocusUpdateContext) -> Bool
//
//    @available(iOS 9.0, *)
//    optional func tableView(_ tableView: UITableView, didUpdateFocusIn context: UITableViewFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator)
//
//    @available(iOS 9.0, *)
//    optional func indexPathForPreferredFocusedView(in tableView: UITableView) -> IndexPath?
//
//    @available(iOS 11.0, *)
//    optional func tableView(_ tableView: UITableView, shouldSpringLoadRowAt indexPath: IndexPath, with context: UISpringLoadedInteractionContext) -> Bool
//
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool
//
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath)
//
//    @available(iOS 13.0, *)
//    optional func tableViewDidEndMultipleSelectionInteraction(_ tableView: UITableView)
//
//    /**
//     * @abstract Called when the interaction begins.
//     *
//     * @param tableView  This UITableView.
//     * @param indexPath  IndexPath of the row for which a configuration is being requested.
//     * @param point      Location of the interaction in the table view's coordinate space
//     *
//     * @return A UIContextMenuConfiguration describing the menu to be presented. Return nil to prevent the interaction from beginning.
//     *         Returning an empty configuration causes the interaction to begin then fail with a cancellation effect. You might use this
//     *         to indicate to users that it's possible for a menu to be presented from this element, but that there are no actions to
//     *         present at this particular time.
//     */
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration?
//
//    /**
//     * @abstract Called when the interaction begins. Return a UITargetedPreview to override the default preview created by the table view.
//     *
//     * @param tableView      This UITableView.
//     * @param configuration  The configuration of the menu about to be displayed by this interaction.
//     */
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
//
//    /**
//     * @abstract Called when the interaction is about to dismiss. Return a UITargetedPreview describing the desired dismissal target.
//     * The interaction will animate the presented menu to the target. Use this to customize the dismissal animation.
//     *
//     * @param tableView      This UITableView.
//     * @param configuration  The configuration of the menu displayed by this interaction.
//     */
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview?
//
//    /**
//     * @abstract Called when the interaction is about to "commit" in response to the user tapping the preview.
//     *
//     * @param tableView      This UITableView.
//     * @param configuration  Configuration of the currently displayed menu.
//     * @param animator       Commit animator. Add animations to this object to run them alongside the commit transition.
//     */
//    @available(iOS 13.0, *)
//    optional func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating)
//
//    /**
//     * @abstract Called when the table view is about to display a menu.
//     *
//     * @param tableView       This UITableView.
//     * @param configuration   The configuration of the menu about to be displayed.
//     * @param animator        Appearance animator. Add animations to run them alongside the appearance transition.
//     */
//    @available(iOS 14.0, *)
//    optional func tableView(_ tableView: UITableView, willDisplayContextMenu configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?)
//
//    /**
//     * @abstract Called when the table view's context menu interaction is about to end.
//     *
//     * @param tableView       This UITableView.
//     * @param configuration   Ending configuration.
//     * @param animator        Disappearance animator. Add animations to run them alongside the disappearance transition.
//     */
//    @available(iOS 14.0, *)
//    optional func tableView(_ tableView: UITableView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionAnimating?)
// }
}

// MARK: -

extension HVTableDataSource: UITableViewDataSource {

//    UITableViewDelegate,
//    UITableViewDataSource

//    @available(iOS 2.0, *)
//    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
//
//
//    // Row display. Implementers should *always* try to reuse cells by setting each cell's reuseIdentifier and querying for available reusable cells with dequeueReusableCellWithIdentifier:
//    // Cell gets various attributes set automatically based on table (separators) and data source (accessory views, editing controls)
//
//    @available(iOS 2.0, *)
//    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
//
//
//    @available(iOS 2.0, *)
//    optional func numberOfSections(in tableView: UITableView) -> Int // Default is 1 if not implemented
//
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? // fixed font style. use custom view (UILabel) if you want something different
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String?
//
//
//    // Editing
//
//    // Individual rows can opt out of having the -editing property set for them. If not implemented, all rows are assumed to be editable.
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool
//
//
//    // Moving/reordering
//
//    // Allows the reorder accessory view to optionally be shown for a particular row. By default, the reorder control will be shown only if the datasource implements -tableView:moveRowAtIndexPath:toIndexPath:
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool
//
//
//    // Index
//
//    @available(iOS 2.0, *)
//    optional func sectionIndexTitles(for tableView: UITableView) -> [String]? // return list of section titles to display in section index view (e.g. "ABCD...Z#")
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int // tell table which section corresponds to section title/index (e.g. "B",1))
//
//
//    // Data manipulation - insert and delete support
//
//    // After a row has the minus or plus button invoked (based on the UITableViewCellEditingStyle for the cell), the dataSource must commit the change
//    // Not called for edit actions using UITableViewRowAction - the action's handler will be invoked instead
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath)
//
//
//    // Data manipulation - reorder / moving support
//
//    @available(iOS 2.0, *)
//    optional func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath)
// }
}

// MARK: -

//    #pragma mark - Table View Data Source
//
//    // Returns YES IFF this value changes.
//    - (BOOL)updateHasArchivedThreadsRow
//    {
//    BOOL hasArchivedThreadsRow
//    = (self.conversationListMode == ConversationListMode_Inbox && self.numberOfArchivedThreads > 0);
//    if (self.hasArchivedThreadsRow == hasArchivedThreadsRow) {
//    return NO;
//    }
//    self.hasArchivedThreadsRow = hasArchivedThreadsRow;
//
//    return YES;
//    }
//
//    - (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
//    {
//    return 4;
//    }
//
//    - (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)aSection
//    {
//    HomeViewSection section = (HomeViewSection)aSection;
//    switch (section) {
//    case HomeViewSectionReminders:
//    return self.hasVisibleReminders ? 1 : 0;
//    case HomeViewSectionPinned:
//    case HomeViewSectionUnpinned:
//    return [self.threadMapping numberOfItemsInSection:section];
//    case HomeViewSectionArchiveButton:
//    return self.hasArchivedThreadsRow ? 1 : 0;
//    }
//
//    OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)section);
//    return 0;
//    }
//
//    - (ThreadViewModel *)threadViewModelForIndexPath:(NSIndexPath *)indexPath
//    {
//    TSThread *threadRecord = [self threadForIndexPath:indexPath];
//    OWSAssertDebug(threadRecord);
//
//    ThreadViewModel *_Nullable cachedThreadViewModel
//    = (ThreadViewModel *)[self.threadViewModelCache objectForKey:threadRecord.uniqueId];
//    if (cachedThreadViewModel) {
//    return cachedThreadViewModel;
//    }
//
//    __block ThreadViewModel *_Nullable newThreadViewModel;
//    [self.databaseStorage readWithBlock:^(SDSAnyReadTransaction *transaction) {
//    newThreadViewModel = [[ThreadViewModel alloc] initWithThread:threadRecord
//    forConversationList:YES
//    transaction:transaction];
//    }];
//    [self.threadViewModelCache setObject:newThreadViewModel forKey:threadRecord.uniqueId];
//    return newThreadViewModel;
//    }
//
//    - (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
//    {
//    switch (section) {
//    case HomeViewSectionPinned:
//    case HomeViewSectionUnpinned: {
//    UIView *container = [UIView new];
//    container.layoutMargins = UIEdgeInsetsMake(14, 16, 8, 16);
//
//    UILabel *label = [UILabel new];
//    [container addSubview:label];
//    [label autoPinEdgesToSuperviewMargins];
//    label.font = UIFont.ows_dynamicTypeBodyFont.ows_semibold;
//    label.textColor = Theme.primaryTextColor;
//    label.text = section == HomeViewSectionPinned
//    ? NSLocalizedString(
//    @"PINNED_SECTION_TITLE", @"The title for pinned conversation section on the conversation list")
//    : NSLocalizedString(
//    @"UNPINNED_SECTION_TITLE", @"The title for unpinned conversation section on the conversation list");
//
//    return container;
//    }
//    default:
//    return [UIView new];
//    }
//    }
//
//    - (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
//    {
//    switch (section) {
//    case HomeViewSectionPinned:
//    case HomeViewSectionUnpinned:
//    if (!self.threadMapping.hasPinnedAndUnpinnedThreads) {
//    return FLT_EPSILON;
//    }
//
//    return UITableViewAutomaticDimension;
//    default:
//    // Without returning a header with a non-zero height, Grouped
//    // table view will use a default spacing between sections. We
//    // do not want that spacing so we use the smallest possible height.
//    return FLT_EPSILON;
//    }
//    }
//
//    - (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
//    {
//    return [UIView new];
//    }
//
//    - (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
//    {
//    // Without returning a footer with a non-zero height, Grouped
//    // table view will use a default spacing between sections. We
//    // do not want that spacing so we use the smallest possible height.
//    return FLT_EPSILON;
//    }
//
//    - (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
//    {
//    HomeViewSection section = (HomeViewSection)indexPath.section;
//
//    UITableViewCell *_Nullable cell;
//
//    switch (section) {
//    case HomeViewSectionReminders: {
//    OWSAssert(self.reminderStackView);
//    cell = self.reminderViewCell;
//    break;
//    }
//    case HomeViewSectionPinned:
//    case HomeViewSectionUnpinned: {
//    cell = [self tableView:tableView cellForConversationAtIndexPath:indexPath];
//    break;
//    }
//    case HomeViewSectionArchiveButton: {
//    cell = [self cellForArchivedConversationsRow:tableView];
//    break;
//    }
//    }
//
//    if (!cell) {
//    OWSFailDebug(@"failure: unexpected section: %lu", (unsigned long)section);
//    cell = [UITableViewCell new];
//    }
//
//    if (!self.splitViewController.isCollapsed) {
//    cell.selectedBackgroundView.backgroundColor
//    = Theme.isDarkThemeEnabled ? UIColor.ows_gray65Color : UIColor.ows_gray15Color;
//    cell.backgroundColor = Theme.secondaryBackgroundColor;
//    }
//
//    return cell;
//    }
//
//    - (UITableViewCell *)tableView:(UITableView *)tableView cellForConversationAtIndexPath:(NSIndexPath *)indexPath
//    {
//    ConversationListCell *cell =
//    [self.tableView dequeueReusableCellWithIdentifier:ConversationListCell.reuseIdentifier];
//    OWSAssertDebug(cell);
//
//    ThreadViewModel *thread = [self threadViewModelForIndexPath:indexPath];
//
//    // We want initial loads and reloads to load avatars sync,
//    // but subsequent avatar loads (e.g. from scrolling) should
//    // be async.
//    const NSTimeInterval avatarAsyncLoadInterval = kSecondInterval * 1;
//    BOOL shouldLoadAvatarAsync = (self.hasEverAppeared
//    && (self.lastReloadDate == nil || fabs(self.lastReloadDate.timeIntervalSinceNow) > avatarAsyncLoadInterval));
//    BOOL isBlocked = [self.blocklistCache isThreadBlocked:thread.threadRecord];
//    [cell configure:[[ConversationListCellConfiguration alloc] initWithThread:thread
//    shouldLoadAvatarAsync:shouldLoadAvatarAsync
//    isBlocked:isBlocked
//    overrideSnippet:nil
//    overrideDate:nil]];
//
//    NSString *cellName;
//    if (thread.threadRecord.isGroupThread) {
//    TSGroupThread *groupThread = (TSGroupThread *)thread.threadRecord;
//    cellName = [NSString stringWithFormat:@"cell-group-%@", groupThread.groupModel.groupName];
//    } else {
//    TSContactThread *contactThread = (TSContactThread *)thread.threadRecord;
//    cellName = [NSString stringWithFormat:@"cell-contact-%@", contactThread.contactAddress.stringForDisplay];
//    }
//    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, cellName);
//
//    NSString *archiveTitle;
//    if (self.conversationListMode == ConversationListMode_Inbox) {
//    archiveTitle = CommonStrings.archiveAction;
//    } else {
//    archiveTitle = CommonStrings.unarchiveAction;
//    }
//
//    OWSCellAccessibilityCustomAction *archiveAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:archiveTitle
//    type:OWSCellAccessibilityCustomActionTypeArchive
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//
//    OWSCellAccessibilityCustomAction *deleteAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:CommonStrings.deleteButton
//    type:OWSCellAccessibilityCustomActionTypeDelete
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//
//    OWSCellAccessibilityCustomAction *unreadAction;
//    if (thread.hasUnreadMessages) {
//    unreadAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:CommonStrings.readAction
//    type:OWSCellAccessibilityCustomActionTypeMarkRead
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//    } else {
//    unreadAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:CommonStrings.unreadAction
//    type:OWSCellAccessibilityCustomActionTypeMarkUnread
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//    }
//
//    OWSCellAccessibilityCustomAction *pinnedAction;
//    if ([self isThreadPinned:thread]) {
//    pinnedAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:CommonStrings.unpinAction
//    type:OWSCellAccessibilityCustomActionTypePin
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//    } else {
//    pinnedAction =
//    [[OWSCellAccessibilityCustomAction alloc] initWithName:CommonStrings.pinAction
//    type:OWSCellAccessibilityCustomActionTypeUnpin
//    threadViewModel:thread
//    target:self
//    selector:@selector(performAccessibilityCustomAction:)];
//    }
//
//    cell.accessibilityCustomActions = @[ archiveAction, deleteAction, unreadAction, pinnedAction ];
//
//
//    if ([self isConversationActiveForThread:thread.threadRecord]) {
//    [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
//    } else {
//    [tableView deselectRowAtIndexPath:indexPath animated:NO];
//    }
//
//    return cell;
//    }
//
//    - (UITableViewCell *)cellForArchivedConversationsRow:(UITableView *)tableView
//    {
//    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:kArchivedConversationsReuseIdentifier];
//    OWSAssertDebug(cell);
//    [OWSTableItem configureCell:cell];
//
//    cell.selectionStyle = UITableViewCellSelectionStyleNone;
//
//    for (UIView *subview in cell.contentView.subviews) {
//    [subview removeFromSuperview];
//    }
//
//    UIImage *disclosureImage = [UIImage imageNamed:(CurrentAppContext().isRTL ? @"NavBarBack" : @"NavBarBackRTL")];
//    OWSAssertDebug(disclosureImage);
//    UIImageView *disclosureImageView = [UIImageView new];
//    disclosureImageView.image = [disclosureImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
//    disclosureImageView.tintColor = [UIColor colorWithRGBHex:0xd1d1d6];
//    [disclosureImageView setContentHuggingHigh];
//    [disclosureImageView setCompressionResistanceHigh];
//
//    UILabel *label = [UILabel new];
//    label.text = NSLocalizedString(@"HOME_VIEW_ARCHIVED_CONVERSATIONS", @"Label for 'archived conversations' button.");
//    label.textAlignment = NSTextAlignmentCenter;
//    label.font = [UIFont ows_dynamicTypeBodyFont];
//    label.textColor = Theme.primaryTextColor;
//
//    UIStackView *stackView = [UIStackView new];
//    stackView.axis = UILayoutConstraintAxisHorizontal;
//    stackView.spacing = 5;
//    // If alignment isn't set, UIStackView uses the height of
//    // disclosureImageView, even if label has a higher desired height.
//    stackView.alignment = UIStackViewAlignmentCenter;
//    [stackView addArrangedSubview:label];
//    [stackView addArrangedSubview:disclosureImageView];
//    [cell.contentView addSubview:stackView];
//    [stackView autoCenterInSuperview];
//    // Constrain to cell margins.
//    [stackView autoPinEdgeToSuperviewMargin:ALEdgeLeading relation:NSLayoutRelationGreaterThanOrEqual];
//    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTrailing relation:NSLayoutRelationGreaterThanOrEqual];
//    [stackView autoPinEdgeToSuperviewMargin:ALEdgeTop];
//    [stackView autoPinEdgeToSuperviewMargin:ALEdgeBottom];
//
//    cell.accessibilityIdentifier = ACCESSIBILITY_IDENTIFIER_WITH_NAME(self, @"archived_conversations");
//
//    return cell;
//    }
//
//    - (TSThread *)threadForIndexPath:(NSIndexPath *)indexPath
//    {
//    OWSAssertDebug(indexPath.section == HomeViewSectionPinned
//    || indexPath.section == HomeViewSectionUnpinned);
//
//    return [self.threadMapping threadForIndexPath:indexPath];
//    }
//
//    - (void)pullToRefreshPerformed:(UIRefreshControl *)refreshControl
//    {
//    OWSAssertIsOnMainThread();
//    OWSLogInfo(@"beggining refreshing.");
//
//    [self.messageFetcherJob runObjc]
//    .then(^{
//    if (TSAccountManager.shared.isRegisteredPrimaryDevice) {
//    return [AnyPromise promiseWithValue:nil];
//    }
//
//    return [SSKEnvironment.shared.syncManager sendAllSyncRequestMessagesWithTimeout:20];
//    })
//    .ensure(^{
//    OWSLogInfo(@"ending refreshing.");
//    [refreshControl endRefreshing];
//    });
//    }
//
// }
