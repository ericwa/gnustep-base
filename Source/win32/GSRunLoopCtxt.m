/**
 * The GSRunLoopCtxt stores context information to handle polling for
 * events.  This information is associated with a particular runloop
 * mode, and persists throughout the life of the runloop instance.
 *
 *	NB.  This class is private to NSRunLoop and must not be subclassed.
 */

#include "config.h"

#include "GNUstepBase/preface.h"
#include "../GSRunLoopCtxt.h"
#include "../GSRunLoopWatcher.h"
#include "../GSPrivate.h"
#include <Foundation/NSDebug.h>
#include <Foundation/NSNotificationQueue.h>
#include <Foundation/NSPort.h>
#include <Foundation/NSStream.h>

extern BOOL	GSCheckTasks();

#if	GS_WITH_GC == 0
SEL	wRelSel;
SEL	wRetSel;
IMP	wRelImp;
IMP	wRetImp;

static void
wRelease(NSMapTable* t, void* w)
{
  (*wRelImp)((id)w, wRelSel);
}

static void
wRetain(NSMapTable* t, const void* w)
{
  (*wRetImp)((id)w, wRetSel);
}

static const NSMapTableValueCallBacks WatcherMapValueCallBacks = 
{
  wRetain,
  wRelease,
  0
};
#else
#define	WatcherMapValueCallBacks	NSOwnedPointerMapValueCallBacks 
#endif

@implementation	GSRunLoopCtxt
- (void) dealloc
{
  RELEASE(mode);
  GSIArrayEmpty(performers);
  NSZoneFree(performers->zone, (void*)performers);
  GSIArrayEmpty(timers);
  NSZoneFree(timers->zone, (void*)timers);
  GSIArrayEmpty(watchers);
  NSZoneFree(watchers->zone, (void*)watchers);
  if (handleMap != 0)
    {
      NSFreeMapTable(handleMap);
    }
  if (winMsgMap != 0)
    {
      NSFreeMapTable(winMsgMap);
    }
  GSIArrayEmpty(_trigger);
  NSZoneFree(_trigger->zone, (void*)_trigger);
  [super dealloc];
}

/**
 * Remove any callback for the specified event which is set for an
 * uncompleted poll operation.<br />
 * This is called by nested event loops on contexts in outer loops
 * when they handle an event ... removing the event from the outer
 * loop ensures that it won't get handled twice, once by the inner
 * loop and once by the outer one.
 */
- (void) endEvent: (void*)data
              for: (GSRunLoopWatcher*)watcher
{
  if (completed == NO)
    {
      unsigned i = GSIArrayCount(_trigger);

      while (i-- > 0)
	{
	  GSIArrayItem	item = GSIArrayItemAtIndex(_trigger, i);

	  if (item.obj == (id)watcher)
	    {
	      GSIArrayRemoveItemAtIndex(_trigger, i);
	    }
	}
      switch (watcher->type)
	{
	  case ET_RPORT:
	  case ET_HANDLE:
	    NSMapRemove(handleMap, data);
	    break;
	  case ET_WINMSG:
	    NSMapRemove(winMsgMap, data);
	    break;
	  case ET_TRIGGER:
	    // Already handled
	    break;
	  default:
	    NSLog(@"Ending an event of unexpected type (%d)", watcher->type);
	    break;
	}
    }
}

/**
 * Mark this poll context as having completed, so that if we are
 * executing a re-entrant poll, the enclosing poll operations
 * know they can stop what they are doing because an inner
 * operation has done the job.
 */
- (void) endPoll
{
  completed = YES;
}

- (id) init
{
  [NSException raise: NSInternalInconsistencyException
	      format: @"-init may not be called for GSRunLoopCtxt"];
  return nil;
}

