/* Control of executable units within a shared virtual memory space
   Copyright (C) 1996 Free Software Foundation, Inc.

   Original Author:  Scott Christley <scottc@net-community.com>
   Rewritten by: Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: 1996
   Rewritten by: Richard Frith-Macdonald <richard@brainstorm.co.uk>
   to add optimisations features for faster thread access.
   
   This file is part of the GNUstep Objective-C Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
*/ 

#include <config.h>
#include <base/preface.h>
#include <unistd.h>
#include <Foundation/NSThread.h>
#include <Foundation/NSLock.h>
#include <Foundation/NSString.h>
#include <Foundation/NSNotificationQueue.h>

/*
 *	A class to defer the use of the real thread method until we have
 *	an autlorelease pool so that target and arg can be safely released
 *	once they are no longer needed.
 */
@interface GSThreadLauncher : NSObject
{
  id	target;
  id	arg;
  SEL	sel;
}
+ (GSThreadLauncher*) newWithTarget: (id)t selector: (SEL)s arg: (id)a;
- (void) sendThreadMethod;
@end

@implementation	GSThreadLauncher
+ (GSThreadLauncher*) newWithTarget: (id)t selector: (SEL)s arg: (id)a
{
  GSThreadLauncher	*l;

  l = (GSThreadLauncher*)NSAllocateObject(self, 0, NSDefaultMallocZone());
  l->target = RETAIN(t);
  l->arg = RETAIN(a);
  l->sel = s;
  return l;
}

- (void) dealloc
{
  RELEASE(target);
  RELEASE(arg);
  NSDeallocateObject(self);
}

- (void) sendThreadMethod
{
  /*
   * We are running in the new thread - so we store ourself in the thread
   * dictionary and release ourself - thus, when the thread exits, we will
   * be deallocated cleanly.
   */
  [[[NSThread currentThread] threadDictionary] setObject: self
						  forKey: @"GSThreadLauncher"];
  RELEASE(self);
  [target performSelector: sel withObject: arg];
  [NSThread exit];
}
@end

// Class variables

/* Flag indicating whether the objc runtime ever went multi-threaded. */
static BOOL entered_multi_threaded_state;

inline NSThread*
GSCurrentThread()
{
  id t = (id) objc_thread_get_data ();

  /* If an NSThread object for this thread has already been created
     and stashed away, return it.  This depends on the objc runtime
     initializing objc_thread_get_data() to 0 for newly-created
     threads. */
  if (t)
    return t;

  /* We haven't yet created an NSThread object for this thread; create
     it.  (Doing this here instead of in +detachNewThread.. not only
     avoids the race condition, it also nicely provides an NSThread on
     request for the single thread that exists at application
     start-up, and for thread's created by calling
     objc_thread_detach() directly.) */
  t = [[NSThread alloc] init];
  return t;
}

NSMutableDictionary*
GSCurrentThreadDictionary()
{
  NSThread		*thread = GSCurrentThread();
  NSMutableDictionary	*dict = thread->_thread_dictionary;

  if (dict == nil)
    dict = [thread threadDictionary];
  return dict; 
}

void gnustep_base_thread_callback()
{
  /*
   * Post a notification if this is the first new thread to be created.
   * Won't work properly if threads are not all created by this class,
   * but it's better than nothing.
   */
  if (!entered_multi_threaded_state)
    {
      NSNotification	*n;

      entered_multi_threaded_state = YES;
      n = [NSNotification alloc];
      n = [n initWithName: NSWillBecomeMultiThreadedNotification
		   object: nil
		 userInfo: nil];
      [[NSNotificationCenter defaultCenter] postNotification: n];
      RELEASE(n);
    }
}


@implementation NSThread

