/** Behaviors for Objective-C, "for Protocols with implementations".
   Copyright (C) 1995, 1996 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: March 1995

   This file is part of the GNUstep Base Library.

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
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/ 

/* A Behavior can be seen as a "Protocol with an implementation" or a
   "Class without any instance variables".  A key feature of behaviors
   is that they give a degree of multiple inheritance.

   Behavior methods, when added to a class, override the class's
   superclass methods, but not the class's methods.

   xxx not necessarily on the "no instance vars".  The behavior just has 
   to have the same layout as the class.

   The following function is a sneaky hack way that provides Behaviors
   without adding any new syntax to the Objective C language.  Simply
   define a class with the methods you want in the behavior, then call
   this function with that class as the BEHAVIOR argument.

   This function should be called in CLASS's +initialize method.

   If you add several behaviors to a class, be aware that the order of 
   the additions is significant.

   McCallum talking to himself:
   "Yipes.  Be careful with [super ...] calls.
   BEHAVIOR methods running in CLASS will now have a different super class.
   No; wrong.  See objc-api.h; typedef struct objc_super."

   */

#include "config.h"
#include <stdio.h>
#include "GNUstepBase/preface.h"
#include "GNUstepBase/behavior.h"
#ifndef NeXT_Foundation_LIBRARY
#include <Foundation/NSException.h>
#include <Foundation/NSString.h>
#else
#include <Foundation/Foundation.h>
#endif

static BOOL class_is_kind_of(Class self, Class class);

static int behavior_debug = 0;

void
behavior_set_debug(int i)
{
  behavior_debug = i;
}

void
behavior_class_add_class (Class class, Class behavior)
{
  Class behavior_super_class = class_get_super_class(behavior);

  NSCAssert(CLS_ISCLASS(class), NSInvalidArgumentException);
  NSCAssert(CLS_ISCLASS(behavior), NSInvalidArgumentException);

#if NeXT_RUNTIME
  NSCAssert2(class->instance_size >= behavior->instance_size,
  @"Trying to add behavior (%s) with instance size larger than class (%s)",
  class_get_class_name(behavior), class_get_class_name(class));
#else
  /* If necessary, increase instance_size of CLASS. */
  if (class->instance_size < behavior->instance_size)
    {
      NSCAssert(!class->subclass_list,
		 @"The behavior-addition code wants to increase the\n"
		 @"instance size of a class, but it cannot because you\n"
		 @"have subclassed the class.  There are two solutions:\n"
		 @"(1) Don't subclass it; (2) Add placeholder instance\n"
		 @"variables to the class, so the behavior-addition code\n"
		 @"will not have to increase the instance size\n");
      class->instance_size = behavior->instance_size;
    }
#endif

  if (behavior_debug)
    {
      fprintf(stderr, "Adding behavior to class %s\n",
	      class->name);
    }

  /* Add instance methods */
  if (behavior_debug)
    {
      fprintf(stderr, "Adding instance methods from %s\n",
	      behavior->name);
    }
#if NeXT_RUNTIME
  {
     void *iterator = 0;
     struct objc_method_list *method_list;

     while ( (method_list = class_nextMethodList(behavior, &iterator)) )
       behavior_class_add_methods (class, method_list);
  }
#else
  behavior_class_add_methods (class, behavior->methods);
#endif

  /* Add class methods */
  if (behavior_debug)
    {
      fprintf(stderr, "Adding class methods from %s\n",
	      behavior->class_pointer->name);
    }
#if NeXT_RUNTIME
  {
     void *iterator = 0;
     struct objc_method_list *method_list;

     while ( (method_list = 
	      class_nextMethodList(behavior->class_pointer, &iterator)) )
       behavior_class_add_methods (class->class_pointer, method_list);
  }
#else
  behavior_class_add_methods (class->class_pointer, 
			      behavior->class_pointer->methods);
#endif

  /* Add behavior's superclass, if not already there. */
  {
    if (!class_is_kind_of(class, behavior_super_class))
      behavior_class_add_class (class, behavior_super_class);
  }

  return;
}

void
behavior_class_add_category (Class class, struct objc_category *category)
{
  behavior_class_add_methods (class, 
			      category->instance_methods);
  behavior_class_add_methods (class->class_pointer, 
			      category->class_methods);
  /* xxx Add the protocols (category->protocols) too. */
}

#if NeXT_RUNTIME

static struct objc_method *search_for_method_in_list (Class class, SEL op);

