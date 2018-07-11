/** \file
 * \brief Tree Control
 *
 * See Copyright Notice in iup.h
 */

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <memory.h>
#include <stdarg.h>

#include "iup.h"
#include "iupcbs.h"

#include "iup_object.h"
#include "iup_layout.h"
#include "iup_attrib.h"
#include "iup_str.h"
#include "iup_drv.h"
#include "iup_drvfont.h"
#include "iup_stdcontrols.h"
#include "iup_key.h"
#include "iup_image.h"
#include "iup_array.h"
#include "iup_tree.h"

#include "iup_drvinfo.h"

#include "iupcocoa_drv.h"

// TODO:
// Removing the disclosure triangle, Disable indenting
// https://stackoverflow.com/questions/4251790/nsoutlineview-remove-disclosure-triangle-and-indent

// the point of this is we have a unique memory address for an identifier
static const void* IUP_COCOA_TREE_DELEGATE_OBJ_KEY = "IUP_COCOA_TREE_DELEGATE_OBJ_KEY";




static NSView* cocoaTreeGetRootView(Ihandle* ih)
{
	NSView* root_container_view = (NSView*)ih->handle;
	NSCAssert([root_container_view isKindOfClass:[NSView class]], @"Expected NSView");
	return root_container_view;
}

static NSScrollView* cocoaTreeGetScrollView(Ihandle* ih)
{
	NSScrollView* scroll_view = (NSScrollView*)ih->handle;
	NSCAssert([scroll_view isKindOfClass:[NSScrollView class]], @"Expected NSScrollView");
	return scroll_view;
}

static NSOutlineView* cocoaTreeGetOutlineView(Ihandle* ih)
{
	
	NSScrollView* scroll_view = cocoaTreeGetScrollView(ih);
	NSOutlineView* outline_view = (NSOutlineView*)[scroll_view documentView];
	NSCAssert([outline_view isKindOfClass:[NSOutlineView class]], @"Expected NSOutlineView");
	return outline_view;
	
}


@interface IupCocoaTreeItem : NSObject
{
	IupCocoaTreeItem* parentItem;
	NSMutableArray* childrenArray;
	int kind; // ITREE_BRANCH ITREE_LEAF
	NSString* title;
	BOOL isDeleted;
	NSImage* bitmapImage;
	NSImage* collapsedImage;
	NSTableCellView* tableCellView; // kind of a hack to force layout in heightOf
	
}

@property(nonatomic, assign) int kind;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, weak) IupCocoaTreeItem* parentItem;
@property(nonatomic, assign) BOOL isDeleted;
@property(nonatomic, retain) NSImage* bitmapImage;
@property(nonatomic, retain) NSImage* collapsedImage;
@property(nonatomic, weak) NSTableCellView* tableCellView; // this is kind of a hack to force layout in heightOf. I'm not sure if I want to keep a strong reference because I don't know if there is a possible circular reference here.

- (IupCocoaTreeItem*) childAtIndex:(NSUInteger)the_index;

@end

// forward declaration needed
static void cocoaTreeReloadItem(IupCocoaTreeItem* tree_item, NSOutlineView* outline_view);


@implementation IupCocoaTreeItem

@synthesize kind = kind;
@synthesize title = title;
@synthesize parentItem = parentItem;
@synthesize isDeleted = isDeleted;
@synthesize bitmapImage = bitmapImage; // is the expandedImage for branches
@synthesize collapsedImage = collapsedImage;
@synthesize tableCellView = tableCellView;


// Creates, caches, and returns the array of children
// Loads children incrementally
- (NSMutableArray*) childrenArray
{
	return childrenArray;
}


- (IupCocoaTreeItem*) childAtIndex:(NSUInteger)the_index
{
	return [[self childrenArray] objectAtIndex:the_index];
}


- (NSUInteger) numberOfChildren
{
	NSArray* tmp = [self childrenArray];
	return [tmp count];
}


- (instancetype) init
{
	self = [super init];
	if(self)
	{
		childrenArray = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void) dealloc
{
	//[tableCellView releae];
	tableCellView = nil; // weak ref
	
	[bitmapImage release];
	[collapsedImage release];

	[childrenArray release];
	[title release];
	parentItem = nil; // weak ref
	[super dealloc];
}

@end
/*
@interface IupCocoaTreeRoot : NSObject
{
	// Array of IupCocoaTreeItems
	NSMutableArray* topLevelObjects;
}
@end

@implementation IupCocoaTreeRoot

@end
*/

// We need to override NSOutlineView in order to implement things like keyDown for k_any
@interface IupCocoaOutlineView : NSOutlineView
{
	Ihandle* _ih;
	NSImage* leafImage;
	NSImage* expandedImage;
	NSImage* collapsedImage;
}
@property(nonatomic, assign) Ihandle* ih;
@property(nonatomic, retain) NSImage* leafImage;
@property(nonatomic, retain) NSImage* expandedImage;
@property(nonatomic, retain) NSImage* collapsedImage;
@end

@implementation IupCocoaOutlineView
@synthesize ih = _ih;
@synthesize leafImage = leafImage;
@synthesize expandedImage = expandedImage;
@synthesize collapsedImage = collapsedImage;

- (void) dealloc
{
	[leafImage release];
	[expandedImage release];
	[collapsedImage release];
	[super dealloc];
}

// TODO: k_any
- (void) keyDown:(NSEvent*)the_event
{
	NSLog(@"keyDown: %@", the_event);
	[super keyDown:the_event];
	
}

@end

// We are not using NSComboBoxDataSource
@interface IupCocoaTreeDelegate : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
	NSUInteger numberOfItems;
	
	NSMutableArray* treeRootTopLevelObjects;
	
//	NSMutableArray* orderedArrayOfSelections; // TODO: If we decide selection order is important enough and worth the risks of edge cases missing updates (like delnode)
	NSIndexSet* previousSelections;
}
@property(nonatomic, assign) NSUInteger numberOfItems;
@property(nonatomic, copy) NSArray* treeRootTopLevelObjects; // This is intended for external read-only access to iterate through all items, such as changing the branch/leaf images
- (NSUInteger) insertChild:(IupCocoaTreeItem*)tree_item_child withParent:(IupCocoaTreeItem*)tree_item_parent;
- (NSUInteger) insertPeer:(IupCocoaTreeItem*)tree_item_new withSibling:(IupCocoaTreeItem*)tree_item_prev;
- (void) insertAtRoot:(IupCocoaTreeItem*)tree_item_new;
- (void) removeAllObjects;
- (NSIndexSet*) removeAllChildrenForItem:(IupCocoaTreeItem*)tree_item;
- (NSUInteger) removeItem:(IupCocoaTreeItem*)tree_item;

//- (NSMutableArray*) dataArray;

// NSOutlineViewDataSource
- (NSInteger) outlineView:(NSOutlineView*)outline_view numberOfChildrenOfItem:(nullable id)the_item;
//- (id) outlineView:(NSOutlineView*)outline_view child:(NSInteger)index ofItem:(nullable id)the_item;
- (BOOL) outlineView:(NSOutlineView*)outline_view isItemExpandable:(id)the_item;
// NSOutlineViewDelegate
- (nullable NSView *)outlineView:(NSOutlineView*)outline_view viewForTableColumn:(nullable NSTableColumn*)table_column item:(id)the_item;
// NSOutlineViewDelegate
- (void) outlineViewSelectionDidChange:(NSNotification*)the_notification;
// NSOutlineViewDelegate, for CANFOCUS
- (NSIndexSet*) outlineView:(NSOutlineView*)outline_view selectionIndexesForProposedSelection:(NSIndexSet*)proposed_selection_indexes;