- (id) initWithMode: (NSString*)theMode extra: (void*)e
{
  self = [super init];
  if (self != nil)
    {
      NSZone	*z = [self zone];

      mode = [theMode copy];
      extra = e;
      performers = NSZoneMalloc(z, sizeof(GSIArray_t));
      GSIArrayInitWithZoneAndCapacity(performers, z, 8);
      timers = NSZoneMalloc(z, sizeof(GSIArray_t));
      GSIArrayInitWithZoneAndCapacity(timers, z, 8);
      watchers = NSZoneMalloc(z, sizeof(GSIArray_t));
      GSIArrayInitWithZoneAndCapacity(watchers, z, 8);

      handleMap = NSCreateMapTable(NSIntMapKeyCallBacks,
              WatcherMapValueCallBacks, 0);
      winMsgMap = NSCreateMapTable(NSIntMapKeyCallBacks,
              WatcherMapValueCallBacks, 0);
      _trigger = NSZoneMalloc(z, sizeof(GSIArray_t));
      GSIArrayInitWithZoneAndCapacity(_trigger, z, 8);
    }
  return self;
}

/*
 * If there is a generic watcher (watching hwnd == 0),
 * loop through all events, and send them to the correct
 * watcher (if there are any) and then process the rest right here.
 * Return a flag to say whether any messages were handled.
 */
- (BOOL) processAllWindowsMessages:(int)num_winMsgs within: (NSArray*)contexts
{
  MSG			msg;
  GSRunLoopWatcher	*generic = nil;
  unsigned		i;
  BOOL			handled = NO;

  if (num_winMsgs > 0)
    {
      generic = NSMapGet(winMsgMap,0);
    }
  
  if (generic != nil && generic->_invalidated == NO)
    {
      while (PeekMessage(&msg, 0, 0, 0, PM_REMOVE))
	{
	  if (num_winMsgs > 0)
	    {
	      HANDLE		handle;
	      GSRunLoopWatcher	*watcher;

	      handle = msg.hwnd;
	      watcher = (GSRunLoopWatcher*)NSMapGet(winMsgMap,
		(void*)handle);
	      if (watcher == nil || watcher->_invalidated == YES)
		{
		  handle = 0;	// Generic
		  watcher
		    = (GSRunLoopWatcher*)NSMapGet(winMsgMap, (void*)handle);
		}
	      if (watcher != nil && watcher->_invalidated == NO)
		{
		  i = [contexts count];
		  while (i-- > 0)
		    {
		      GSRunLoopCtxt *c = [contexts objectAtIndex: i];

		      if (c != self)
			{ 
			  [c endEvent: (void*)handle for: watcher];
			}
		    }
		  handled = YES;
		  /*
		   * The watcher is still valid - so call the
		   * receiver's event handling method.
		   */
		  [watcher->receiver receivedEvent: watcher->data
					      type: watcher->type
					     extra: (void*)&msg
					   forMode: mode];
		  continue;
		}
	    }
	  TranslateMessage(&msg); 
	  DispatchMessage(&msg);
	}
    }
  else
    {
      if (num_winMsgs > 0)
	{
	  unsigned		num = num_winMsgs;
	  NSMapEnumerator	hEnum;
	  HANDLE		handle;
	  GSRunLoopWatcher	*watcher;

	  hEnum = NSEnumerateMapTable(winMsgMap);
	  while (NSNextMapEnumeratorPair(&hEnum, &handle, (void**)&watcher))
	    {
	      if (watcher->_invalidated == NO)
		{
		  while (PeekMessage(&msg, handle, 0, 0, PM_REMOVE))
		    {
		      i = [contexts count];
		      while (i-- > 0)
			{
			  GSRunLoopCtxt *c = [contexts objectAtIndex: i];
			      
			  if (c != self)
			    {
			      [c endEvent: (void*)handle for: watcher];
			    }
			}
		      handled = YES;
		      [watcher->receiver receivedEvent: watcher->data
						  type: watcher->type
						 extra: (void*)&msg
					       forMode: mode];
		    }
		}
	      num--;
	    }
	  NSEndMapTableEnumeration(&hEnum);
	} 
    }
  return handled;
}

