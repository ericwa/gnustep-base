/* GNU Objective C Runtime Thread Implementation
   Copyright (C) 1996, 1997 Free Software Foundation, Inc.
   Contributed by Galen C. Hunt (gchunt@cs.rochester.edu)
   Modified for Mach threads by Bill Bumgarner <bbum@friday.com>
   Condition functions added by Mircea Oancea <mircea@first.elcom.pub.ro>

This file is part of GNU CC.

GNU CC is free software; you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation; either version 2, or (at your option) any later version.

GNU CC is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License
along with GNU CC; see the file COPYING.  If not, write to
the Free Software Foundation, 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.  */

/* As a special exception, if you link this library with files compiled with
   GCC to produce an executable, this does not cause the resulting executable
   to be covered by the GNU General Public License. This exception does not
   however invalidate any other reasons why the executable file might be
   covered by the GNU General Public License.  */

#include <mach/mach.h>
#include <mach/cthreads.h>
#include "gnustep/base/objc-gnu2next.h"
#include "gnustep/base/thr-mach.h"

/* Global exit status. */
int __objc_thread_exit_status = 0;

/* Flag which lets us know if we ever became multi threaded */
int __objc_is_multi_threaded = 0;

/* Number of threads alive  */
int __objc_runtime_threads_alive = 0;

/* Thread create/exit mutex */
struct objc_mutex* __objc_runtime_mutex = NULL; 

/* The hook function called when the runtime becomes multi threaded */
objc_thread_callback _objc_became_multi_threaded = NULL;

/*
  Use this to set the hook function that will be called when the 
  runtime initially becomes multi threaded.
  The hook function is only called once, meaning only when the 
  2nd thread is spawned, not for each and every thread.

  It returns the previous hook function or NULL if there is none.

  A program outside of the runtime could set this to some function so
  it can be informed; for example, the GNUstep Base Library sets it 
  so it can implement the NSBecomingMultiThreaded notification.
  */
objc_thread_callback objc_set_thread_callback(objc_thread_callback func)
{
  objc_thread_callback temp = _objc_became_multi_threaded;
  _objc_became_multi_threaded = func;
  return temp;
}

/*
  Private functions

  These functions are utilized by the frontend, but they are not
  considered part of the public interface.
  */

/*
  First function called in a thread, starts everything else.

  This function is passed to the backend by objc_thread_detach
  as the starting function for a new thread.
 */
struct __objc_thread_start_state
{
  SEL selector;
  id object;
  id argument;
};

static volatile void
__objc_thread_detach_function(struct __objc_thread_start_state *istate)
{
  /* Valid state? */
  if (istate) {
    id (*imp)(id,SEL,id);
    SEL selector = istate->selector;
    id object   = istate->object;
    id argument = istate->argument;

    /* Don't need anymore so free it */
    objc_free(istate);

    /* Clear out the thread local storage */
    objc_thread_set_data(NULL);

    /* Check to see if we just became multi threaded */
    if (!__objc_is_multi_threaded)
      {
	__objc_is_multi_threaded = 1;

	/* Call the hook function */
	if (_objc_became_multi_threaded != NULL)
	  (*_objc_became_multi_threaded)();
      }

    /* Call the method */
    if ((imp = (id(*)(id, SEL, id))objc_msg_lookup(object, selector)))
	(*imp)(object, selector, argument);
    else
      objc_error(object, OBJC_ERR_UNIMPLEMENTED,
		 "objc_thread_detach called with bad selector.\n");
  }
  else
    objc_error(nil, OBJC_ERR_BAD_STATE,
	       "objc_thread_detach called with NULL state.\n");

  /* Exit the thread */
  objc_thread_exit();
}

/*
  Frontend functions

  These functions constitute the public interface to the Objective-C thread
  and mutex functionality.
  */

/* Frontend thread functions */

/*
  Detach a new thread of execution and return its id.  Returns NULL if fails.
  Thread is started by sending message with selector to object.  Message
  takes a single argument.
  */