@end

static NSUInteger Helper_RecursivelyCountItems(IupCocoaTreeItem* the_item)
{
	NSUInteger counter = 1;
	for(IupCocoaTreeItem* a_item in [the_item childrenArray])
	{
		counter += Helper_RecursivelyCountItems(a_item);
	}
	return counter;
}

@implementation IupCocoaTreeDelegate
@synthesize numberOfItems = numberOfItems;
@synthesize treeRootTopLevelObjects = treeRootTopLevelObjects;

- (instancetype) init
{
	self = [super init];
	if(self)
	{
		treeRootTopLevelObjects = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void) dealloc
{
	[treeRootTopLevelObjects release];
	[previousSelections release];
	[super dealloc];
}

- (NSUInteger) insertChild:(IupCocoaTreeItem*)tree_item_child withParent:(IupCocoaTreeItem*)tree_item_parent
{
	// IUP always inserts the child in the first position, not the last, when in this parent/child relationship
	[[tree_item_parent childrenArray] insertObject:tree_item_child atIndex:0];
	[tree_item_child setParentItem:tree_item_parent];
	numberOfItems = numberOfItems + Helper_RecursivelyCountItems(tree_item_child);
	return 0; // always index 0 since we always insert in the first position
}

- (NSUInteger) insertPeer:(IupCocoaTreeItem*)tree_item_new withSibling:(IupCocoaTreeItem*)tree_item_prev
{
	IupCocoaTreeItem* tree_item_parent = [tree_item_prev parentItem];
	if(nil != tree_item_parent)
	{
		[tree_item_new setParentItem:tree_item_parent];
		// insert the new node after reference node
		NSMutableArray* children_array = [tree_item_parent childrenArray];
		NSUInteger prev_index = [children_array indexOfObject:tree_item_prev];
		NSUInteger target_index = prev_index + 1;

		if(target_index > [children_array count])
		{
			target_index = [children_array count];
			[children_array addObject:tree_item_new];
		}
		else
		{
			[children_array insertObject:tree_item_new atIndex:target_index];
		}
		numberOfItems = numberOfItems + Helper_RecursivelyCountItems(tree_item_new);
		return target_index;
	}
	else
	{
		// we are adding a peer to the root (case is ADDROOT=NO)
		NSUInteger target_index = 0;

		NSUInteger object_index = [treeRootTopLevelObjects indexOfObject:tree_item_prev];
		if(object_index != NSNotFound)
		{
			// insert after the previous (reference) node
			target_index = object_index + 1;
		}
	
		[treeRootTopLevelObjects insertObject:tree_item_new atIndex:target_index];
		numberOfItems = numberOfItems + Helper_RecursivelyCountItems(tree_item_new);
		return target_index;
	}
}

- (void) insertAtRoot:(IupCocoaTreeItem*)tree_item_new
{
	// IUP always inserts the child in the first position, not the last
	[treeRootTopLevelObjects insertObject:tree_item_new atIndex:0];
	numberOfItems = numberOfItems + Helper_RecursivelyCountItems(tree_item_new);
}

- (void) removeAllObjects
{
	[treeRootTopLevelObjects removeAllObjects];
	numberOfItems = 0;
}

// Returns the indexes of the top-level children that get removed
- (NSIndexSet*) removeAllChildrenForItem:(IupCocoaTreeItem*)tree_item
{
	if(nil == tree_item)
	{
		return nil;
	}
	NSUInteger number_of_descendents = Helper_RecursivelyCountItems(tree_item) - 1; // subtract one because we don't want to count the tree_item itself, just children/grandchildren

	NSMutableArray* children_array = [tree_item childrenArray];
	NSIndexSet* top_level_children_indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [children_array count])];
	[children_array removeAllObjects];
	numberOfItems = numberOfItems - number_of_descendents;
	return top_level_children_indexes;
}

// This is a helper for removeItem:
// This is a special helper because when using fast enumeration in removeItem: we can't change the parent's childrenArray to remove this node.
// So in this helper, we don't try and assume removeItem: will handle that last step itself.
// So this method is here so we can clear the children data and update the count.
- (void) removeRecursiveChildItemHelper:(IupCocoaTreeItem*)tree_item
{
	// First, if this node has any children, recursively traverse through all the children and remove them.
	NSMutableArray* children_array = [tree_item childrenArray];
	for(IupCocoaTreeItem* an_item in children_array)
	{
		[self removeRecursiveChildItemHelper:an_item];
	}
	// clear the children array so in case there is another reference that is still using this pointer, it will have updated info that there are no children.
	[children_array removeAllObjects];
	[tree_item setIsDeleted:YES];
	numberOfItems = numberOfItems - 1;
}

- (NSUInteger) removeItem:(IupCocoaTreeItem*)tree_item
{
	if(nil == tree_item)
	{
		return NSNotFound;
	}
	// If we already removed this item, the parentItem is nil.
	if(YES == [tree_item isDeleted])
	{
		return NSNotFound;
	}
	
	// First, if this node has any children, recursively traverse through all the children and remove them.
	NSMutableArray* children_array = [tree_item childrenArray];
	for(IupCocoaTreeItem* an_item in children_array)
	{
		[self removeRecursiveChildItemHelper:an_item];
	}
	// clear the children array so in case there is another reference that is still using this pointer, it will have updated info that there are no children.
	[children_array removeAllObjects];

	// now remove this node by going to the parent and removing this from the parent's childrenArray
	IupCocoaTreeItem* tree_item_parent = [tree_item parentItem];
	if(nil != tree_item_parent)
	{
		NSUInteger object_index = [[tree_item_parent childrenArray] indexOfObject:tree_item];
		if(object_index != NSNotFound)
		{
			[[tree_item_parent childrenArray] removeObjectAtIndex:object_index];
			numberOfItems = numberOfItems - 1;
		}
		return object_index;
	}
	else
	{
		// this is top level node
		NSUInteger object_index = [treeRootTopLevelObjects indexOfObject:tree_item];
		if(object_index != NSNotFound)
		{
			[treeRootTopLevelObjects removeObjectAtIndex:object_index];
			numberOfItems = numberOfItems - 1;
		}
		return object_index;
	}
}

- (NSInteger) outlineView:(NSOutlineView*)outline_view numberOfChildrenOfItem:(nullable id)the_item
{
	// FIXME: temp placeholder
	// FIXME: temp placeholder
	if(nil == the_item)
	{
		NSInteger the_count = [treeRootTopLevelObjects count];
		return the_count;
	}
	else
	{
		NSInteger the_count = [the_item numberOfChildren];
		return the_count;
	}
}

- (id) outlineView:(NSOutlineView*)outline_view child:(NSInteger)the_index ofItem:(nullable id)the_item
{
	// FIXME: temp placeholder
	if(nil == the_item)
	{
//		return nil;
//		IupCocoaTreeItem* dummy = [[[IupCocoaTreeItem alloc] init] autorelease];
// return dummy;
		IupCocoaTreeItem* tree_item = [treeRootTopLevelObjects objectAtIndex:the_index];
		return tree_item;
	}
	else
	{
		return [the_item childAtIndex:the_index];
	}
}

- (BOOL) outlineView:(NSOutlineView*)outline_view isItemExpandable:(id)the_item
{
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)the_item;

	NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"Expected IupCocoaTreeItem");
		
#if 0
		// This is the basic implementation.
		// The problem is if you add children after this gets called, this happens too late.
		// The workaround would be to use dispatch_async, but that causes a delay and flicker.
		// One other possible solution to to force a reload on the parent item on delete and add node events.
		if([tree_item numberOfChildren] > 0)
		{
			return YES;
		}
		else
		{
			return NO;
		}