void 
behavior_class_add_methods (Class class, struct objc_method_list *methods)
{
  static SEL initialize_sel = 0;
  struct objc_method_list *mlist;

  if (!initialize_sel)
    initialize_sel = sel_register_name ("initialize");

  /* Add methods to class->dtable and class->methods */
  mlist = methods;
    {
      int counter;
      struct objc_method_list *new_list;

      counter = mlist->method_count ? mlist->method_count - 1 : 1;

      /* This is a little wasteful of memory, since not necessarily 
	 all methods will go in here. */
      new_list = (struct objc_method_list *)
	objc_malloc (sizeof(struct objc_method_list) +
		     sizeof(struct objc_method[counter+1]));
      new_list->method_count = 0;

      while (counter >= 0)
        {
          struct objc_method *method = &(mlist->method_list[counter]);

	  if (behavior_debug)
	    {
	      fprintf(stderr, "   processing method [%s] ... ", 
		sel_get_name(method->method_name));
	    }

	  if (!search_for_method_in_list(class,method->method_name)
	    && !sel_eq(method->method_name, initialize_sel))
	    {
	      /* As long as the method isn't defined in the CLASS,
		 put the BEHAVIOR method in there.  Thus, behavior
		 methods override the superclasses' methods. */
	      new_list->method_list[new_list->method_count] = *method;
	      (new_list->method_count)++;
	      if (behavior_debug)
		{
		  fprintf(stderr, "added.\n"); 
		}
	    }
	  else if (behavior_debug)
	    {
	      fprintf(stderr, "ignored.\n"); 
	    }
          counter -= 1;
        }
      if (new_list->method_count)
	{
	  class_add_method_list(class, new_list);
	}
      else
	{
	  OBJC_FREE(new_list);
	}
    }
}

/* Search for the named method's method structure.  Return a pointer
   to the method's method structure if found.  NULL otherwise. */
static struct objc_method *
search_for_method_in_list (Class class, SEL op)
{
  void *iterator = 0;
  struct objc_method_list *method_list;

  if (! sel_is_mapped (op))
    return NULL;

  /* If not found then we'll search the list.  */
  while ( (method_list = class_nextMethodList(class, &iterator)) )
    {
      int i;

      /* Search the method list.  */
      for (i = 0; i < method_list->method_count; ++i)
        {
          struct objc_method *method = &method_list->method_list[i];

          if (method->method_name)
            {
              if (sel_eq(method->method_name, op))
                return method;
            }
        }
    }

  return NULL;
}

#else
/* GNU runtime */

/*
 * The following two functions are implemented in the GNU objc runtime
 */
extern Method_t search_for_method_in_list(MethodList_t list, SEL op);
extern void class_add_method_list(Class, MethodList_t);

void
behavior_class_add_methods (Class class, 
			    struct objc_method_list *methods)
{
  static SEL initialize_sel = 0;
  struct objc_method_list *mlist;

  if (!initialize_sel)
    initialize_sel = sel_register_name ("initialize");

  /* Add methods to class->dtable and class->methods */
  for (mlist = methods; mlist; mlist = mlist->method_next)
    {
      int counter;
      struct objc_method_list *new_list;

      counter = mlist->method_count ? mlist->method_count - 1 : 1;

      /* This is a little wasteful of memory, since not necessarily 
	 all methods will go in here. */
      new_list = (struct objc_method_list *)
	objc_malloc (sizeof(struct objc_method_list) +
		     sizeof(struct objc_method[counter+1]));
      new_list->method_count = 0;
      new_list->method_next = NULL;

      while (counter >= 0)
        {
          struct objc_method	*method = &(mlist->method_list[counter]);
	  const char		*name = sel_get_name(method->method_name);

	  if (behavior_debug)
	    {
	      fprintf(stderr, "   processing method [%s] ... ", name);
	    }
	  if (!search_for_method_in_list(class->methods, method->method_name)
	      && !sel_eq(method->method_name, initialize_sel))
	    {
	      /* As long as the method isn't defined in the CLASS,
		 put the BEHAVIOR method in there.  Thus, behavior
		 methods override the superclasses' methods. */
	      new_list->method_list[new_list->method_count] = *method;
	      /*
	       * HACK ... the GNU runtime implementation of
	       * class_add_method_list() expects the method names to be
	       * C-strings rather than selectors ... so we must allow
	       * for that.
	       */
	      new_list->method_list[new_list->method_count].method_name
		= (SEL)name;
	      (new_list->method_count)++;
	      if (behavior_debug)
		{
		  fprintf(stderr, "added.\n"); 
		}
	    }
	  else if (behavior_debug)
	    {
	      fprintf(stderr, "ignored.\n"); 
	    }
          counter -= 1;
        }
      if (new_list->method_count)
	{
	  class_add_method_list(class, new_list);
	}
      else
	{
	  OBJC_FREE(new_list);
	}
    }
}

#endif /* NeXT runtime */

static BOOL class_is_kind_of(Class self, Class aClassObject)
{
  Class class;

  for (class = self; class!=Nil; class = class_get_super_class(class))
    if (class==aClassObject)
      return YES;
  return NO;
}