objc_thread_t
objc_thread_detach(SEL selector, id object, id argument)
{
  struct __objc_thread_start_state *istate;
  objc_thread_t        thread_id = NULL;

  /* Allocate the state structure */
  if (!(istate = (struct __objc_thread_start_state *)
	objc_malloc(sizeof(*istate))))
    return NULL;

  /* Initialize the state structure */
  istate->selector = selector;
  istate->object = object;
  istate->argument = argument;

  /* lock access */
  objc_mutex_lock(__objc_runtime_mutex);

  /* Call the backend to spawn the thread */
  if ((thread_id = __objc_thread_detach((void *)__objc_thread_detach_function,
					istate)) == NULL)
    {
      /* failed! */
      objc_mutex_unlock(__objc_runtime_mutex);
      objc_free(istate);
      return NULL;
    }

  /* Increment our thread counter */
  __objc_runtime_threads_alive++;
  objc_mutex_unlock(__objc_runtime_mutex);

  return thread_id;
}

/*
  Obtain the maximum thread priority that can set for t.  Under the
  mach threading model, it is possible for the developer to adjust the
  maximum priority downward only-- cannot be raised without superuser
  privileges.  Once lowered, it cannot be raised.
  */
static int __mach_get_max_thread_priority(cthread_t t, int *base)
{
  thread_t threadP;
  kern_return_t error;
  struct thread_sched_info info;
  unsigned int info_count=THREAD_SCHED_INFO_COUNT;
    
  if (t == NULL)
    return -1;

  threadP  = cthread_thread(t); 	/* get thread underlying */

  error=thread_info(threadP, THREAD_SCHED_INFO, 
		    (thread_info_t)&info, &info_count);

  if (error != KERN_SUCCESS)
    return -1;

  if (base != NULL)
    *base = info.base_priority;

  return info.max_priority;
}
	
/* Backend initialization functions */

/* Initialize the threads subsystem. */
int
__objc_init_thread_system(void)
{
  return 0;
}

/* Close the threads subsystem. */
int
__objc_close_thread_system(void)
{
  return 0;
}

/* Backend thread functions */

/* Create a new thread of execution. */
objc_thread_t
__objc_thread_detach(void (*func)(void *arg), void *arg)
{
  objc_thread_t thread_id;
  cthread_t new_thread_handle;

  /* create thread */
  new_thread_handle = cthread_fork((cthread_fn_t)func, arg);

  if(new_thread_handle)
    {
      /* this is not terribly portable */
      thread_id = *(objc_thread_t *)&new_thread_handle; 
      cthread_detach(new_thread_handle);
    }
  else
    thread_id = NULL;
  
  return thread_id;
}

/* Set the current thread's priority. */
int
objc_thread_set_priority(int priority)
{
  objc_thread_t *t = objc_thread_id();
  cthread_t cT = (cthread_t) t; 
  int maxPriority = __mach_get_max_thread_priority(cT, NULL);
  int sys_priority = 0;

  if (maxPriority == -1)
    return -1;

  switch (priority)
    {
    case OBJC_THREAD_INTERACTIVE_PRIORITY:
      sys_priority = maxPriority;
      break;
    case OBJC_THREAD_BACKGROUND_PRIORITY:
      sys_priority = (maxPriority * 2) / 3;
      break;
    case OBJC_THREAD_LOW_PRIORITY:
      sys_priority = maxPriority / 3;
      break;
    default:
      return -1;
    }

  if (sys_priority == 0)
    return -1;

  /* Change the priority */
  if (cthread_priority(cT, sys_priority, 0) == KERN_SUCCESS)
    return 0;
  else
    return -1;
}