#else
		// We are preferring this implementation over the numberOfChildren > 0
		// because when we first add a branch without children, expandItem won't work.
		// The workaround for that is to use dispatch_async, but this causes a delay and flicker.
		// Since IUP makes users declare the difference between a leaf & branch, we can assume all branches should be expandable.
		// And we have that information immediately.
		// The downside "bug" with this implementation is empty branches always show the triangle which is not typical.
		// One other possible solution is to go back to the above or do a hybrid, and try the reload parent idea.
		if([tree_item kind] == ITREE_BRANCH)
		{
#if 1
			// UPDATE: This might work now an only show the triangle when has children, due to all the other changes I made with adding/deleting.
			if([tree_item numberOfChildren] > 0)
			{
				return YES;
			}
			else
			{
				return NO;
			}
#else
			return YES;
#endif
		}
		else
		{
			return NO;
		}
#endif
}

/* // Not needed for View based NSOutlineView
- (nullable id)outlineView:(NSOutlineView *)outline_view objectValueForTableColumn:(nullable NSTableColumn *)table_column byItem:(nullable id)the_item
{
	//return (the_item == nil) ? @"/" : @"lower";
	if(nil == the_item)
	{
		return @"Hello World";
	}
	else
	{
		IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)the_item;
		NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"Expected IupCocoaTreeItem");
		return [tree_item title];
	}
	
}
*/


static NSImage* helperGetActiveImageForTreeItem(IupCocoaTreeItem* tree_item, IupCocoaOutlineView* outline_view, CGFloat* out_width, CGFloat* out_height)
{
	NSImage* active_image = nil;
	int kind = [tree_item kind];
	if(ITREE_BRANCH == kind)
	{
	
		if([outline_view isItemExpanded:tree_item])
		{
			active_image = [tree_item bitmapImage];
			if(nil == active_image)
			{
				active_image = [(IupCocoaOutlineView*)outline_view expandedImage];
			}
		}
		else
		{
			active_image = [tree_item collapsedImage];
			if(nil == active_image)
			{
				active_image = [(IupCocoaOutlineView*)outline_view collapsedImage];
			}
		}
	}
	else if(ITREE_LEAF == kind)
	{
		active_image = [tree_item bitmapImage];
		if(nil == active_image)
		{
			active_image = [(IupCocoaOutlineView*)outline_view leafImage];
		}
	}

	NSSize image_size = NSMakeSize(0.0, 0.0);
	if(active_image)
	{
		image_size = [active_image size];
	}

	if(NULL != out_width)
	{
		*out_width = image_size.width;
	}

	if(NULL != out_height)
	{
		*out_height = image_size.height;
	}
	return active_image;
}

// WARNING: This method needs to be fast for performance.
// I'm worried the image support is already a bit too complicated because it allows for any image size. But I think it will be fine for desktop.
- (CGFloat) outlineView:(NSOutlineView*)outline_view heightOfRowByItem:(id)the_item
{
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)the_item;
	CGFloat text_height = 17.0;
	
	// TODO: Height needs to also account for font if the user changed it
	CGFloat image_width = 0.0;
	CGFloat image_height = 0.0;
	NSImage* active_image = helperGetActiveImageForTreeItem(tree_item, (IupCocoaOutlineView*)outline_view, &image_width, &image_height);
	
	NSTableCellView* table_cell_view = [tree_item tableCellView];
	NSTextField* text_field = [table_cell_view textField];
	NSSize text_field_size = { 0, 0 };
	if(text_field)
	{
		text_field_size = [text_field fittingSize];
	}
	
	if(text_field_size.height > text_height)
	{
		text_height = text_field_size.height;
	}
	else if(text_field_size.height == 0)
	{
		// don't allow 0
	}
	else
	{
		// should I allow smaller text heights?
		text_height = text_field_size.height;
	}


	if(active_image)
	{
		if(image_height < text_height)
		{
			return text_height;
		}
		else
		{
			return image_height;
		}
	}
	else
	{
		return text_height;
	}

}

// NSOutlineViewDelegate
// WARNING: This is another method that should be fast for performance.
- (nullable NSView *)outlineView:(NSOutlineView*)outline_view viewForTableColumn:(nullable NSTableColumn*)table_column item:(id)the_item
{
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)the_item;
	NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"Expected IupCocoaTreeItem");
	NSString* string_item = [tree_item title];


	// Get an existing cell with the MyView identifier if it exists
	NSTableCellView* table_cell_view = [outline_view makeViewWithIdentifier:@"IupCocoaTreeTableViewCell" owner:self];

	// There is no existing cell to reuse so create a new one
	if(nil == table_cell_view)
	{
		table_cell_view = [[NSTableCellView alloc] initWithFrame:NSZeroRect];

		// The identifier of the NSTextField instance is set to MyView.
		// This allows the cell to be reused.
		
		[table_cell_view setIdentifier:@"IupCocoaTreeTableViewCell"];
	}

	// table_cell_view is now guaranteed to be valid, either as a reused cell
	// or as a new cell, so set the stringValue of the cell to the
	// nameArray value at row
	NSTextField* text_field = nil;
	text_field = [table_cell_view textField];
	NSImageView* image_view = nil;
	image_view = [table_cell_view imageView];
	[text_field setStringValue:string_item];


	CGFloat image_width = 0.0;
	CGFloat image_height = 0.0;
	NSImage* active_image = helperGetActiveImageForTreeItem(tree_item, (IupCocoaOutlineView*)outline_view, &image_width, &image_height);
	
	if(nil == active_image)
	{
		[image_view setHidden:YES];
		[image_view setImage:nil];
	}
	else
	{
		[image_view setHidden:NO];
		[image_view setImage:active_image];
	}

	[tree_item setTableCellView:table_cell_view]; // kind of a hack. We need it to compute the size in heightOf
 
	// Return the result
	return table_cell_view;
}

// I think it is a really bad idea to change images based on expanded or closed
// because this creates another potential reload (which loses selection data)
// and another potential performance bottleneck.
// This is not a typical Mac/Cocoa behavior.
// But the IUP API demands it.
// There is an optimization here to not swap images if the image is the same.
// However, this is a pointer comparison and requires both the user and IUP implementation to not accidentally load the same image twice
// or create two separate object wrappers around the same image.
// I recommend we add something to the official API documation that separate images is a bad idea.
- (void) outlineViewItemWillExpand:(NSNotification*)the_notification
{
	IupCocoaOutlineView* outline_view = (IupCocoaOutlineView*)[the_notification object];
		NSDictionary* user_info = [the_notification userInfo];
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)[user_info objectForKey:@"NSObject"];
//	Ihandle* ih = [outline_view ih];
	
	if(nil == tree_item)
	{
		return;
	}
	


	NSImage* expanded_image = [tree_item bitmapImage];
	NSImage* collapsed_image = [tree_item collapsedImage];
	NSImage* fallback_expanded_image = [outline_view expandedImage];
	NSImage* fallback_collapsed_image = [outline_view collapsedImage];

	if(expanded_image || fallback_expanded_image)
	{
		NSImage* which_expanded_image = nil;
		if(expanded_image)
		{
			which_expanded_image = expanded_image;
		}
		else
		{
			which_expanded_image = fallback_expanded_image;
		}
		NSImage* which_collapsed_image = nil;
		if(collapsed_image)
		{
			which_collapsed_image = collapsed_image;
		}
		else
		{
			which_collapsed_image = fallback_collapsed_image;
		}

		// Only reload if the expanded and collapsed images are different
		// (I'm worried that switching images is not a typical Mac behavior and may hurt built-in performance optimizations.
		// Also, reloading may reset selection which is not nice.)
		// Note: I've been using retain, hoping that we just have a simple pointer comparison and it will avoid doing slow pixel comparisons.
		if(![which_expanded_image isEqual:which_collapsed_image])
		{
			cocoaTreeReloadItem(tree_item, outline_view);
		}
	}
	

}