// Class initialization
+ (void) initialize
{
  if (self == [NSThread class])
    {
      entered_multi_threaded_state = NO;
      /*
       * The objc runtime calls this callback AFTER creating a new thread -
       * which is not correct for us, but does at least mean that we can tell
       * if we have become multi-threaded due to a call to the runtime directly
       * rather than via the NSThread class.
       */
      objc_set_thread_callback(gnustep_base_thread_callback);
    }
}


// Initialization

- (void) dealloc
{
  TEST_RELEASE(_thread_dictionary);
  [super dealloc];
}

- (id) init
{
  /* Make it easy and fast to get this NSThread object from the thread. */
  objc_thread_set_data (self);

  /* initialize our ivars. */
  _thread_dictionary = nil;	// Initialize this later only when needed
  _exception_handler = NULL;
  init_autorelease_thread_vars(&_autorelease_vars);

  return self;
}


// Creating an NSThread

+ (NSThread*) currentThread
{
  return GSCurrentThread();
}

+ (void) detachNewThreadSelector: (SEL)aSelector
		        toTarget: (id)aTarget
                      withObject: (id)anArgument
{
  GSThreadLauncher	*launcher;
  /*
   * Make sure the notification is posted BEFORE the new thread starts.
   */
  gnustep_base_thread_callback();
  /*
   * Have the runtime detach the thread
   */
  launcher = [GSThreadLauncher newWithTarget: aTarget
				    selector: aSelector
					 arg: anArgument];

  if (objc_thread_detach(@selector(sendThreadMethod), launcher, nil) == NULL)
    {
      /* This should probably be an exception */
      NSLog(@"Unable to detach thread (unknown error)");
    }

  /* NOTE we can't create the new NSThread object for this thread here
     because there would be a race condition.  The newly created
     thread might ask for its NSThread object before we got to create
     it. */
}


// Querying a thread

+ (BOOL) isMultiThreaded
{
  return entered_multi_threaded_state;
}

/* Thread dictionary
   NB. This cannot be autoreleased, since we cannot be sure that the
   autorelease pool for the thread will continue to exist for the entire
   life of the thread!
 */
- (NSMutableDictionary*) threadDictionary
{
  if (!_thread_dictionary)
    _thread_dictionary = [NSMutableDictionary new];
  return _thread_dictionary;
}

// Delaying a thread
+ (void) sleepUntilDate: (NSDate*)date
{
  NSTimeInterval delay;

  // delay is always the number of seconds we still need to wait
  delay = [date timeIntervalSinceNow];

  // Avoid integer overflow by breaking up long sleeps
  // We assume usleep can accept a value at least 31 bits in length
  while (delay > 30.0*60.0)
    {
      // sleep 30 minutes
#ifdef	HAVE_USLEEP
      usleep (30*60*1000000);
#else
#if defined(__WIN32__)
      Sleep (30*60*1000);
#else
      sleep (30*60);
#endif
#endif
      delay = [date timeIntervalSinceNow];
    }

  // usleep may return early because of signals
  while (delay > 0)
    {
#ifdef	HAVE_USLEEP
      usleep ((int)(delay*1000000));
#else
#if defined(__WIN32__)
      Sleep (delay*1000);
#else
      sleep ((int)delay);
#endif
#endif
      delay = [date timeIntervalSinceNow];
    }
}

// Terminating a thread
// What happens if the thread doesn't call +exit?
+ (void) exit
{
  NSThread		*t;
  NSNotification	*n;

  // the current NSThread
  t = GSCurrentThread();

  // Post the notification
  n = [NSNotification alloc];
  n = [n initWithName: NSThreadWillExitNotification
	       object: t
	     userInfo: nil];
  [[NSNotificationCenter defaultCenter] postNotification: n];
  RELEASE(n);

  /*
   * Release anything in our autorelease pools
   */
  [NSAutoreleasePool _endThread];

  RELEASE(t);

  // xxx Clean up any outstanding NSAutoreleasePools here.

  // Tell the runtime to exit the thread
  objc_thread_exit ();
}

@end