/* Return the current thread's priority. */
int
objc_thread_get_priority(void)
{
  objc_thread_t *t = objc_thread_id();
  cthread_t cT = (cthread_t) t; /* see objc_thread_id() */
  int basePriority;
  int maxPriority;
  int sys_priority = 0;

  int interactiveT, backgroundT, lowT; /* thresholds */

  maxPriority = __mach_get_max_thread_priority(cT, &basePriority);

  if(maxPriority == -1)
    return -1;

  if (basePriority > ( (maxPriority * 2) / 3))
    return OBJC_THREAD_INTERACTIVE_PRIORITY;

  if (basePriority > ( maxPriority / 3))
    return OBJC_THREAD_BACKGROUND_PRIORITY;

  return OBJC_THREAD_LOW_PRIORITY;
}

/* Yield our process time to another thread. */
void
objc_thread_yield(void)
{
  cthread_yield();
}

/* Terminate the current thread. */
int
objc_thread_exit(void)
{
  /* Decrement our counter of the number of threads alive */
  objc_mutex_lock(__objc_runtime_mutex);
  __objc_runtime_threads_alive--;
  objc_mutex_unlock(__objc_runtime_mutex);

  /* exit the thread */
  cthread_exit(&__objc_thread_exit_status);

  /* Failed if we reached here */
  return -1;
}

/* Returns an integer value which uniquely describes a thread. */
objc_thread_t
objc_thread_id(void)
{
  cthread_t self = cthread_self();

  return *(objc_thread_t *)&self;
}

/* Sets the thread's local storage pointer. */
int
objc_thread_set_data(void *value)
{
  cthread_set_data(cthread_self(), (any_t) value);
  return 0;
}

/* Returns the thread's local storage pointer. */
void *
objc_thread_get_data(void)
{
  return (void *) cthread_data(cthread_self());
}

/* Backend mutex functions */

/* Allocate a mutex. */
objc_mutex_t
objc_mutex_allocate(objc_mutex_t mutex)
{
  int err = 0;
  objc_mutex_t mutex;

  /* Allocate the mutex structure */
  if (!(mutex = (objc_mutex_t)objc_malloc(sizeof(struct objc_mutex))))
    return NULL;

  mutex->backend = objc_malloc(sizeof(struct mutex));

  err = mutex_init((mutex_t)(mutex->backend));

  if (err != 0)
    {
      objc_free(mutex->backend);
      objc_free(mutex);
      return NULL;
    }

  /* Initialize mutex */
  mutex->owner = NULL;
  mutex->depth = 0;
  return mutex;
}

/* Deallocate a mutex. */
int
objc_mutex_deallocate(objc_mutex_t mutex)
{
  int depth;

  /* Valid mutex? */
  if (!mutex)
    return -1;

  /* Acquire lock on mutex */
  depth = objc_mutex_lock(mutex);

  mutex_clear((mutex_t)(mutex->backend));

  objc_free(mutex->backend);
  mutex->backend = NULL;

  /* Free the mutex structure */
  objc_free(mutex);

  /* Return last depth */
  return depth;
}

/* Grab a lock on a mutex. */
int
objc_mutex_lock(objc_mutex_t mutex)
{
  objc_thread_t thread_id;

  /* Valid mutex? */
  if (!mutex)
    return -1;

  /* If we already own the lock then increment depth */
  thread_id = objc_thread_id();
  if (mutex->owner == thread_id)
    return ++mutex->depth;

  mutex_lock((mutex_t)(mutex->backend));

  /* Successfully locked the thread */
  mutex->owner = thread_id;
  return mutex->depth = 1;
}

/* Try to grab a lock on a mutex. */
int
objc_mutex_trylock(objc_mutex_t mutex)
{
  objc_thread_t thread_id;
  int status;

  /* Valid mutex? */
  if (!mutex)
    return -1;

  /* If we already own the lock then increment depth */ 
  thread_id = objc_thread_id();
  if (mutex->owner == thread_id)
    return ++mutex->depth;
    
  if (mutex_try_lock((mutex_t)(mutex->backend)) == 0)
    status = -1;
  else
    status = 0;

  /* Failed? */
  if (status)
    return status;

  /* Successfully locked the thread */
  mutex->owner = thread_id;
  return mutex->depth = 1;
}