// I think it is a really bad idea to change images based on expanded or closed
// because this creates another potential reload (which loses selection data)
// and another potential performance bottleneck.
// This is not a typical Mac/Cocoa behavior.
// But the IUP API demands it.
// There is an optimization here to not swap images if the image is the same.
// However, this is a pointer comparison and requires both the user and IUP implementation to not accidentally load the same image twice
// or create two separate object wrappers around the same image.
// I recommend we add something to the official API documation that separate images is a bad idea.
- (void) outlineViewItemWillCollapse:(NSNotification*)the_notification
{

	IupCocoaOutlineView* outline_view = [the_notification object];
	NSDictionary* user_info = [the_notification userInfo];
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)[user_info objectForKey:@"NSObject"];
//	Ihandle* ih = [(IupCocoaOutlineView*)outline_view ih];
	
	if(nil == tree_item)
	{
		return;
	}
	
	
	
	NSImage* expanded_image = [tree_item bitmapImage];
	NSImage* collapsed_image = [tree_item collapsedImage];
	NSImage* fallback_expanded_image = [outline_view expandedImage];
	NSImage* fallback_collapsed_image = [outline_view collapsedImage];

	if(collapsed_image || fallback_collapsed_image)
	{
		NSImage* which_expanded_image = nil;
		if(expanded_image)
		{
			which_expanded_image = expanded_image;
		}
		else
		{
			which_expanded_image = fallback_expanded_image;
		}
		NSImage* which_collapsed_image = nil;
		if(collapsed_image)
		{
			which_collapsed_image = collapsed_image;
		}
		else
		{
			which_collapsed_image = fallback_collapsed_image;
		}

		// Only reload if the expanded and collapsed images are different
		// (I'm worried that switching images is not a typical Mac behavior and may hurt built-in performance optimizations.
		// Also, reloading may reset selection which is not nice.)
		// Note: I've been using retain, hoping that we just have a simple pointer comparison and it will avoid doing slow pixel comparisons.
		if(![which_expanded_image isEqual:which_collapsed_image])
		{
			cocoaTreeReloadItem(tree_item, outline_view);
		}
	}
	


}

- (void) handleSelectionDidChange:(NSOutlineView*)outline_view
{
	// Rules:
	// If we are in single selection mode, we use the single_cb
	// If we are in multiple selection mode, then one of the following:
	// - If it is a single selection, then use single_cb
	// - If it is a multiple selection, then use multi_cb and skip single_cb
	//     - but if multi_cb is not defined, invoke multiple callbacks of single_cb
	// Also, we need to remember that to do multi-unselection_cb.
	// - This fires if there was a multi-selection from the last time.
	
	// Additional notes:
	
	// (1) Multi_cb is supposed to be a contiguous range for a single action.
	// While I expect that will be the typical case on Mac,
	// I do worry that Apple may have or introduce some built-in key-shortcut (e.g. cmd-a selects all) that can create a non-contiguous selection.
	// For example, what if there is an "invert selection" option?
	// So say you pick the middle item. Then you invert it which gets you everything except the middle item.
	// You now have a discontinuous selection created in one-shot.

	// (2) Delete nodes and selection.
	// I asked Scuri if we are supposed to trigger a selection callback when nodes are deleted,
	// since this will alter the list of selected items.
	// He says that IUP does not do a callback for this case.
	// But this is why I broke this into a helper method, in case it needs to be called directly instead of just on Apple's selection notification.
	// (Apple does not seem to give selection notification callbacks for changes caused by delete or reloadData either.)

	NSCAssert([outline_view isKindOfClass:[IupCocoaOutlineView class]], @"Expected IupCocoaOutlineView");
	Ihandle* ih = [(IupCocoaOutlineView*)outline_view ih];
	if(NULL == ih)
	{
		return;
	}
	

	// May not be the best way to determine callback type since the user can change this on the fly.
//	BOOL in_mulitple_selection_mode = [outline_view allowsMultipleSelection];
	IFnii single_selection_cb = (IFnii)IupGetCallback(ih, "SELECTION_CB");
    IFnIi multi_selection_cb = (IFnIi)IupGetCallback(ih, "MULTISELECTION_CB");
    IFnIi multi_unselection_cb = (IFnIi)IupGetCallback(ih, "MULTIUNSELECTION_CB");

	// No sense doing any work if callbacks are not set.
	// NOTE: setting previousSelection will also be skipped in this case.
	if((single_selection_cb == NULL) && (multi_selection_cb == NULL) && (multi_unselection_cb == NULL))
	{
		return;
	}

#if 0
	// debug: print all currently selected items
	{
		NSIndexSet* selected_index = [outline_view selectedRowIndexes];
		NSUInteger selected_i = [selected_index firstIndex];
		while(selected_i != NSNotFound)
		{
			id selected_item = [outline_view itemAtRow:selected_i];
			NSLog(@"all selected_item: %@", [selected_item title]);
			// get the next index in the set
			selected_i = [selected_index indexGreaterThanIndex:selected_i];
		}
	}
#endif
	
	// First handle the unselections
	{
		// We will get a copy of the previous selections.
		NSMutableIndexSet* unselected_set = [previousSelections mutableCopy];
		if(unselected_set != nil)
		{
			// Then remove the current selections from the previous selections.
			// This will leave the unselected items.
			[unselected_set removeIndexes:[outline_view selectedRowIndexes]];
			
			NSUInteger number_of_items = [unselected_set count];

			// If the previous selection had more than 1, it was a multi-selection.
			// That means we need to do a multi-unselection to balance it.
			// This is safer than testing for whether the outlineview is in multi-mode or not because the user could have changed it on the fly.
			if(number_of_items == 0)
			{
				// do nothing
			}
			else if([previousSelections count] > 1)
			{
				if((NULL != multi_unselection_cb) || (NULL != single_selection_cb))
				{
					// We are in the multiple unselection case
					// VLA
					int array_of_ids[number_of_items];
					NSUInteger selected_i = [unselected_set firstIndex];
					size_t i = 0;
					while(selected_i != NSNotFound)
					{
						NSCAssert(i<number_of_items, @"Overflow: More indexes than expected.");

						array_of_ids[i] = (int)selected_i;
						i++;
						// id selected_item = [outline_view itemAtRow:selected_i];
						//	NSLog(@"removed selected_item: %@", [selected_item title]);
						// get the next index in the set
						selected_i = [unselected_set indexGreaterThanIndex:selected_i];
					}

					if(NULL != multi_unselection_cb)
					{
						multi_unselection_cb(ih, array_of_ids, (int)number_of_items);
					}
					else if(NULL != single_selection_cb)
					{
						for(size_t j=0; j<number_of_items; j++)
						{
							single_selection_cb(ih, array_of_ids[j], 1);
						}
					}
				}

			
			}
			else
			{
				// We are in the single unselection case
				// This should be 0, but just in case there are more, use the first one.
				if(number_of_items > 0)
				{
					if(NULL != single_selection_cb)
					{
						NSUInteger selected_i = [unselected_set firstIndex];
			           	single_selection_cb(ih, (int)selected_i, 0);
					}
				}
				// else do nothing since there was nothing unselected

			}
			
			[unselected_set release];
		}
	} // end unselections
	
	
	
	// handle the selections
	{
		// Get a copy of all the current selections
		NSMutableIndexSet* added_selected_set = [[outline_view selectedRowIndexes] mutableCopy];
		// Subtract out the previousSelections from the current selections which leaves just the newly added selections.
		[added_selected_set removeIndexes:previousSelections];

		if(added_selected_set != nil)
		{
			NSUInteger number_of_items = [added_selected_set count];

			if(number_of_items == 0)
			{
				// do nothing
			}
			else if(number_of_items > 1)
			{
				if((NULL != multi_selection_cb) || (NULL != single_selection_cb))
				{
					// We are in the multiple selection case
					// VLA
					int array_of_ids[number_of_items];
					NSUInteger selected_i = [added_selected_set firstIndex];
					size_t i = 0;
					while(selected_i != NSNotFound)
					{
						NSCAssert(i<number_of_items, @"Overflow: More indexes than expected.");

						array_of_ids[i] = (int)selected_i;
						i++;
						// id selected_item = [outline_view itemAtRow:selected_i];
						// NSLog(@"added selected_item: %@", [selected_item title]);
						// get the next index in the set
						selected_i = [added_selected_set indexGreaterThanIndex:selected_i];
					}

					if(NULL != multi_selection_cb)
					{
						multi_selection_cb(ih, array_of_ids, (int)number_of_items);
					}
					else if(NULL != single_selection_cb)
					{
						for(size_t j=0; j<number_of_items; j++)
						{
							single_selection_cb(ih, array_of_ids[j], 1);
						}
					}
				}
			}
			else // number_of_items == 1
			{
				// We are in the single selection case

				if(NULL != single_selection_cb)
				{
					NSUInteger selected_i = [added_selected_set firstIndex];
					single_selection_cb(ih, (int)selected_i, 1);
				}
			}
			
			[added_selected_set release];
		}
	} // end selections
	
	
	// Release the old previousSelections and save the new/current selections as previousSelections for the next time this is called.
	[previousSelections release];
	previousSelections = [[outline_view selectedRowIndexes] copy];
}

