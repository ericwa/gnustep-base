/** Implementation of ObjC runtime additions for GNUStep
   Copyright (C) 1995-2002 Free Software Foundation, Inc.

   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date: Aug 1995
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: Nov 2002
   Written by:  Manuel Guesdon <mguesdon@orange-concept.com>
   Date: Nov 2002

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

   <title>GSObjCRuntime function and macro reference</title>
   $Date$ $Revision$
   */

#include "config.h"
#include "GNUstepBase/preface.h"
#ifndef NeXT_Foundation_LIBRARY
#include <Foundation/NSArray.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSData.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSEnumerator.h>
#include <Foundation/NSException.h>
#include <Foundation/NSLock.h>
#include <Foundation/NSMethodSignature.h>
#include <Foundation/NSObjCRuntime.h>
#include <Foundation/NSSet.h>
#include <Foundation/NSString.h>
#include <Foundation/NSValue.h>
#else
#include <Foundation/Foundation.h>
#endif
#include "GNUstepBase/GSObjCRuntime.h"
#include "GNUstepBase/GNUstep.h"
#include "GNUstepBase/GSCategories.h"

#include <objc/Protocol.h>

#include <string.h>

@class	NSNull;

#ifdef NeXT_Foundation_LIBRARY
@interface NSObject (MissingFromMacOSX)
+ (IMP) methodForSelector: (SEL)aSelector;
@end
#endif