/* Unlock the mutex */
int
objc_mutex_unlock(objc_mutex_t mutex)
{
  objc_thread_t thread_id;

  /* Valid mutex? */
  if (!mutex)
    return -1;

  /* If another thread owns the lock then abort */
  thread_id = objc_thread_id();
  if (mutex->owner != thread_id)
    return -1;

  /* Decrement depth and return */
  if (mutex->depth > 1)
    return --mutex->depth;

  /* Depth down to zero so we are no longer the owner */
  mutex->depth = 0;
  mutex->owner = NULL;

  mutex_unlock((mutex_t)(mutex->backend));

  return 0;
}

/* Backend condition mutex functions */

/* Allocate a condition. */
objc_condition_t 
objc_condition_allocate(void)
{
  objc_condition_t condition;
    
  /* Allocate the condition mutex structure */
  if (!(condition = 
	(objc_condition_t)objc_malloc(sizeof(struct objc_condition))))
    return NULL;

  condition->backend = objc_malloc(sizeof(struct condition));
  condition_init((condition_t)(condition->backend));

  return condition;
}

/* Deallocate a condition. */
int
objc_condition_deallocate(objc_condition_t condition)
{
  /* Broadcast the condition */
  if (objc_condition_broadcast(condition))
    return -1;

  condition_clear((condition_t)(condition->backend));
  objc_free(condition->backend);
  condition->backend = NULL;

  /* Free the condition mutex structure */
  objc_free(condition);
  return 0;
}

/* Wait on the condition */
int
objc_condition_wait(objc_condition_t condition, objc_mutex_t mutex)
{
  objc_thread_t thread_id;

  /* Valid arguments? */
  if (!mutex || !condition)
    return -1;

  /* Make sure we are owner of mutex */
  thread_id = objc_thread_id();
  if (mutex->owner != thread_id)
    return -1;

  /* Cannot be locked more than once */
  if (mutex->depth > 1)
    return -1;

  /* Virtually unlock the mutex */
  mutex->depth = 0;
  mutex->owner = (objc_thread_t)NULL;

  condition_wait((condition_t)(condition->backend),
		 (mutex_t)(mutex->backend));

  /* Make ourselves owner of the mutex */
  mutex->owner = thread_id;
  mutex->depth = 1;

  return 0;
}

/* Wake up all threads waiting on this condition. */
int
objc_condition_broadcast(objc_condition_t condition)
{
  /* Valid condition mutex? */
  if (!condition)
    return -1;

  condition_broadcast((condition_t)(condition->backend));
  return 0;
}

/* Wake up one thread waiting on this condition. */
int
objc_condition_signal(objc_condition_t condition)
{
  /* Valid condition mutex? */
  if (!condition)
    return -1;

  condition_signal((condition_t)(condition->backend));
  return 0;
}

/* Make the objc thread system aware that a thread which is managed
   (started, stopped) by external code could access objc facilities
   from now on.  This is used when you are interfacing with some
   external non-objc-based environment/system - you must call
   objc_thread_add() before an alien thread makes any calls to
   Objective-C.  Do not cause the _objc_became_multi_threaded hook to
   be executed. */
void 
objc_thread_add(void)
{
  objc_mutex_lock(__objc_runtime_mutex);
  __objc_is_multi_threaded = 1;
  __objc_runtime_threads_alive++;
  objc_mutex_unlock(__objc_runtime_mutex);  
}

/* Make the objc thread system aware that a thread managed (started,
   stopped) by some external code will no longer access objc and thus
   can be forgotten by the objc thread system.  Call
   objc_thread_remove() when your alien thread is done with making
   calls to Objective-C. */
void
objc_thread_remove(void)
{
  objc_mutex_lock(__objc_runtime_mutex);
  __objc_runtime_threads_alive--;
  objc_mutex_unlock(__objc_runtime_mutex);  
}

/* End of File */