- (void) outlineViewSelectionDidChange:(NSNotification*)the_notification
{
	NSOutlineView* outline_view = [the_notification object];
	[self handleSelectionDidChange:outline_view];

}

- (NSIndexSet*) outlineView:(NSOutlineView*)outline_view selectionIndexesForProposedSelection:(NSIndexSet*)proposed_selection_indexes
{
	Ihandle* ih = [(IupCocoaOutlineView*)outline_view ih];
	if(iupAttribGetBoolean(ih, "CANFOCUS"))
	{
		return proposed_selection_indexes;
	}
	else
	{
		return nil;
	}
}

@end

/*****************************************************************************/
/* ADDING ITEMS                                                              */
/*****************************************************************************/

static void cocoaTreeReloadItem(IupCocoaTreeItem* tree_item, NSOutlineView* outline_view)
{
	NSOperatingSystemVersion macosx_1012 = { 10, 12, 0 };
	
	// isOperatingSystemAtLeastVersion officially requires 10.10+, but seems available on 10.9
	if([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:macosx_1012])
	{
		// Starting in 10.12, reloadItem: was fixed to do the right thing. Must link to 10.12 SDK or higher (which you should always link to the lastest on Mac anyway)
		[outline_view reloadItem:tree_item];
	}
	else
	{
		[outline_view reloadData];
	}
}

void iupdrvTreeAddNode(Ihandle* ih, int prev_id, int kind, const char* title, int add)
{
/*
 
 id is the number identifier of a reference node, the reference node is used to position the new node.
 
 kind is the new node type, if it is a branch or a leaf.
 
 add means appending a node at the end of the branch, if 0 means inserting the node in the branch
 
 If the reference node exists then
 if (reference node is a branch and appending)
 insert the new node after the reference node, as first child
 else
 insert the new node after reference node
 else
 add the new node at root
*/
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
	IupCocoaTreeDelegate* data_source_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	
	

	
	
	InodeHandle* inode_prev = iupTreeGetNode(ih, prev_id);
	

	/* the previous node is not necessary only
	 if adding the root in an empty tree or before the root. */
	if (!inode_prev && prev_id!=-1)
	{
//		return;
	}
	
	if (!title)
	{
		title = "";
	}
	

	
	IupCocoaTreeItem* tree_item_new = [[IupCocoaTreeItem alloc] init];
	[tree_item_new setKind:kind];
	NSString* ns_title = [NSString stringWithUTF8String:title];
	[tree_item_new setTitle:ns_title];
//	InodeHandle* inode_new = (InodeHandle*)calloc(1, sizeof(InodeHandle));
	InodeHandle* inode_new = (InodeHandle*)tree_item_new; // NOTE: retain count is 1 from alloc. We are not going to retain it again.
	
	//  If the reference node exists then
	if(inode_prev)
	{
		IupCocoaTreeItem* tree_item_prev = inode_prev;
		int kind_prev = [tree_item_prev kind];
	
		
		// if (reference node is a branch and appending)
		if((ITREE_BRANCH == kind_prev) && (1 == add))
		{
			// insert the new node after the reference node, as first child
			/* depth+1 */
			// IUP always inserts the child in the first position, not the last
			// update the data source
			NSUInteger target_index = [data_source_delegate insertChild:tree_item_new withParent:tree_item_prev];

			// directly update the outlineview so we don't have to reloadData
			NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:target_index];
			[outline_view insertItemsAtIndexes:index_set inParent:tree_item_prev withAnimation:NSTableViewAnimationEffectNone];

		}
		else
		{
			// insert the new node after reference node
			/* same depth */
			
			// update the data source
			NSUInteger target_index = [data_source_delegate insertPeer:tree_item_new withSibling:tree_item_prev];

			// directly update the outlineview so we don't have to reloadData
			// It is okay if the parent is nil. This also handles the case where ADDROOT=NO and we are adding another top-level node.
			IupCocoaTreeItem* tree_item_parent = [tree_item_prev parentItem];
			NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:target_index];
			[outline_view insertItemsAtIndexes:index_set inParent:tree_item_parent withAnimation:NSTableViewAnimationEffectNone];

		}

		iupTreeAddToCache(ih, add, kind_prev, inode_prev, inode_new);

	}
	else
	{
		//  add the new node at root
		[data_source_delegate insertAtRoot:tree_item_new];
		// directly update the outlineview so we don't have to reloadData
		[outline_view insertItemsAtIndexes:[NSIndexSet indexSetWithIndex:0] inParent:nil withAnimation:NSTableViewAnimationEffectNone];

		iupTreeAddToCache(ih, 0, 0, NULL, inode_new);

	}
	// We don't need to reloadData if we update the outline view directly.
//	[outline_view reloadData];

	if(ITREE_BRANCH == kind)
	{
		BOOL should_expand = IupGetInt(ih, "ADDEXPANDED");
		if(should_expand)
		{
			// Just in case we do have children already, expand now which may skip the animation delay.
			//[outline_view expandItem:tree_item_new];
			[outline_view expandItem:tree_item_new expandChildren:YES];
#if 0
			// Tricky: This wasn't working until I added dispatch_async.
			// I think the problem is that when I expand a branch, the children may not be added yet.
			// So if there are no children at the time, my expand request gets ignored.
			// The dispatch_async will force the expand to happen on the next event loop pass, after any children have been added from this loop.
			// So the expand will work now that the children exist.
			// UPDATE: This is now fixed by using
			// - (BOOL) outlineView:(NSOutlineView*)outline_view isItemExpandable:(id)the_item
			// and making it rely on "kind" to determine if expandable instead of number of children.
			dispatch_async(dispatch_get_main_queue(), ^{
//				[outline_view expandItem:tree_item_new];
				[outline_view expandItem:tree_item_new expandChildren:YES];
				}
			);
#endif
		}
	}
	
	// make sure to release since it should now be retained by the data_source_delegate
	[tree_item_new release];
}