- (BOOL) pollUntil: (int)milliseconds within: (NSArray*)contexts
{
  NSMapEnumerator	hEnum;
  GSRunLoopWatcher	*watcher;
  HANDLE		handleArray[MAXIMUM_WAIT_OBJECTS-1];
  int			num_handles;
  int			num_winMsgs;
  unsigned		count;
  unsigned		i;
  void			*handle;
  int			wait_timeout;
  DWORD			wait_return;
  BOOL			immediate = NO;

  // Set timeout how much time should wait
  if (milliseconds >= 0)
    {
      wait_timeout = milliseconds;
    }
  else
    {
      wait_timeout = INFINITE;
    }

  NSResetMapTable(handleMap);
  NSResetMapTable(winMsgMap);
  GSIArrayRemoveAllItems(_trigger);

  i = GSIArrayCount(watchers);
  num_handles = 0;
  num_winMsgs = 0;
  while (i-- > 0)
    {
      GSRunLoopWatcher	*info;
      BOOL		trigger;
      
      info = GSIArrayItemAtIndex(watchers, i).obj;
      if (info->_invalidated == YES)
	{
	  GSIArrayRemoveItemAtIndex(watchers, i);
	}
      else if ([info runLoopShouldBlock: &trigger] == NO)
	{
	  if (trigger == YES)
	    {
	      immediate = YES;
	      GSIArrayAddItem(_trigger, (GSIArrayItem)(id)info);
	    }
	}
      else
	{
	  HANDLE	handle;

	  switch (info->type)
	    {
	      case ET_HANDLE:
		handle = (HANDLE)(int)info->data;
		NSMapInsert(handleMap, (void*)handle, info);
		num_handles++;
		break;
	      case ET_RPORT:
		{
		  id port = info->receiver;
		  int port_handle_count = 128; // #define this constant
		  int port_handle_array[port_handle_count];
		  if ([port respondsToSelector: @selector(getFds:count:)])
		    {
		      [port getFds: port_handle_array
			     count: &port_handle_count];
		    }
		  else
		    {
		      NSLog(@"pollUntil - Impossible get win32 Handles");
		      abort();
		    }
		  NSDebugMLLog(@"NSRunLoop", @"listening to %d port handles",
		    port_handle_count);
		  while (port_handle_count--)
		    {
		      NSMapInsert(handleMap, 
			(void*)port_handle_array[port_handle_count], info);
		      num_handles++;
		    }
		}
		break;
	      case ET_WINMSG:
		handle = (HANDLE)(int)info->data;
		NSMapInsert(winMsgMap, (void*)handle, info);
		num_winMsgs++;
		break;
	      case ET_TRIGGER:
		break;
	    }
	}
    }
    
  /*
   * If there are notifications in the 'idle' queue, we try an
   * instantaneous select so that, if there is no input pending,
   * we can service the queue.  Similarly, if a task has completed,
   * we need to deliver its notifications.
   */
  if (GSCheckTasks() || GSNotifyMore() || immediate == YES)
    {
      wait_timeout = 0;
    }

  i = 0;
  hEnum = NSEnumerateMapTable(handleMap);
  while (NSNextMapEnumeratorPair(&hEnum, &handle, (void**)&watcher))
    {
      if (i < MAXIMUM_WAIT_OBJECTS-1)
	{
	  handleArray[i++] = (HANDLE)handle;
	}
      else
	{
	  NSLog(@"Too many handles to wait for ... only using %d of %d",
	    i, num_handles);
	}
    }
  NSEndMapTableEnumeration(&hEnum);
  num_handles = i;

  /* Clear all the windows messages first before we wait,
   * since MsgWaitForMultipleObjects only signals on NEW messages
   */
  if ([self processAllWindowsMessages: num_winMsgs within: contexts] == YES)
    {
      wait_timeout = 0;	// Processed something ... no need to wait.
    }

  if (num_winMsgs > 0)
    {
      /*
       * Wait for signalled events or window messages.
       */
      wait_return = MsgWaitForMultipleObjects(num_handles, handleArray, 
        NO, wait_timeout, QS_ALLINPUT);
    }
  else if (num_handles > 0)
    {
      /*
       * We are not interested in windows messages ... just wait for
       * signalled events.
       */
      wait_return = WaitForMultipleObjects(num_handles, handleArray, 
        NO, wait_timeout);
    }
  else
    {
      wait_return = WAIT_OBJECT_0;
    }
  NSDebugMLLog(@"NSRunLoop", @"wait returned %d", wait_return);

  // check wait errors
  if (wait_return == WAIT_FAILED)
    {
      int	i;
      BOOL	found = NO;

      NSDebugMLLog(@"NSRunLoop", @"WaitForMultipleObjects() error in "
	@"-acceptInputForMode:beforeDate: %s",
	GSLastErrorStr(GetLastError()));
      /*
       * Check each handle in turn until either we find one which has an
       * event signalled, or we find the one which caused the original
       * wait to fail ... so the callback routine for that handle can
       * deal with the problem.
       */
      for (i = 0; i < num_handles; i++)
	{
	  handleArray[0] = handleArray[i];
	  wait_return = WaitForMultipleObjects(1, handleArray, NO, 0);
	  if (wait_return != WAIT_TIMEOUT)
	    {
	      wait_return = WAIT_OBJECT_0;
	      found = YES;
	      break;
	    }
	}
      if (found == NO)
	{
	  NSLog(@"WaitForMultipleObjects() error in "
	    @"-acceptInputForMode:beforeDate: %s",
	    GSLastErrorStr(GetLastError()));
	  abort ();        
	}
    }

  /*
   * Trigger any watchers which are set up to for every runloop wait.
   */
  count = GSIArrayCount(_trigger);
  completed = NO;
  while (completed == NO && count-- > 0)
    {
      GSRunLoopWatcher	*watcher;

      watcher = (GSRunLoopWatcher*)GSIArrayItemAtIndex(_trigger, count).obj;
	if (watcher->_invalidated == NO)
	  {
	    i = [contexts count];
	    while (i-- > 0)
	      {
		GSRunLoopCtxt	*c = [contexts objectAtIndex: i];

		if (c != self)
		  {
		    [c endEvent: (void*)watcher for: watcher];
		  }
	      }
	    /*
	     * The watcher is still valid - so call its
	     * receivers event handling method.
	     */
	    [watcher->receiver receivedEvent: watcher->data
					type: watcher->type
				       extra: watcher->data
				     forMode: mode];
	  }
	GSNotifyASAP();
    }

  // if there are windows message
  if (wait_return == WAIT_OBJECT_0 + num_handles)
    {
      [self processAllWindowsMessages: num_winMsgs within: contexts];
      return NO;
    }

  // if there arent events
  if (wait_return == WAIT_TIMEOUT)
    {
      completed = YES;
      return NO;        
    }
  
  /*
   * Look the event that WaitForMultipleObjects() says is ready;
   * get the corresponding fd for that handle event and notify
   * the corresponding object for the ready fd.
   */
  i = wait_return - WAIT_OBJECT_0;

  NSDebugMLLog(@"NSRunLoop", @"Event listen %d", i);
  
  handle = handleArray[i];

  watcher = (GSRunLoopWatcher*)NSMapGet(handleMap, (void*)handle);
  if (watcher != nil && watcher->_invalidated == NO)
    {
      i = [contexts count];
      while (i-- > 0)
        {
          GSRunLoopCtxt *c = [contexts objectAtIndex: i];

          if (c != self)
            { 
              [c endEvent: (void*)handle for: watcher];
            }
	}
      /*
       * The watcher is still valid - so call its receivers
       * event handling method.
       */
      NSDebugMLLog(@"NSRunLoop", @"Event callback found");
      [watcher->receiver receivedEvent: watcher->data
				  type: watcher->type
				 extra: watcher->data
			       forMode: mode];
    }

  GSNotifyASAP();

  completed = YES;
  return YES;
}

@end