#define BDBGPrintf(format, args...) \
  do { if (behavior_debug) { fprintf(stderr, (format) , ## args); } } while (0)

static objc_mutex_t local_lock = NULL;

/* This class it intended soley for thread safe / +load safe
   initialization of the local lock.
   It's a root class so it won't trigger the initialization
   of any other class.  */
@interface _GSObjCRuntimeInitializer /* Root Class */
{
  Class isa;
}
+ (Class)class;
@end
@implementation _GSObjCRuntimeInitializer
+ (void)initialize
{
  if (local_lock == NULL)
    {
      local_lock = objc_mutex_allocate();
    }
}
+ (Class)class
{
  return self;
}
@end

void
GSAllocateMutexAt(objc_mutex_t *request)
{
  if (request == NULL)
    {
      /* This could be called very early in process
	 initialization so many things may not have
	 been setup correctly yet.  */
      fprintf(stderr,
	      "Error: GSAllocateMutexAt() called with NULL pointer.\n");
      abort();
    }

  if (local_lock == NULL)
    {
      /* Initialize in a thread safe way.  */
      [_GSObjCRuntimeInitializer class];
    }

  objc_mutex_lock(local_lock);
  if (*request == NULL)
    {
      *request = objc_mutex_allocate();
    }
  objc_mutex_unlock(local_lock);
}

/**  Deprecated ... use GSObjCFindVariable() */
BOOL
GSFindInstanceVariable(id obj, const char *name,
		       const char **type, unsigned int *size, int *offset)
{
  return GSObjCFindVariable(obj, name, type, size, offset);
}

/**
 * This function is used to locate information about the instance
 * variable of obj called name.  It returns YES if the variable
 * was found, NO otherwise.  If it returns YES, then the values
 * pointed to by type, size, and offset will be set (except where
 * they are null pointers).
 */
BOOL
GSObjCFindVariable(id obj, const char *name,
		   const char **type, unsigned int *size, int *offset)
{
  Class			class;
  struct objc_ivar_list	*ivars;
  struct objc_ivar	*ivar = 0;

  if (obj == nil) return NO;
  class = GSObjCClass(obj);
  while (class != nil && ivar == 0)
    {
      ivars = class->ivars;
      class = class->super_class;
      if (ivars != 0)
	{
	  int	i;

	  for (i = 0; i < ivars->ivar_count; i++)
	    {
	      if (strcmp(ivars->ivar_list[i].ivar_name, name) == 0)
		{
		  ivar = &ivars->ivar_list[i];
		  break;
		}
	    }
	}
    }
  if (ivar == 0)
    {
      return NO;
    }

  if (type)
    *type = ivar->ivar_type;
  if (size)
    *size = objc_sizeof_type(ivar->ivar_type);
  if (offset)
    *offset = ivar->ivar_offset;
  return YES;
}

/**
 * This method returns an array listing the names of all the
 * instance methods available to obj, whether they
 * belong to the class of obj or one of its superclasses.<br />
 * If obj is a class, this returns the class methods.<br />
 * Returns nil if obj is nil.
 */
NSArray *
GSObjCMethodNames(id obj)
{
  NSMutableSet	*set;
  NSArray	*array;
  Class		 class;
  GSMethodList	 methods;

  if (obj == nil)
    {
      return nil;
    }
  /*
   * Add names to a set so methods declared in superclasses
   * and then overridden do not appear more than once.
   */
  set = [[NSMutableSet alloc] initWithCapacity: 32];

  class = GSObjCClass(obj);

  while (class != nil)
    {
      void *iterator = 0;

      while ((methods = class_nextMethodList(class, &iterator)))
	{
	  int i;

	  for (i = 0; i < methods->method_count; i++)
	    {
	      GSMethod method = &methods->method_list[i];

	      if (method->method_name != 0)
		{
		  NSString	*name;
                  const char *cName;

                  cName = GSNameFromSelector(method->method_name);
                  name = [[NSString alloc] initWithUTF8String: cName];
		  [set addObject: name];
		  RELEASE(name);
		}
	    }
	}
      class = class->super_class;
    }

  array = [set allObjects];
  RELEASE(set);
  return array;
}

/**
 * This method returns an array listing the names of all the
 * instance variables present in the instance obj, whether they
 * belong to the class of obj or one of its superclasses.<br />
 * Returns nil if obj is nil.
 */
NSArray *
GSObjCVariableNames(id obj)
{
  NSMutableArray	*array;
  Class			class;
  struct objc_ivar_list	*ivars;

  if (obj == nil)
    {
      return nil;
    }
  array = [NSMutableArray arrayWithCapacity: 16];
  class = GSObjCClass(obj);
  while (class != nil)
    {
      ivars = class->ivars;
      if (ivars != 0)
	{
	  int		i;

	  for (i = 0; i < ivars->ivar_count; i++)
	    {
	      NSString	*name;

	      name = [[NSString alloc] initWithUTF8String:
		ivars->ivar_list[i].ivar_name];
	      [array addObject: name];
	      RELEASE(name);
	    }
	}
      class = class->super_class;
    }
  return array;
}

/**  Deprecated ... use GSObjCGetVariable() */
void
GSGetVariable(id obj, int offset, unsigned int size, void *data)
{
  GSObjCGetVariable(obj, offset, size, data);
}
/**
 * Gets the value from an instance variable in obj<br />
 * This function performs no checking ... you should use it only where
 * you are providing information from a call to GSFindVariable()
 * and you know that the data area provided is the correct size.
 */
void
GSObjCGetVariable(id obj, int offset, unsigned int size, void *data)
{
  memcpy(data, ((void*)obj) + offset, size);
}

/**  Deprecated ... use GSObjCSetVariable() */
void
GSSetVariable(id obj, int offset, unsigned int size, const void *data)
{
  GSObjCSetVariable(obj, offset, size, data);
}
/**
 * Sets the value in an instance variable in obj<br />
 * This function performs no checking ... you should use it only where
 * you are providing information from a call to GSObjCFindVariable()
 * and you know that the data area provided is the correct size.
 */
void
GSObjCSetVariable(id obj, int offset, unsigned int size, const void *data)
{
  memcpy(((void*)obj) + offset, data, size);
}

GS_EXPORT unsigned int
GSClassList(Class *buffer, unsigned int max, BOOL clearCache)
{
#ifdef NeXT_RUNTIME
  int num;

  if (buffer != NULL)
    {
      memset(buffer, 0, sizeof(Class) * (max + 1));
    }

  num = objc_getClassList(buffer, max);
  num = (num < 0) ? 0 : num;

#else
  static Class *cache = 0;
  static unsigned cacheClassCount = 0;
  static volatile objc_mutex_t cache_lock = NULL;
  unsigned int num;

  if (cache_lock == NULL)
    {
      GSAllocateMutexAt((void*)&cache_lock);
    }

  objc_mutex_lock(cache_lock);

  if (clearCache)
    {
      if (cache)
	{
	  objc_free(cache);
	  cache = NULL;
	}
      cacheClassCount = 0;
    }

  if (cache == NULL)
    {
      void *iterator = 0;
      Class cls;
      unsigned int i;

      cacheClassCount = 0;
      while ((cls = objc_next_class(&iterator)))
	{
	  cacheClassCount++;
	}
      cache = objc_malloc(sizeof(Class) * (cacheClassCount + 1));
      /* Be extra careful as another thread may be loading classes.  */
      for (i = 0, iterator = 0, cls = objc_next_class(&iterator);
	   i < cacheClassCount && cls != NULL;
	   i++, cls = objc_next_class(&iterator))
	{
	  cache[i] = cls;
	}
      cache[i] = NULL;
    }

  if (buffer == NULL)
    {
      num = cacheClassCount;
    }
  else
    {
      size_t       cpySize;
      unsigned int cpyCnt;

      cpyCnt = MIN(max, cacheClassCount);
      cpySize = sizeof(Class) * cpyCnt;
      memcpy(buffer, cache, cpySize);
      buffer[cpyCnt] = NULL;

      num = (max > cacheClassCount) ? 0 : (cacheClassCount - max);
    }

  objc_mutex_unlock(cache_lock);

#endif

  return num;
}

/** references:
http://www.macdevcenter.com/pub/a/mac/2002/05/31/runtime_parttwo.html?page=1
http://developer.apple.com/documentation/Cocoa/Conceptual/ObjectiveC/9objc_runtime_reference/chapter_5_section_1.html
http://developer.apple.com/documentation/Cocoa/Conceptual/ObjectiveC/9objc_runtime_reference/chapter_5_section_21.html
ObjcRuntimeUtilities.m by Nicola Pero
**/

/**
 * <p>Create a Class structure for use by the ObjectiveC runtime and return
 * an NSValue object pointing to it.  The class will not be added to the
 * runtime (you must do that later using the GSObjCAddClasses() function).
 * </p>
 * <p>The iVars dictionary lists the instance variable names and their types.
 * </p>
 */
NSValue *
GSObjCMakeClass(NSString *name, NSString *superName, NSDictionary *iVars)
{
  Class		newClass;
  Class		classSuperClass;
  const char	*classNameCString;
  const char	*superClassNameCString;
  Class		newMetaClass;
  Class		rootClass;
  unsigned int	iVarSize;
  char		*tmp;

  NSCAssert(name, @"no name");
  NSCAssert(superName, @"no superName");

  classSuperClass = NSClassFromString(superName);

  NSCAssert1(classSuperClass, @"No class named %@",superName);
  NSCAssert1(!NSClassFromString(name), @"A class %@ already exists", name);

  classNameCString = [name cString];
  tmp = objc_malloc(strlen(classNameCString) + 1);
  strcpy(tmp, classNameCString);
  classNameCString = tmp;

  superClassNameCString = [superName cString];
  tmp = objc_malloc(strlen(superClassNameCString) + 1);
  strcpy(tmp, superClassNameCString);
  superClassNameCString = tmp;

  rootClass = classSuperClass;
  while (rootClass->super_class != 0)
    {
      rootClass = rootClass->super_class;
    }

  /*
   * Create new class and meta class structure storage
   *
   * From Nicola: NB: There is a trick here.
   * The runtime system will look up the name in the following string,
   * and replace it with a pointer to the actual superclass structure.
   * This also means the type of pointer will change, that's why we
   * need to cast it.
   */
  newMetaClass = objc_malloc(sizeof(struct objc_class));
  memset(newMetaClass, 0, sizeof(struct objc_class));
  newMetaClass->class_pointer = rootClass->class_pointer; // Points to root
  newMetaClass->super_class = (Class)superClassNameCString;
  newMetaClass->name = classNameCString;
  newMetaClass->version = 0;
  newMetaClass->info = _CLS_META; // this is a Meta Class


  newClass = objc_malloc(sizeof(struct objc_class));
  memset(newClass, 0, sizeof(struct objc_class));
  newClass->class_pointer = newMetaClass; // Points to the class's meta class.
  newClass->super_class = (Class)superClassNameCString;
  newClass->name = classNameCString;
  newClass->version = 0;
  newClass->info = _CLS_CLASS; // this is a Class

  // work on instances variables
  iVarSize = classSuperClass->instance_size; // super class ivar size
  if ([iVars count] > 0)
    {
      unsigned int	iVarsStructsSize;
      struct objc_ivar	*ivar = NULL;
      unsigned int	iVarsCount = [iVars count];
      NSEnumerator	*enumerator = [iVars keyEnumerator];
      NSString		*key;

      // ivars list is 1 objc_ivar_list followed by (iVarsCount-1) ivar_list
      iVarsStructsSize = sizeof(struct objc_ivar_list)
	+ (iVarsCount-1)*sizeof(struct objc_ivar);

      // Allocate for all ivars
      newClass->ivars = (struct objc_ivar_list*)objc_malloc(iVarsStructsSize);
      memset(newClass->ivars, 0, iVarsStructsSize);

      // Set ivars count
      newClass->ivars->ivar_count = iVarsCount;

      // initialize each ivar
      ivar = newClass->ivars->ivar_list; // 1st one
      while ((key = [enumerator nextObject]) != nil)
        {
          const	char	*iVarName = [key cString];
          const char	*iVarType = [[iVars objectForKey: key] cString];

          tmp = objc_malloc(strlen(iVarName) + 1);
	  strcpy(tmp, iVarName);
          ivar->ivar_name = tmp;
          tmp =  objc_malloc(strlen(iVarType) + 1);
	  strcpy(tmp, iVarType);
          ivar->ivar_type = tmp;

          // align the ivar (i.e. put it on the first aligned address
          iVarSize = objc_aligned_size(ivar->ivar_type);
          ivar->ivar_offset = iVarSize;
          iVarSize += objc_sizeof_type(ivar->ivar_type); // add the ivar size
	  ivar = ivar + 1;
        }
    }

  /*
   * Size in bytes of the class.  The sum of the class definition
   * and all super class definitions.
   */
  newClass->instance_size = iVarSize;

  // Meta Class instance size is superclass instance size.
  newMetaClass->instance_size = classSuperClass->class_pointer->instance_size;

  return [NSValue valueWithPointer: newClass];
}

/**
 * The classes argument is an array of NSValue objects containing pointers
 * to classes previously created by the GSObjCMakeClass() function.
 */
#ifdef NeXT_RUNTIME
void
GSObjCAddClasses(NSArray *classes)
{
  unsigned int	numClasses = [classes count];
  unsigned int	i;
  for (i = 0; i < numClasses; i++)
    {
      objc_addClass((Class)[[classes objectAtIndex: i] pointerValue]);
    }
}
#else
/*
 *	NOTE - OBJC_VERSION needs to be defined to be the version of the
 *	Objective-C runtime you are using.  You can find this in the file
 *	'init.c' in the GNU objective-C runtime source.
 */
#define	OBJC_VERSION	8

void
GSObjCAddClasses(NSArray *classes)
{
  void	__objc_exec_class (void* module);
  void	__objc_resolve_class_links ();
  Module_t	module;
  Symtab_t	symtab;
  unsigned int	numClasses = [classes count];
  unsigned int	i;
  Class		c;

  NSCAssert(numClasses > 0, @"No classes (array is NULL)");

  c = (Class)[[classes objectAtIndex: 0] pointerValue];

  // Prepare a fake module containing only the new classes
  module = objc_calloc (1, sizeof (Module));
  module->version = OBJC_VERSION;
  module->size = sizeof (Module);
  module->name = objc_malloc (strlen(c->name) + 15);
  strcpy ((char*)module->name, "GNUstep-Proxy-");
  strcat ((char*)module->name, c->name);
  module->symtab = objc_malloc(sizeof(Symtab) + numClasses * sizeof(void *));

  symtab = module->symtab;
  symtab->sel_ref_cnt = 0;
  symtab->refs = 0;
  symtab->cls_def_cnt = numClasses; // We are defining numClasses classes.
  symtab->cat_def_cnt = 0; // But no categories

  for (i = 0; i < numClasses; i++)
    {
      symtab->defs[i] = (Class)[[classes objectAtIndex: i] pointerValue];
    }
  symtab->defs[numClasses] = NULL; //null terminated list

  // Insert our new class into the runtime.
  __objc_exec_class (module);
  __objc_resolve_class_links();
}
#endif


static int behavior_debug = 0;

void
GSObjCBehaviorDebug(int i)
{
  behavior_debug = i;
}

#if NeXT_RUNTIME

static GSMethod search_for_method_in_class (Class cls, SEL op);

void
GSObjCAddMethods (Class cls, GSMethodList methods)
{
  static SEL initialize_sel = 0;
  GSMethodList mlist;

  if (!initialize_sel)
    initialize_sel = sel_register_name ("initialize");

  /* Add methods to cls->dtable and cls->methods */
  mlist = methods;
    {
      int counter;
      GSMethodList new_list;

      counter = mlist->method_count ? mlist->method_count - 1 : 1;

      /* This is a little wasteful of memory, since not necessarily
	 all methods will go in here. */
      new_list = (GSMethodList)
	objc_malloc (sizeof(struct objc_method_list) +
		     sizeof(struct objc_method[counter+1]));
      new_list->method_count = 0;

      while (counter >= 0)
        {
          GSMethod method = &(mlist->method_list[counter]);

	  BDBGPrintf("   processing method [%s] ... ",
		     GSNameFromSelector(method->method_name));

	  if (!search_for_method_in_class(cls, method->method_name)
	    && !sel_eq(method->method_name, initialize_sel))
	    {
	      /* As long as the method isn't defined in the CLASS,
		 put the BEHAVIOR method in there.  Thus, behavior
		 methods override the superclasses' methods. */
	      new_list->method_list[new_list->method_count] = *method;
	      (new_list->method_count)++;

	      BDBGPrintf("added.\n");
	    }
	  else
	    {
	      BDBGPrintf("ignored.\n");
	    }
          counter -= 1;
        }
      if (new_list->method_count)
	{
	  class_add_method_list(cls, new_list);
	}
      else
	{
	  OBJC_FREE(new_list);
	}
    }
}

/* Search for the named method's method structure.  Return a pointer
   to the method's method structure if found.  NULL otherwise. */
static GSMethod
search_for_method_in_class (Class cls, SEL op)
{
  void *iterator = 0;
  GSMethodList method_list;

  if (! sel_is_mapped (op))
    return NULL;

  /* If not found then we'll search the list.  */
  while ((method_list = class_nextMethodList(cls, &iterator)))
    {
      int i;

      /* Search the method list.  */
      for (i = 0; i < method_list->method_count; ++i)
        {
          GSMethod method = &method_list->method_list[i];

          if (method->method_name)
            {
              if (sel_eq(method->method_name, op))
                return method;
            }
        }
    }

  return NULL;
}

#else /* GNU runtime */

/*
 * The following two functions are implemented in the GNU objc runtime
 */
extern Method_t search_for_method_in_list(MethodList_t list, SEL op);
extern void class_add_method_list(Class, MethodList_t);

static Method_t search_for_method_in_class (Class cls, SEL op);

void
GSObjCAddMethods (Class cls, GSMethodList methods)
{
  static SEL initialize_sel = 0;
  GSMethodList mlist;

  if (initialize_sel == 0)
    {
      initialize_sel = sel_register_name ("initialize");
    }

  /* Add methods to class->dtable and class->methods */
  for (mlist = methods; mlist; mlist = mlist->method_next)
    {
      int counter;
      GSMethodList new_list;

      counter = mlist->method_count ? mlist->method_count - 1 : 1;

      /* This is a little wasteful of memory, since not necessarily
	 all methods will go in here. */
      new_list = (GSMethodList)
	objc_malloc (sizeof(struct objc_method_list) +
		     sizeof(struct objc_method[counter+1]));
      new_list->method_count = 0;
      new_list->method_next = NULL;

      while (counter >= 0)
        {
          GSMethod method = &(mlist->method_list[counter]);
	  const char *name = GSNameFromSelector(method->method_name);

	  BDBGPrintf("   processing method [%s] ... ", name);

	  if (!search_for_method_in_list(cls->methods, method->method_name)
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

	      BDBGPrintf("added.\n");
	    }
	  else
	    {
	      BDBGPrintf("ignored.\n");
	    }
          counter -= 1;
        }
      if (new_list->method_count)
	{
	  class_add_method_list(cls, new_list);
	}
      else
	{
	  OBJC_FREE(new_list);
	}
    }
}

static Method_t
search_for_method_in_class (Class cls, SEL op)
{
  return cls != NULL ? search_for_method_in_list(cls->methods, op) : NULL;
}

#endif /* NeXT runtime */

GSMethod
GSGetMethod(Class cls, SEL sel,
	    BOOL searchInstanceMethods,
	    BOOL searchSuperClasses)
{
  if (cls == 0 || sel == 0)
    {
      return 0;
    }

  if (searchSuperClasses == NO)
    {
      if (searchInstanceMethods == NO)
	{
	  return search_for_method_in_class(cls->class_pointer, sel);
	}
      else
	{
	  return search_for_method_in_class(cls, sel);
	}
    }
  else
    {
      if (searchInstanceMethods == NO)
	{
	  /*
	    We do not rely on the mapping supplied in objc_gnu2next.h
	    because we want to be explicit about the fact
	    that the expected parameters are different.
	    Therefor we refrain from simply using class_getClassMethod().
	  */
#ifdef NeXT_RUNTIME
	  return class_getClassMethod(cls, sel);
#else
	  return class_get_class_method(cls->class_pointer, sel);
#endif
	}
      else
	{
	  return class_get_instance_method(cls, sel);
	}
    }
}


/* See header for documentation. */
GSMethodList
GSAllocMethodList (unsigned int count)
{
  GSMethodList list;
  size_t size;

  size = (sizeof (struct objc_method_list) +
          sizeof (struct objc_method[count]));
  list = objc_malloc (size);
  memset(list, 0, size);

  return list;
}

/* See header for documentation. */
void
GSAppendMethodToList (GSMethodList list,
                      SEL sel,
                      const char *types,
                      IMP imp,
                      BOOL isFree)
{
  unsigned int num;

  num = (list->method_count)++;

#ifdef GNU_RUNTIME
  /*
     Deal with typed selectors: No matter what kind of selector we get
     convert it into a c-string.  Cache that c-string incase the
     selector isn't found, then search for cooresponding typed selector.
     If none is found use the cached name to register an new selector
     with the cooresponding types.
   */
  sel = (SEL)GSNameFromSelector (sel);

  if (isFree == NO)
    {
      const char *sel_save = (const char *)sel;

      sel = sel_get_typed_uid (sel_save, types);
      if (sel == 0)
        {
          sel = sel_register_typed_name (sel_save, types);
        }
    }
#endif

  list->method_list[num].method_name = sel;
  list->method_list[num].method_types = strdup(types);
  list->method_list[num].method_imp = imp;
}

/* See header for documentation. */
BOOL
GSRemoveMethodFromList (GSMethodList list,
                        SEL sel,
                        BOOL isFree)
{
  int i;

#ifdef GNU_RUNTIME
  if (isFree == YES)
    {
      sel = (SEL)GSNameFromSelector (sel);
    }
#else
  /* Insure that we always use sel_eq on non GNU Runtimes.  */
  isFree = NO;
#endif

  for (i = 0; i < list->method_count; i++)
    {
      SEL  method_name = list->method_list[i].method_name;

      /* For the GNU runtime we have use strcmp instead of sel_eq
	 for free standing method lists.  */
      if ((isFree == YES && strcmp((char *)method_name, (char *)sel) == 0)
          || (isFree == NO && sel_eq(method_name, sel)))
        {
	  /* Found the list.  Now fill up the gap.  */
          for ((list->method_count)--; i < list->method_count; i++)
            {
              list->method_list[i].method_name
                = list->method_list[i+1].method_name;
              list->method_list[i].method_types
                = list->method_list[i+1].method_types;
              list->method_list[i].method_imp
                = list->method_list[i+1].method_imp;
            }

	  /* Clear the last entry.  */
	  /* NB: We may leak the types if they were previously
	     set by GSAppendMethodFromList.  Yet as we can not
	     determine the origin, we shall leak.  */
          list->method_list[i].method_name = 0;
          list->method_list[i].method_types = 0;
          list->method_list[i].method_imp = 0;

          return YES;
        }
    }
  return NO;
}

/* See header for documentation. */
GSMethodList
GSMethodListForSelector(Class cls,
                        SEL selector,
                        void **iterator,
                        BOOL searchInstanceMethods)
{
  void *local_iterator = 0;

  if (cls == 0 || selector == 0)
    {
      return 0;
    }

  if (searchInstanceMethods == NO)
    {
      cls = cls->class_pointer;
    }

  if (sel_is_mapped(selector))
    {
      void **iterator_pointer;
      GSMethodList method_list;

      iterator_pointer = (iterator == 0 ? &local_iterator : iterator);
      while ((method_list = class_nextMethodList(cls, iterator_pointer)))
        {
	  /* Search the method in the current list.  */
	  if (GSMethodFromList(method_list, selector, NO) != 0)
	    {
	      return method_list;
	    }
        }
    }

  return 0;
}

/* See header for documentation. */
GSMethod
GSMethodFromList(GSMethodList list,
                 SEL sel,
		 BOOL isFree)
{
  unsigned i;

#ifdef GNU_RUNTIME
  if (isFree)
    {
      sel = (SEL)GSNameFromSelector (sel);
    }
#else
  isFree = NO;
#endif

  for (i = 0; i < list->method_count; ++i)
    {
      GSMethod method = &list->method_list[i];
      SEL  method_name = method->method_name;

      /* For the GNU runtime we have use strcmp instead of sel_eq
	 for free standing method lists.  */
      if ((isFree == YES && strcmp((char *)method_name, (char *)sel) == 0)
          || (isFree == NO && sel_eq(method_name, sel)))
	{
	  return method;
	}
    }
  return 0;
}

/* See header for documentation. */
void
GSAddMethodList(Class cls,
                GSMethodList list,
                BOOL toInstanceMethods)
{
  if (cls == 0 || list == 0)
    {
      return;
    }

  if (toInstanceMethods == NO)
    {
      cls = cls->class_pointer;
    }

  class_add_method_list(cls, list);
}

GS_STATIC_INLINE void
gs_revert_selector_names_in_list(GSMethodList list)
{
  int i;
  const char *name;

  for (i = 0; i < list->method_count; i++)
    {
      name  = GSNameFromSelector(list->method_list[i].method_name);
      if (name)
	{
	  list->method_list[i].method_name = (SEL)name;
	}
    }
}

/* See header for documentation. */
void
GSRemoveMethodList(Class cls,
                   GSMethodList list,
                   BOOL fromInstanceMethods)
{
  if (cls == 0 || list == 0)
    {
      return;
    }

  if (fromInstanceMethods == NO)
    {
      cls = cls->class_pointer;
    }

#ifdef NeXT_RUNTIME
  class_removeMethods(cls, list);
#else
  if (list == cls->methods)
    {
      cls->methods = list->method_next;
      list->method_next = 0;

      /*
	The list has become "free standing".
	Replace all selector references with selector names
	so the runtime can convert them again
	it the list gets reinserted.
      */
      gs_revert_selector_names_in_list(list);
    }
  else
    {
      GSMethodList current_list;
      for (current_list = cls->methods;
           current_list != 0;
           current_list = current_list->method_next)
        {
          if (current_list->method_next == list)
            {
              current_list->method_next = list->method_next;
              list->method_next = 0;

              /*
                 The list has become "free standing".
                 Replace all selector references with selector names
                 so the runtime can convert them again
                 it the list gets reinserted.
	      */
	      gs_revert_selector_names_in_list(list);
            }
        }
    }
#endif /* NeXT_RUNTIME */
}


GS_STATIC_INLINE const char *
gs_skip_type_qualifier_and_layout_info (const char *types)
{
  while (*types == '+'
	 || *types == '-'
	 || *types == _C_CONST
	 || *types == _C_IN
	 || *types == _C_INOUT
	 || *types == _C_OUT
	 || *types == _C_BYCOPY
	 || *types == _C_BYREF
	 || *types == _C_ONEWAY
	 || *types == _C_GCINVISIBLE
	 || isdigit ((unsigned char) *types))
    {
      types++;
    }

  return types;
}

/* See header for documentation. */
GS_EXPORT BOOL
GSSelectorTypesMatch(const char *types1, const char *types2)
{
  if (! types1 || ! types2)
    return NO;

  while (*types1 && *types2)
    {
      types1 = gs_skip_type_qualifier_and_layout_info (types1);
      types2 = gs_skip_type_qualifier_and_layout_info (types2);

      /* Reached the end of the selector.  */
      if (! *types1 && ! *types2)
        return YES;

      /* Ignore structure name yet compare layout.  */
      if (*types1 == '{' && *types2 == '{')
	{
	  while (*types1 != '=')
	    types1++;

	  while (*types2 != '=')
	    types2++;
	}

      if (*types1 != *types2)
        return NO;

      types1++;
      types2++;
    }

  types1 = gs_skip_type_qualifier_and_layout_info (types1);
  types2 = gs_skip_type_qualifier_and_layout_info (types2);

  return (! *types1 && ! *types2);
}

/* See header for documentation. */
GSIVar
GSCGetInstanceVariableDefinition(Class cls, const char *name)
{
  struct objc_ivar_list *list;
  int i;

  if (cls == 0)
    return 0;

  list = cls->ivars;
  for (i = 0; (list != 0) && i < list->ivar_count; i++)
    {
      if (strcmp (list->ivar_list[i].ivar_name, name) == 0)
	return &(list->ivar_list[i]);
    }
  cls = GSObjCSuper(cls);
  if (cls != 0)
    {
      return GSCGetInstanceVariableDefinition(cls, name);
    }
  return 0;
}

GSIVar
GSObjCGetInstanceVariableDefinition(Class cls, NSString *name)
{
  return GSCGetInstanceVariableDefinition(cls, [name cString]);
}

typedef struct {
  @defs(Protocol)
} *pcl;

GS_STATIC_INLINE unsigned int
gs_string_hash(const char *s)
{
  unsigned int val = 0;
  while (*s != 0)
    {
      val = (val << 5) + val + *s++;
    }
  return val;
}

GS_STATIC_INLINE pcl
gs_find_protocol_named_in_protocol_list(const char *name,
					struct objc_protocol_list *pcllist)
{
  pcl p = NULL;
  size_t i;

  while (pcllist != NULL)
    {
      for (i=0; i<pcllist->count; i++)
	{
	  p = (pcl)pcllist->list[i];
	  if (strcmp(p->protocol_name, name) == 0)
	    {
	      return p;
	    }
	}
      pcllist = pcllist->next;
    }
  return NULL;
}

GS_STATIC_INLINE pcl
gs_find_protocol_named(const char *name)
{
  pcl p = NULL;
  Class cls;
#ifdef NeXT_RUNTIME
  Class *clsList, *clsListStart;
  unsigned int num;

  /* Setting the clearCache flag is a noop for the Apple runtime.  */
  num = GSClassList(NULL, 0, NO);
  clsList = objc_malloc(sizeof(Class) * (num + 1));
  GSClassList(clsList, num, NO);

  clsListStart = clsList;

  while (p == NULL && (cls = *clsList++))
    {
      p = gs_find_protocol_named_in_protocol_list(name, cls->protocols);
    }

  objc_free(clsListStart);

#else
  void *iterator = NULL;

  while (p == NULL && (cls = objc_next_class(&iterator)))
    {
      p = gs_find_protocol_named_in_protocol_list(name, cls->protocols);
    }

#endif
  return p;
}

#define GSI_MAP_HAS_VALUE 1
#define GSI_MAP_RETAIN_KEY(M, X)
#define GSI_MAP_RETAIN_VAL(M, X)
#define GSI_MAP_RELEASE_KEY(M, X)
#define GSI_MAP_RELEASE_VAL(M, X)
#define GSI_MAP_HASH(M, X)    (gs_string_hash(X.ptr))
#define GSI_MAP_EQUAL(M, X,Y) (strcmp(X.ptr, Y.ptr) == 0)
#define GSI_MAP_NOCLEAN 1

#define GSI_MAP_KTYPES GSUNION_PTR
#define GSI_MAP_VTYPES GSUNION_PTR

#include "GNUstepBase/GSIMap.h"

static GSIMapTable_t protocol_by_name;
static BOOL protocol_by_name_init = NO;
static volatile objc_mutex_t protocol_by_name_lock = NULL;

/* Not sure about the semantics of inlining
   functions with static variables.  */
static void
gs_init_protocol_lock(void)
{
  if (protocol_by_name_lock == NULL)
    {
      GSAllocateMutexAt((void *)&protocol_by_name_lock);
      objc_mutex_lock(protocol_by_name_lock);
      if (protocol_by_name_init == NO)
	{
	  GSIMapInitWithZoneAndCapacity (&protocol_by_name,
					 NSDefaultMallocZone(),
					 128);
	  protocol_by_name_init = YES;
	}
      objc_mutex_unlock(protocol_by_name_lock);
    }
}

void
GSRegisterProtocol(Protocol *proto)
{
  if (protocol_by_name_init == NO)
    {
      gs_init_protocol_lock();
    }

  if (proto != nil)
    {
      GSIMapNode node;
      pcl p;

      p = (pcl)proto;
      objc_mutex_lock(protocol_by_name_lock);
      node = GSIMapNodeForKey(&protocol_by_name,
			      (GSIMapKey) p->protocol_name);
      if (node == 0)
	{
	  GSIMapAddPairNoRetain(&protocol_by_name,
				(GSIMapKey) (void *) p->protocol_name,
				(GSIMapVal) (void *) p);
	}
      objc_mutex_unlock(protocol_by_name_lock);
    }
}

Protocol *
GSProtocolFromName(const char *name)
{
  GSIMapNode node;
  pcl p;

  if (protocol_by_name_init == NO)
    {
      gs_init_protocol_lock();
    }

  node = GSIMapNodeForKey(&protocol_by_name, (GSIMapKey) name);
  if (node)
    {
      p = node->value.ptr;
    }
  else
    {
      objc_mutex_lock(protocol_by_name_lock);
      node = GSIMapNodeForKey(&protocol_by_name, (GSIMapKey) name);

      if (node)
	{
	  p = node->value.ptr;
	}
      else
	{
	  p = gs_find_protocol_named(name);
	  if (p)
	    {
	      /* Use the protocol's name to save us from allocating
		 a copy of the parameter 'name'.  */
	      GSIMapAddPairNoRetain(&protocol_by_name,
				    (GSIMapKey) (void *) p->protocol_name,
				    (GSIMapVal) (void *) p);
	    }
	}
      objc_mutex_unlock(protocol_by_name_lock);

    }

  return (Protocol *)p;
}


/**
 * <p>A Behavior can be seen as a "Protocol with an implementation" or a
 * "Class without any instance variables".  A key feature of behaviors
 * is that they give a degree of multiple inheritance.
 * </p>
 * <p>Behavior methods, when added to a class, override the class's
 * superclass methods, but not the class's methods.
 * </p>
 * <p>It's not the case that a class adding behaviors from another class
 * must have "no instance vars".  The receiver class just has to have the
 * same layout as the behavior class (optionally with some additional
 * ivars after those of the behavior class).
 * </p>
 * <p>This function provides Behaviors without adding any new syntax to
 * the Objective C language.  Simply define a class with the methods you
 * want to add, then call this function with that class as the behavior
 * argument.
 * </p>
 * <p>This function should be called in the +initialize method of the receiver.
 * </p>
 * <p>If you add several behaviors to a class, be aware that the order of
 * the additions is significant.
 * </p>
 */
void
GSObjCAddClassBehavior(Class receiver, Class behavior)
{
  Class behavior_super_class = GSObjCSuper(behavior);

  NSCAssert(CLS_ISCLASS(receiver), NSInvalidArgumentException);
  NSCAssert(CLS_ISCLASS(behavior), NSInvalidArgumentException);

  /* If necessary, increase instance_size of CLASS. */
  if (receiver->instance_size < behavior->instance_size)
    {
#if NeXT_RUNTIME
        NSCAssert2(receiver->instance_size >= behavior->instance_size,
          @"Trying to add behavior (%s) with instance size larger than class (%s)",
          class_get_class_name(behavior), class_get_class_name(receiver));
#else
      NSCAssert(!receiver->subclass_list,
	@"The behavior-addition code wants to increase the\n"
	@"instance size of a class, but it cannot because you\n"
	@"have subclassed the class.  There are two solutions:\n"
	@"(1) Don't subclass it; (2) Add placeholder instance\n"
	@"variables to the class, so the behavior-addition code\n"
	@"will not have to increase the instance size\n");
#endif
      receiver->instance_size = behavior->instance_size;
    }

  BDBGPrintf("Adding behavior to class %s\n", receiver->name);
  BDBGPrintf("  instance methods from %s\n", behavior->name);

  /* Add instance methods */
#if NeXT_RUNTIME
  {
    void	 *iterator = 0;
    GSMethodList  method_list;

    method_list = class_nextMethodList(behavior, &iterator);
    while (method_list != 0)
      {
	GSObjCAddMethods (receiver, method_list);
	method_list = class_nextMethodList(behavior, &iterator);
      }
  }
#else
  GSObjCAddMethods (receiver, behavior->methods);
#endif

  /* Add class methods */
  BDBGPrintf("Adding class methods from %s\n",
	     behavior->class_pointer->name);
#if NeXT_RUNTIME
  {
    void	 *iterator = 0;
    GSMethodList  method_list;

    method_list = class_nextMethodList(behavior->class_pointer, &iterator);
    while (method_list != 0)
      {
	GSObjCAddMethods (receiver->class_pointer, method_list);
	method_list = class_nextMethodList(behavior->class_pointer, &iterator);
      }
  }
#else
  GSObjCAddMethods (receiver->class_pointer, behavior->class_pointer->methods);
#endif

  /* Add behavior's superclass, if not already there. */
  if (!GSObjCIsKindOf(receiver, behavior_super_class))
    {
      GSObjCAddClassBehavior (receiver, behavior_super_class);
    }
  GSFlushMethodCacheForClass (receiver);
}




#ifndef NeXT_Foundation_LIBRARY
#include	<Foundation/NSValue.h>
#include	<Foundation/NSKeyValueCoding.h>
#endif


/**  Deprecated ... use GSObjCGetValue() */
id
GSGetValue(NSObject *self, NSString *key, SEL sel,
	   const char *type, unsigned size, int offset)
{
  return GSObjCGetValue(self, key, sel, type, size, offset);
}
/**
 * This is used internally by the key-value coding methods, to get a
 * value from an object either via an accessor method (if sel is
 * supplied), or via direct access (if type, size, and offset are
 * supplied).<br />
 * Automatic conversion between NSNumber and C scalar types is performed.<br />
 * If type is null and can't be determined from the selector, the
 * [NSObject-handleQueryWithUnboundKey:] method is called to try
 * to get a value.
 */
id
GSObjCGetValue(NSObject *self, NSString *key, SEL sel,
	       const char *type, unsigned size, int offset)
{
  if (sel != 0)
    {
      NSMethodSignature	*sig = [self methodSignatureForSelector: sel];

      if ([sig numberOfArguments] != 2)
	{
	  [NSException raise: NSInvalidArgumentException
		      format: @"key-value get method has wrong number of args"];
	}
      type = [sig methodReturnType];
    }
  if (type == NULL)
    {
      return [self valueForUndefinedKey: key];
    }
  else
    {
      id	val = nil;

      switch (*type)
	{
	  case _C_ID:
	  case _C_CLASS:
	    {
	      id	v;

	      if (sel == 0)
		{
		  v = *(id *)((char *)self + offset);
		}
	      else
		{
		  id	(*imp)(id, SEL) =
		    (id (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = v;
	    }
	    break;

	  case _C_CHR:
	    {
	      signed char	v;

	      if (sel == 0)
		{
		  v = *(char *)((char *)self + offset);
		}
	      else
		{
		  signed char	(*imp)(id, SEL) =
		    (signed char (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithChar: v];
	    }
	    break;

	  case _C_UCHR:
	    {
	      unsigned char	v;

	      if (sel == 0)
		{
		  v = *(unsigned char *)((char *)self + offset);
		}
	      else
		{
		  unsigned char	(*imp)(id, SEL) =
		    (unsigned char (*)(id, SEL))[self methodForSelector:
		    sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithUnsignedChar: v];
	    }
	    break;

	  case _C_SHT:
	    {
	      short	v;

	      if (sel == 0)
		{
		  v = *(short *)((char *)self + offset);
		}
	      else
		{
		  short	(*imp)(id, SEL) =
		    (short (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithShort: v];
	    }
	    break;

	  case _C_USHT:
	    {
	      unsigned short	v;

	      if (sel == 0)
		{
		  v = *(unsigned short *)((char *)self + offset);
		}
	      else
		{
		  unsigned short	(*imp)(id, SEL) =
		    (unsigned short (*)(id, SEL))[self methodForSelector:
		    sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithUnsignedShort: v];
	    }
	    break;

	  case _C_INT:
	    {
	      int	v;

	      if (sel == 0)
		{
		  v = *(int *)((char *)self + offset);
		}
	      else
		{
		  int	(*imp)(id, SEL) =
		    (int (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithInt: v];
	    }
	    break;

	  case _C_UINT:
	    {
	      unsigned int	v;

	      if (sel == 0)
		{
		  v = *(unsigned int *)((char *)self + offset);
		}
	      else
		{
		  unsigned int	(*imp)(id, SEL) =
		    (unsigned int (*)(id, SEL))[self methodForSelector:
		    sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithUnsignedInt: v];
	    }
	    break;

	  case _C_LNG:
	    {
	      long	v;

	      if (sel == 0)
		{
		  v = *(long *)((char *)self + offset);
		}
	      else
		{
		  long	(*imp)(id, SEL) =
		    (long (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithLong: v];
	    }
	    break;

	  case _C_ULNG:
	    {
	      unsigned long	v;

	      if (sel == 0)
		{
		  v = *(unsigned long *)((char *)self + offset);
		}
	      else
		{
		  unsigned long	(*imp)(id, SEL) =
		    (unsigned long (*)(id, SEL))[self methodForSelector:
		    sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithUnsignedLong: v];
	    }
	    break;

#ifdef	_C_LNG_LNG
	  case _C_LNG_LNG:
	    {
	      long long	v;

	      if (sel == 0)
		{
		  v = *(long long *)((char *)self + offset);
		}
	      else
		{
		   long long	(*imp)(id, SEL) =
		    (long long (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithLongLong: v];
	    }
	    break;
#endif

#ifdef	_C_ULNG_LNG
	  case _C_ULNG_LNG:
	    {
	      unsigned long long	v;

	      if (sel == 0)
		{
		  v = *(unsigned long long *)((char *)self + offset);
		}
	      else
		{
		  unsigned long long	(*imp)(id, SEL) =
		    (unsigned long long (*)(id, SEL))[self
		    methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithUnsignedLongLong: v];
	    }
	    break;
#endif

	  case _C_FLT:
	    {
	      float	v;

	      if (sel == 0)
		{
		  v = *(float *)((char *)self + offset);
		}
	      else
		{
		  float	(*imp)(id, SEL) =
		    (float (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithFloat: v];
	    }
	    break;

	  case _C_DBL:
	    {
	      double	v;

	      if (sel == 0)
		{
		  v = *(double *)((char *)self + offset);
		}
	      else
		{
		  double	(*imp)(id, SEL) =
		    (double (*)(id, SEL))[self methodForSelector: sel];

		  v = (*imp)(self, sel);
		}
	      val = [NSNumber numberWithDouble: v];
	    }
	    break;

	  case _C_VOID:
            {
              void        (*imp)(id, SEL) =
                (void (*)(id, SEL))[self methodForSelector: sel];

              (*imp)(self, sel);
            }
            val = nil;
            break;

	  default:
	    [NSException raise: NSInvalidArgumentException
			format: @"key-value get method has unsupported type"];
	}
      return val;
    }
}

/**  Deprecated ... use GSObjCSetValue() */
void
GSSetValue(NSObject *self, NSString *key, id val, SEL sel,
	   const char *type, unsigned size, int offset)
{
  GSObjCSetValue(self, key, val, sel, type, size, offset);
}
/**
 * This is used internally by the key-value coding methods, to set a
 * value in an object either via an accessor method (if sel is
 * supplied), or via direct access (if type, size, and offset are
 * supplied).<br />
 * Automatic conversion between NSNumber and C scalar types is performed.<br />
 * If type is null and can't be determined from the selector, the
 * [NSObject-handleTakeValue:forUnboundKey:] method is called to try
 * to set a value.
 */
void
GSObjCSetValue(NSObject *self, NSString *key, id val, SEL sel,
	       const char *type, unsigned size, int offset)
{
  static NSNull	*null = nil;

  if (null == nil)
    {
      null = [NSNull new];
    }
  if (sel != 0)
    {
      NSMethodSignature	*sig = [self methodSignatureForSelector: sel];

      if ([sig numberOfArguments] != 3)
	{
	  [NSException raise: NSInvalidArgumentException
		      format: @"key-value set method has wrong number of args"];
	}
      type = [sig getArgumentTypeAtIndex: 2];
    }
  if (type == NULL)
    {
      [self setValue: val forUndefinedKey: key];
    }
  else if ((val == nil || val == null) && *type != _C_ID && *type != _C_CLASS)
    {
      [self setNilValueForKey: key];
    }
  else
    {
      switch (*type)
	{
	  case _C_ID:
	  case _C_CLASS:
	    {
	      id	v = val;

	      if (sel == 0)
		{
		  id *ptr = (id *)((char *)self + offset);

		  ASSIGN(*ptr, v);
		}
	      else
		{
		  void	(*imp)(id, SEL, id) =
		    (void (*)(id, SEL, id))[self methodForSelector: sel];

		  (*imp)(self, sel, val);
		}
	    }
	    break;

	  case _C_CHR:
	    {
	      char	v = [val charValue];

	      if (sel == 0)
		{
		  char *ptr = (char *)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, char) =
		    (void (*)(id, SEL, char))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_UCHR:
	    {
	      unsigned char	v = [val unsignedCharValue];

	      if (sel == 0)
		{
		  unsigned char *ptr = (unsigned char*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, unsigned char) =
		    (void (*)(id, SEL, unsigned char))[self methodForSelector:
		    sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_SHT:
	    {
	      short	v = [val shortValue];

	      if (sel == 0)
		{
		  short *ptr = (short*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, short) =
		    (void (*)(id, SEL, short))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_USHT:
	    {
	      unsigned short	v = [val unsignedShortValue];

	      if (sel == 0)
		{
		  unsigned short *ptr;

		  ptr = (unsigned short*)((char *)self + offset);
		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, unsigned short) =
		    (void (*)(id, SEL, unsigned short))[self methodForSelector:
		    sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_INT:
	    {
	      int	v = [val intValue];

	      if (sel == 0)
		{
		  int *ptr = (int*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, int) =
		    (void (*)(id, SEL, int))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_UINT:
	    {
	      unsigned int	v = [val unsignedIntValue];

	      if (sel == 0)
		{
		  unsigned int *ptr = (unsigned int*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, unsigned int) =
		    (void (*)(id, SEL, unsigned int))[self methodForSelector:
		    sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_LNG:
	    {
	      long	v = [val longValue];

	      if (sel == 0)
		{
		  long *ptr = (long*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, long) =
		    (void (*)(id, SEL, long))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_ULNG:
	    {
	      unsigned long	v = [val unsignedLongValue];

	      if (sel == 0)
		{
		  unsigned long *ptr = (unsigned long*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, unsigned long) =
		    (void (*)(id, SEL, unsigned long))[self methodForSelector:
		    sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

#ifdef	_C_LNG_LNG
	  case _C_LNG_LNG:
	    {
	      long long	v = [val longLongValue];

	      if (sel == 0)
		{
		  long long *ptr = (long long*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, long long) =
		    (void (*)(id, SEL, long long))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;
#endif

#ifdef	_C_ULNG_LNG
	  case _C_ULNG_LNG:
	    {
	      unsigned long long	v = [val unsignedLongLongValue];

	      if (sel == 0)
		{
		  unsigned long long *ptr = (unsigned long long*)((char*)self +
								  offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, unsigned long long) =
		    (void (*)(id, SEL, unsigned long long))[self
		    methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;
#endif

	  case _C_FLT:
	    {
	      float	v = [val floatValue];

	      if (sel == 0)
		{
		  float *ptr = (float*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, float) =
		    (void (*)(id, SEL, float))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  case _C_DBL:
	    {
	      double	v = [val doubleValue];

	      if (sel == 0)
		{
		  double *ptr = (double*)((char *)self + offset);

		  *ptr = v;
		}
	      else
		{
		  void	(*imp)(id, SEL, double) =
		    (void (*)(id, SEL, double))[self methodForSelector: sel];

		  (*imp)(self, sel, v);
		}
	    }
	    break;

	  default:
	    [NSException raise: NSInvalidArgumentException
			format: @"key-value set method has unsupported type"];
	}
    }
}


/** Returns an autoreleased array of subclasses of Class cls, including
 *  subclasses of subclasses. */
NSArray *GSObjCAllSubclassesOfClass(Class cls)
{
  if (!cls)
    {
      return nil;
    }
  else
    {
      Class aClass;
      NSMutableArray *result = [[NSMutableArray alloc] init];

#ifdef GNU_RUNTIME
      for (aClass = cls->subclass_list; aClass; aClass=aClass->sibling_class)
	{
	  if (CLS_ISMETA(aClass))
	    continue;
	  [result addObject:aClass];
	  [result addObjectsFromArray: GSObjCAllSubclassesOfClass(aClass)];
	}
#else
#warning not implemented for the NeXT_RUNTIME
#endif
      return AUTORELEASE(result);
    }
}

/** Returns an autoreleased array containing subclasses directly descendent of
 *  Class cls. */
NSArray *GSObjCDirectSubclassesOfClass(Class cls)
{
  if (!cls)
    {
      return nil;
    }
  else
    {
      NSMutableArray *result=[[NSMutableArray alloc] init];
      Class aClass;

#ifdef GNU_RUNTIME
      for (aClass = cls->subclass_list;aClass;aClass=aClass->sibling_class)
	{
	  if (CLS_ISMETA(aClass))
	    continue;
	  [result addObject:aClass];
	}
#else
#warning not implemented for the NeXT_RUNTIME
#endif
      return AUTORELEASE(result);
    }
}

void *
GSAutoreleasedBuffer(unsigned size)
{
#if GS_WITH_GC
  return GC_malloc(size);
#else
#ifdef ALIGN
#undef ALIGN
#endif
#define ALIGN __alignof__(double)

  static Class	nsobject_class = 0;
  static Class	autorelease_class;
  static SEL	autorelease_sel;
  static IMP	autorelease_imp;
  static int	offset;
  NSObject	*o;

  if (nsobject_class == 0)
    {
      nsobject_class = [NSObject class];
      offset = nsobject_class->instance_size % ALIGN;
      autorelease_class = [NSAutoreleasePool class];
      autorelease_sel = @selector(addObject:);
      autorelease_imp = [autorelease_class methodForSelector: autorelease_sel];
    }
  o = (NSObject*)NSAllocateObject(nsobject_class,
    size + offset, NSDefaultMallocZone());
  (*autorelease_imp)(autorelease_class, autorelease_sel, o);
  return ((void*)&o[1]) + offset;
#endif
}



/* Getting a system error message on a variety of systems */
#ifdef __MINGW__
LPTSTR GetErrorMsg(DWORD msgId)
{
  LPVOID lpMsgBuf;

  FormatMessage(
    FORMAT_MESSAGE_ALLOCATE_BUFFER |
    FORMAT_MESSAGE_FROM_SYSTEM |
    FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL, msgId,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), // Default language
    (LPTSTR)&lpMsgBuf, 0, NULL);

  return (LPTSTR)lpMsgBuf;
}
#else
#ifndef HAVE_STRERROR
const char *
strerror(int eno)
{
  extern char  *sys_errlist[];
  extern int    sys_nerr;

  if (eno < 0 || eno >= sys_nerr)
    {
      return("unknown error number");
    }
  return(sys_errlist[eno]);
}
#endif
#endif /* __MINGW__ */

const char *
GSLastErrorStr(long error_id)
{
#ifdef __MINGW__
  return GetErrorMsg(GetLastError());
#else
  return strerror(error_id);
#endif
}



BOOL
GSPrintf (FILE *fptr, NSString* format, ...)
{
  static Class                  stringClass = 0;
  static NSStringEncoding       enc;
  CREATE_AUTORELEASE_POOL(arp);
  va_list       ap;
  NSString      *message;
  NSData        *data;
  BOOL          ok = NO;

  if (stringClass == 0)
    {
      stringClass = [NSString class];
      enc = [stringClass defaultCStringEncoding];
    }
  message = [stringClass allocWithZone: NSDefaultMallocZone()];
  va_start (ap, format);
  message = [message initWithFormat: format locale: nil arguments: ap];
  va_end (ap);
  data = [message dataUsingEncoding: enc];
  if (data == nil)
    {
      data = [message dataUsingEncoding: NSUTF8StringEncoding];
    }
  RELEASE(message);

  if (data != nil)
    {
      unsigned int      length = [data length];

      if (length == 0 || fwrite([data bytes], 1, length, fptr) == length)
        {
          ok = YES;
        }
    }
  RELEASE(arp);
  return ok;
}