int iupdrvTreeTotalChildCount(Ihandle* ih, InodeHandle* node_handle)
{
//	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
//	IupCocoaTreeDelegate* data_source_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)node_handle;
	NSUInteger number_of_items = [tree_item numberOfChildren];
	return (int)number_of_items;
}

InodeHandle* iupdrvTreeGetFocusNode(Ihandle* ih)
{
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);

	id selected_item = [outline_view itemAtRow:[outline_view selectedRow]];

	
	
	return (InodeHandle*)selected_item;
}


// FIXME: Why does the GTK version look so different?
void iupdrvTreeUpdateMarkMode(Ihandle *ih)
{
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
	const char* mark_mode = iupAttribGet(ih, "MARKMODE");
	if(iupStrEqualNoCase(mark_mode, "MULTIPLE"))
	{
		[outline_view setAllowsMultipleSelection:YES];
	}
	else
	{
		[outline_view setAllowsMultipleSelection:NO];
	}
}



void iupdrvTreeDragDropCopyNode(Ihandle* src, Ihandle* dst, InodeHandle *itemSrc, InodeHandle *itemDst)
{
	
}


static int cocoaTreeSetDelNodeAttrib(Ihandle* ih, int node_id, const char* value)
{
	if (!ih->handle)  /* do not do the action before map */
	return 0;

	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
	IupCocoaTreeDelegate* data_source_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];


	if (iupStrEqualNoCase(value, "ALL"))
	{
		NSUInteger number_of_items = [data_source_delegate numberOfItems];
		if(number_of_items > 0)
		{

			[data_source_delegate removeAllObjects];

			// Scuri says not required to handle for delete.
			// [data_source_delegate handleSelectionDidChange:outline_view];

			// If there are multiple nodes at the root (ADDROOT=NO), it seems easier to reloadData than to hunt down and remove each node.
			[outline_view reloadData];

		}

		return 0;
	}
	if (iupStrEqualNoCase(value, "SELECTED"))  /* selected here means the reference node */
	{

		IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)iupTreeGetNode(ih, node_id);

		if(!tree_item)
		{
			return 0;
		}
		NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"expecting class IupCocoaTreeItem");

		[outline_view beginUpdates];

		IupCocoaTreeItem* parent_tree_item = [tree_item parentItem]; // get parent before removing because it may nil out the parent in removeItem
		NSUInteger target_index = [data_source_delegate removeItem:tree_item];
		//	[outline_view reloadData];

		if(NSNotFound != target_index)
		{
			NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:target_index];
			[outline_view removeItemsAtIndexes:index_set inParent:parent_tree_item withAnimation:NSTableViewAnimationEffectNone];
		}

		// Scuri says not required to handle for delete.
		// [data_source_delegate handleSelectionDidChange:outline_view];

		[outline_view endUpdates];

	}
	else if(iupStrEqualNoCase(value, "CHILDREN"))  /* children of the reference node */
	{
		IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)iupTreeGetNode(ih, node_id);

		if(!tree_item)
		{
			return 0;
		}
		NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"expecting class IupCocoaTreeItem");
		
		[outline_view beginUpdates];

		NSIndexSet* index_set = [data_source_delegate removeAllChildrenForItem:tree_item];
		[outline_view removeItemsAtIndexes:index_set inParent:tree_item withAnimation:NSTableViewAnimationEffectNone];

		//[outline_view reloadData];

		// Scuri says not required to handle for delete.
		// [data_source_delegate handleSelectionDidChange:outline_view];

		[outline_view endUpdates];

		return 0;
		
	}
	else if(iupStrEqualNoCase(value, "MARKED"))  /* Delete the array of marked nodes */
	{
		[outline_view beginUpdates];
		NSIndexSet* selected_index = [outline_view selectedRowIndexes];

		NSUInteger selected_i = [selected_index firstIndex];
		while(selected_i != NSNotFound)
		{
			id selected_item = [outline_view itemAtRow:selected_i];

			// I can't figure out how to make this work correctly when you select both parents and its children to be deleted.
			// Use reloadData for now.
#if 0
			IupCocoaTreeItem* parent_tree_item  = [(IupCocoaTreeItem*)selected_item parentItem];
			NSUInteger target_index = [data_source_delegate removeItem:selected_item];
			
			NSIndexSet* index_set = [NSIndexSet indexSetWithIndex:target_index];
			[outline_view removeItemsAtIndexes:index_set inParent:parent_tree_item withAnimation:NSTableViewAnimationEffectNone];
#else
			[data_source_delegate removeItem:selected_item];
#endif

			
			// get the next index in the set
			selected_i = [selected_index indexGreaterThanIndex:selected_i];
		}

		[outline_view reloadData];

		// Scuri says not required to handle for delete.
		// [data_source_delegate handleSelectionDidChange:outline_view];
		[outline_view endUpdates];

	}

	return 0;
}


/*****************************************************************************/
/* MANIPULATING IMAGES                                                       */
/*****************************************************************************/

static NSImage* helperGetImage(Ihandle* ih, int node_id, const char* value, IupCocoaTreeItem* tree_item)
{
	if(!tree_item)
	{
		return nil;
	}

	NSImage* bitmap_image = nil;
	
	if(iupStrEqualNoCase("IMGEMPTY", value))
	{
		bitmap_image = nil;
	}
	else
	{
		bitmap_image = (NSImage*)iupImageGetImage(value, ih, 0);
	}

	return bitmap_image;
}

static int cocoaTreeSetImageExpandedAttrib(Ihandle* ih, int node_id, const char* value)
{
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)iupTreeGetNode(ih, node_id);
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);

	NSImage* bitmap_image = helperGetImage(ih, node_id, value, tree_item);
	
	// Oh how ironic and tragic.
	// I combined expanded and leaf into the same variable and made collapsed separate.
	// But IUP combined collpased and leaf into the same variable and made expanded separate.
	[tree_item setBitmapImage:bitmap_image];
	cocoaTreeReloadItem(tree_item, outline_view);

	return 1;
}

static int cocoaTreeSetImageAttrib(Ihandle* ih, int node_id, const char* value)
{
	IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)iupTreeGetNode(ih, node_id);
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);

	NSImage* bitmap_image = helperGetImage(ih, node_id, value, tree_item);

	
	// Oh how ironic and tragic.
	// I combined expanded and leaf into the same variable and made collapsed separate.
	// But IUP combined collpased and leaf into the same variable and made expanded separate.
	if([tree_item kind] == ITREE_LEAF)
	{
		[tree_item setBitmapImage:bitmap_image];
	}
	else
	{
		[tree_item setCollapsedImage:bitmap_image];
	}
	cocoaTreeReloadItem(tree_item, outline_view);

	return 0;
}

static void helperSetImageBranchExpanded(IupCocoaOutlineView* outline_view, IupCocoaTreeItem* tree_item, NSImage* ns_image)
{
	for(IupCocoaTreeItem* a_item in [tree_item childrenArray])
	{
		helperSetImageBranchExpanded(outline_view, a_item, ns_image);
	}
	if([tree_item kind] == ITREE_BRANCH)
	{
		// only need to reload if the user hasn't overridden with a custom-per-node image.
		if(![tree_item bitmapImage])
		{
			cocoaTreeReloadItem(tree_item, outline_view);
		}
	}
}

static int cocoaTreeSetImageBranchExpandedAttrib(Ihandle* ih, const char* value)
{
	NSImage* ns_image = (NSImage*)iupImageGetImage(value, ih, 0);
	IupCocoaOutlineView* outline_view = (IupCocoaOutlineView*)cocoaTreeGetOutlineView(ih);

	[outline_view beginUpdates];

	[outline_view setExpandedImage:ns_image];

	/* Update all images */
	IupCocoaTreeDelegate* tree_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	for(IupCocoaTreeItem* tree_item in [tree_delegate treeRootTopLevelObjects])
	{
		helperSetImageBranchExpanded(outline_view, tree_item, ns_image);
	}
	
	[outline_view endUpdates];

	return 1;
}


static void helperSetImageBranchCollapsed(IupCocoaOutlineView* outline_view, IupCocoaTreeItem* tree_item, NSImage* ns_image)
{
	for(IupCocoaTreeItem* a_item in [tree_item childrenArray])
	{
		helperSetImageBranchCollapsed(outline_view, a_item, ns_image);
	}
	// only need to reload if the user hasn't overridden with a custom-per-node image.
	if([tree_item kind] == ITREE_BRANCH)
	{
		// only need to reload if the user hasn't overridden with a custom-per-node image.
		if(![tree_item collapsedImage])
		{
			cocoaTreeReloadItem(tree_item, outline_view);
		}
	}
}

static int cocoaTreeSetImageBranchCollapsedAttrib(Ihandle* ih, const char* value)
{
	NSImage* ns_image = (NSImage*)iupImageGetImage(value, ih, 0);
	IupCocoaOutlineView* outline_view = (IupCocoaOutlineView*)cocoaTreeGetOutlineView(ih);

	[outline_view beginUpdates];

	[outline_view setCollapsedImage:ns_image];

	/* Update all images */
	IupCocoaTreeDelegate* tree_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	for(IupCocoaTreeItem* tree_item in [tree_delegate treeRootTopLevelObjects])
	{
		helperSetImageBranchCollapsed(outline_view, tree_item, ns_image);
	}
	
	[outline_view endUpdates];

	return 1;
}

static void helperSetImageLeaf(IupCocoaOutlineView* outline_view, IupCocoaTreeItem* tree_item, NSImage* ns_image)
{
	for(IupCocoaTreeItem* a_item in [tree_item childrenArray])
	{
		helperSetImageLeaf(outline_view, a_item, ns_image);
	}
	if([tree_item kind] == ITREE_LEAF)
	{
		// only need to reload if the user hasn't overridden with a custom-per-node image.
		if(![tree_item bitmapImage])
		{
			cocoaTreeReloadItem(tree_item, outline_view);
		}
	}
}

static int cocoaTreeSetImageLeafAttrib(Ihandle* ih, const char* value)
{
	NSImage* ns_image = (NSImage*)iupImageGetImage(value, ih, 0);
	IupCocoaOutlineView* outline_view = (IupCocoaOutlineView*)cocoaTreeGetOutlineView(ih);

	[outline_view beginUpdates];

	[outline_view setLeafImage:ns_image];

	/* Update all images */
	IupCocoaTreeDelegate* tree_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	for(IupCocoaTreeItem* tree_item in [tree_delegate treeRootTopLevelObjects])
	{
		helperSetImageLeaf(outline_view, tree_item, ns_image);
	}
	
	[outline_view endUpdates];

	return 1;
}


/*****************************************************************************/
/* AUXILIAR FUNCTIONS                                                        */
/*****************************************************************************/

static char* cocoaTreeGetTitleAttrib(Ihandle* ih, int item_id)
{
//	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
//	IupCocoaTreeDelegate* data_source_delegate = (IupCocoaTreeDelegate*)[outline_view dataSource];
	
	InodeHandle* inode_handle = iupTreeGetNode(ih, item_id);

	if(inode_handle)
	{
		IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)inode_handle;
		NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"expecting class IupCocoaTreeItem");
		NSString* ns_title = [tree_item title];
		return iupStrReturnStr([ns_title UTF8String]);
	}
	else
	{
		return NULL;
	}
}

static int cocoaTreeSetTitleAttrib(Ihandle* ih, int item_id, const char* value)
{
	InodeHandle* inode_handle = iupTreeGetNode(ih, item_id);
	
	if(inode_handle)
	{
		NSString* ns_title = @"";
		if(value)
		{
			ns_title = [NSString stringWithUTF8String:value];
		}
		
		IupCocoaTreeItem* tree_item = (IupCocoaTreeItem*)inode_handle;
		NSCAssert([tree_item isKindOfClass:[IupCocoaTreeItem class]], @"expecting class IupCocoaTreeItem");
		[tree_item setTitle:ns_title];
		NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);

		cocoaTreeReloadItem(tree_item, outline_view);
	}

	return 0;
}

static int cocoaTreeSetExpandAllAttrib(Ihandle* ih, const char* value)
{
	NSOutlineView* outline_view = cocoaTreeGetOutlineView(ih);
	bool should_expand = iupStrBoolean(value);
	
	if(should_expand)
	{
		// item=nil should do all root items
		[outline_view expandItem:nil expandChildren:YES];
	}
	else
	{
		// item=nil should do all root items
		[outline_view collapseItem:nil collapseChildren:YES];
	}

  return 0;
}


static int cocoaTreeMapMethod(Ihandle* ih)
{
	NSBundle* framework_bundle = [NSBundle bundleWithIdentifier:@"br.puc-rio.tecgraf.iup"];
	NSNib* outline_nib = [[NSNib alloc] initWithNibNamed:@"IupCocoaOutlineView" bundle:framework_bundle];
	
	
	NSArray* top_level_objects = nil;
	
	
	IupCocoaOutlineView* outline_view = nil;
	NSScrollView* scroll_view = nil;
	
	if([outline_nib instantiateWithOwner:nil topLevelObjects:&top_level_objects])
	{
		for(id current_object in top_level_objects)
		{

			if([current_object isKindOfClass:[NSScrollView class]])
			{
				scroll_view = current_object;
				break;
			}
		}
	}
	
	outline_view = (IupCocoaOutlineView*)[scroll_view documentView];
	NSCAssert([outline_view isKindOfClass:[IupCocoaOutlineView class]], @"Expected IupCocoaOutlineView");
	
	// ScrollView is expected to hold on to all the other objects we need
	[scroll_view retain];
	[outline_nib release];
	
	// We need a way to get the ih during Cocoa callbacks, such as for selection changed notifications.
	[outline_view setIh:ih];

	
	IupCocoaTreeDelegate* tree_delegate = [[IupCocoaTreeDelegate alloc] init];
	
	[outline_view setDataSource:tree_delegate];
	[outline_view setDelegate:tree_delegate];
	

	
	// We're going to use OBJC_ASSOCIATION_RETAIN because I do believe it will do the right thing for us.
	// I'm attaching to the scrollview instead of the outline view because I'm a little worried about circular references and I'm hoping this helps a little
	objc_setAssociatedObject(scroll_view, IUP_COCOA_TREE_DELEGATE_OBJ_KEY, (id)tree_delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	[tree_delegate release];
	
	ih->handle = scroll_view;
	
	
	
	// All Cocoa views shoud call this to add the new view to the parent view.
	iupCocoaAddToParent(ih);
	
	
	
	// turn off the header
	[outline_view setHeaderView:nil];

	/* Initialize the default images */
	NSImage* leaf_image = iupImageGetImage(iupAttribGetStr(ih, "IMAGELEAF"), ih, 0);
//	NSImage* collapsed_image = iupImageGetImage(iupAttribGetStr(ih, "IMAGEBRANCHCOLLAPSED"), ih, 0);
//	NSImage* expanded_image = iupImageGetImage(iupAttribGetStr(ih, "IMAGEBRANCHEXPANDED"), ih, 0);

	NSImage* collapsed_image = [NSImage imageNamed:NSImageNameFolder];
//	NSImage* expanded_image = [NSImage imageNamed:NSImageNameFolder];
	NSImage* expanded_image = collapsed_image;

	[outline_view setLeafImage:leaf_image];
	[outline_view setCollapsedImage:collapsed_image];
	[outline_view setExpandedImage:expanded_image];


	if (iupAttribGetInt(ih, "ADDROOT"))
	{
		iupdrvTreeAddNode(ih, -1, ITREE_BRANCH, "", 0);
	}
	
	/* configure for DRAG&DROP of files */
	if (IupGetCallback(ih, "DROPFILES_CB"))
	{
		iupAttribSet(ih, "DROPFILESTARGET", "YES");
	}
	
//	IupSetCallback(ih, "_IUP_XY2POS_CB", (Icallback)cocoaTreeConvertXYToPos);
	
	iupdrvTreeUpdateMarkMode(ih);

	
	
	return IUP_NOERROR;
}

static void cocoaTreeUnMapMethod(Ihandle* ih)
{
	id root_view = ih->handle;
	
	
	iupCocoaRemoveFromParent(ih);
	[root_view release];
	ih->handle = NULL;
}




void iupdrvTreeInitClass(Iclass* ic)
{
	/* Driver Dependent Class functions */
	ic->Map = cocoaTreeMapMethod;
	ic->UnMap = cocoaTreeUnMapMethod;
#if 0
	
	/* Visual */
	iupClassRegisterAttribute(ic, "BGCOLOR", NULL, cocoaTreeSetBgColorAttrib, IUPAF_SAMEASSYSTEM, "TXTBGCOLOR", IUPAF_DEFAULT);
	iupClassRegisterAttribute(ic, "FGCOLOR", NULL, cocoaTreeSetFgColorAttrib, IUPAF_SAMEASSYSTEM, "TXTFGCOLOR", IUPAF_DEFAULT);
#endif
	/* IupTree Attributes - GENERAL */
	iupClassRegisterAttribute(ic, "EXPANDALL", NULL, cocoaTreeSetExpandAllAttrib, NULL, NULL, IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
#if 0
	iupClassRegisterAttribute(ic, "INDENTATION", cocoaTreeGetIndentationAttrib, cocoaTreeSetIndentationAttrib, NULL, NULL, IUPAF_DEFAULT);
	iupClassRegisterAttribute(ic, "SPACING", iupTreeGetSpacingAttrib, cocoaTreeSetSpacingAttrib, IUPAF_SAMEASSYSTEM, "0", IUPAF_NOT_MAPPED);
	iupClassRegisterAttribute(ic, "TOPITEM", NULL, cocoaTreeSetTopItemAttrib, NULL, NULL, IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
#endif
	/* IupTree Attributes - IMAGES */
	iupClassRegisterAttributeId(ic, "IMAGE", NULL, cocoaTreeSetImageAttrib, IUPAF_IHANDLENAME|IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "IMAGEEXPANDED", NULL, cocoaTreeSetImageExpandedAttrib, IUPAF_IHANDLENAME|IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	
	iupClassRegisterAttribute(ic, "IMAGELEAF",            NULL, cocoaTreeSetImageLeafAttrib, IUPAF_SAMEASSYSTEM, "IMGLEAF", IUPAF_IHANDLENAME|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "IMAGEBRANCHCOLLAPSED", NULL, cocoaTreeSetImageBranchCollapsedAttrib, IUPAF_SAMEASSYSTEM, "IMGCOLLAPSED", IUPAF_IHANDLENAME|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute(ic, "IMAGEBRANCHEXPANDED",  NULL, cocoaTreeSetImageBranchExpandedAttrib, IUPAF_SAMEASSYSTEM, "IMGEXPANDED", IUPAF_IHANDLENAME|IUPAF_NO_INHERIT);

#if 0
	/* IupTree Attributes - NODES */
	iupClassRegisterAttributeId(ic, "STATE",  cocoaTreeGetStateAttrib,  cocoaTreeSetStateAttrib, IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "DEPTH",  cocoaTreeGetDepthAttrib,  NULL, IUPAF_READONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "KIND",   cocoaTreeGetKindAttrib,   NULL, IUPAF_READONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "PARENT", cocoaTreeGetParentAttrib, NULL, IUPAF_READONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "COLOR",  cocoaTreeGetColorAttrib,  cocoaTreeSetColorAttrib, IUPAF_NO_INHERIT);
#endif
	
	iupClassRegisterAttributeId(ic, "TITLE",  cocoaTreeGetTitleAttrib,  cocoaTreeSetTitleAttrib, IUPAF_NO_INHERIT);
	
#if 0
	iupClassRegisterAttributeId(ic, "TOGGLEVALUE", cocoaTreeGetToggleValueAttrib, cocoaTreeSetToggleValueAttrib, IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "TOGGLEVISIBLE", cocoaTreeGetToggleVisibleAttrib, cocoaTreeSetToggleVisibleAttrib, IUPAF_NO_INHERIT);
	
	/* Change the set method for GTK */
	iupClassRegisterReplaceAttribFunc(ic, "SHOWRENAME", NULL, cocoaTreeSetShowRenameAttrib);
	
	iupClassRegisterAttributeId(ic, "CHILDCOUNT", cocoaTreeGetChildCountAttrib, NULL, IUPAF_READONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "TITLEFONT",  cocoaTreeGetTitleFontAttrib,  cocoaTreeSetTitleFontAttrib, IUPAF_NO_INHERIT);
	
	/* IupTree Attributes - MARKS */
	iupClassRegisterAttributeId(ic, "MARKED", cocoaTreeGetMarkedAttrib, cocoaTreeSetMarkedAttrib, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute  (ic, "MARK",      NULL, cocoaTreeSetMarkAttrib,      NULL, NULL, IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute  (ic, "STARTING",  NULL, cocoaTreeSetMarkStartAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute  (ic, "MARKSTART", NULL, cocoaTreeSetMarkStartAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	iupClassRegisterAttribute  (ic, "MARKEDNODES", cocoaTreeGetMarkedNodesAttrib, cocoaTreeSetMarkedNodesAttrib, NULL, NULL, IUPAF_NO_SAVE|IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	
	iupClassRegisterAttribute(ic, "MARKWHENTOGGLE", NULL, NULL, NULL, NULL, IUPAF_NO_INHERIT);
	
	iupClassRegisterAttribute  (ic, "VALUE", cocoaTreeGetValueAttrib, cocoaTreeSetValueAttrib, NULL, NULL, IUPAF_NO_DEFAULTVALUE|IUPAF_NO_INHERIT);
	
	/* IupTree Attributes - ACTION */
#endif
	iupClassRegisterAttributeId(ic, "DELNODE", NULL, cocoaTreeSetDelNodeAttrib, IUPAF_NOT_MAPPED|IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
#if 0
	iupClassRegisterAttribute(ic, "RENAME", NULL, cocoaTreeSetRenameAttrib, NULL, NULL, IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "MOVENODE", NULL, cocoaTreeSetMoveNodeAttrib, IUPAF_NOT_MAPPED|IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	iupClassRegisterAttributeId(ic, "COPYNODE", NULL, cocoaTreeSetCopyNodeAttrib, IUPAF_NOT_MAPPED|IUPAF_WRITEONLY|IUPAF_NO_INHERIT);
	
	/* IupTree Attributes - GTK Only */
	iupClassRegisterAttribute  (ic, "RUBBERBAND", NULL, NULL, IUPAF_SAMEASSYSTEM, "YES", IUPAF_NO_INHERIT);
#endif
}
