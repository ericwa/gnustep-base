/* Implementation of NSBundle class
   Copyright (C) 1993,1994,1995, 1996, 1997 Free Software Foundation, Inc.

   Written by:  Adam Fedor <fedor@boulder.colorado.edu>
   Date: May 1993

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

#include <config.h>
#include <base/preface.h>
#include <Foundation/objc-load.h>
#include <Foundation/NSBundle.h>
#include <Foundation/NSException.h>
#include <Foundation/NSString.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDebug.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSProcessInfo.h>
#include <Foundation/NSObjCRuntime.h>
#include <Foundation/NSUserDefaults.h>
#include <Foundation/NSNotification.h>
#include <Foundation/NSLock.h>
#include <Foundation/NSMapTable.h>
#include <Foundation/NSAutoreleasePool.h>
#include <Foundation/NSFileManager.h>
#include <unistd.h>

typedef enum {
  NSBUNDLE_BUNDLE = 1, NSBUNDLE_APPLICATION, NSBUNDLE_LIBRARY
} bundle_t;

/* Class variables - We keep track of all the bundles */
static NSBundle*   _mainBundle = nil;
static NSMapTable* _bundles = NULL;

/* Keep the path to the executable file for finding the main bundle. */
static NSString *_executable_path;

/*
 * An empty strings file table for use when localization files can't be found.
 */
static NSDictionary	*_emptyTable = nil;

/* This is for bundles that we can't unload, so they shouldn't be
   dealloced.  This is true for all bundles right now */
static NSMapTable* _releasedBundles = NULL;

/* When we are linking in an object file, objc_load_modules calls our
   callback routine for every Class and Category loaded.  The following
   variable stores the bundle that is currently doing the loading so we know
   where to store the class names. 
*/
static NSBundle* _loadingBundle = nil;
static NSBundle* _gnustep_bundle = nil;
static NSRecursiveLock* load_lock = nil;
static BOOL _strip_after_loading = NO;

static NSString* gnustep_target_dir = 
#ifdef GNUSTEP_TARGET_DIR
  @GNUSTEP_TARGET_DIR;
#else
  nil;
#endif
static NSString* gnustep_target_cpu = 
#ifdef GNUSTEP_TARGET_CPU
  @GNUSTEP_TARGET_CPU;
#else
  nil;
#endif
static NSString* gnustep_target_os = 
#ifdef GNUSTEP_TARGET_OS
  @GNUSTEP_TARGET_OS;
#else
  nil;
#endif
static NSString* library_combo = 
#ifdef LIBRARY_COMBO
  @LIBRARY_COMBO;
#else
  nil;
#endif

/* This function is provided for objc-load.c, although I'm not sure it
   really needs it (So far only needed if using GNU dld library) */
const char *
objc_executable_location( void )
{
  return [[[NSBundle mainBundle] bundlePath] cString];
}

static BOOL
bundle_directory_readable(NSString *path)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  BOOL directory;

  if (![mgr fileExistsAtPath: path isDirectory: &directory]
      || !directory)
    return NO;

  return [mgr isReadableFileAtPath: path];
}

static BOOL
bundle_file_readable(NSString *path)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  return [mgr isReadableFileAtPath: path];
}

/* Get the object file that should be located in the bundle of the same name */
static NSString *
bundle_object_name(NSString *path, NSString* executable)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  NSString	*name, *path0, *path1, *path2;

  if (executable)
    {
      NSString	*exepath;

      name = [executable lastPathComponent];
      exepath = [executable stringByDeletingLastPathComponent];
      if ([exepath isEqualToString: @""] == NO)
	{
	  if ([exepath isAbsolutePath] == YES)
	    path = exepath;
	  else
	    path = [path stringByAppendingPathComponent: exepath];
	}
    }
  else
    {
      name = [[path lastPathComponent] stringByDeletingPathExtension];
      path = [path stringByDeletingLastPathComponent];
    }
  path0 = [path stringByAppendingPathComponent: name];
  path = [path stringByAppendingPathComponent: gnustep_target_dir];
  path1 = [path stringByAppendingPathComponent: name];
  path = [path stringByAppendingPathComponent: library_combo];
  path2 = [path stringByAppendingPathComponent: executable];

  if ([mgr isReadableFileAtPath: path2] == YES)
    return path2;
  else if ([mgr isReadableFileAtPath: path1] == YES)
    return path1;
  else if ([mgr isReadableFileAtPath: path0] == YES)
    return path0;
  return path2;
}

/* Construct a path from components */
static NSString * 
_bundle_resource_path(NSString *primary, NSString* bundlePath, NSString *lang)
{
  if (bundlePath)
    primary = [primary stringByAppendingPathComponent: bundlePath];
  if (lang)
    primary = [primary stringByAppendingPathComponent: 
	         [NSString stringWithFormat: @"%@.lproj", lang]];
  return primary;
}

/* Find the first directory entry with a given name (with any extension) */
static NSString *
_bundle_name_first_match(NSString* directory, NSString* name)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  NSEnumerator *filelist;
  NSString *path, *match;

  path = [directory stringByAppendingPathComponent: name];
  filelist = [[mgr directoryContentsAtPath: directory] objectEnumerator];
  while ((match = [filelist nextObject]))
    {
      if ([name isEqual: [match stringByDeletingPathExtension]])
	return [directory stringByAppendingPathComponent: match];
    }

  return nil;
}

@interface NSBundle (Private)
- (NSArray *) _bundleClasses;
@end

@implementation NSBundle (Private)
- (NSArray *) _bundleClasses
{
  return _bundleClasses;
}
@end

void
_bundle_load_callback(Class theClass, Category *theCategory)
{
  NSCAssert(_loadingBundle, NSInternalInconsistencyException);
  /* Don't store categories */
  if (!theCategory)
    [(NSMutableArray *)[_loadingBundle _bundleClasses] addObject: (id)theClass];
}

@implementation NSBundle

+ (void)initialize
{
  if (self == [NSBundle class])
    {
      NSDictionary	*env;

      _emptyTable = RETAIN([NSDictionary dictionary]);

      /* Need to make this recursive since both mainBundle and initWithPath:
	 want to lock the thread */
      load_lock = [NSRecursiveLock new];
      env = [[NSProcessInfo processInfo] environment];
      if (env)
	{
	  NSMutableString	*system;
	  NSString		*str;

	  if ((str = [env objectForKey: @"GNUSTEP_TARGET_DIR"]) != nil)
	    gnustep_target_dir = RETAIN(str);
	  else if ((str = [env objectForKey: @"GNUSTEP_HOST_DIR"]) != nil)
	    gnustep_target_dir = RETAIN(str);
	
	  if ((str = [env objectForKey: @"GNUSTEP_TARGET_CPU"]) != nil)
	    gnustep_target_cpu = RETAIN(str);
	  else if ((str = [env objectForKey: @"GNUSTEP_HOST_CPU"]) != nil)
	    gnustep_target_cpu = RETAIN(str);
	
	  if ((str = [env objectForKey: @"GNUSTEP_TARGET_OS"]) != nil)
	    gnustep_target_os = RETAIN(str);
	  else if ((str = [env objectForKey: @"GNUSTEP_HOST_OS"]) != nil)
	    gnustep_target_os = RETAIN(str);
	
	  if ((str = [env objectForKey: @"LIBRARY_COMBO"]) != nil)
	    library_combo = RETAIN(str);

	  system = AUTORELEASE([[env objectForKey: @"GNUSTEP_SYSTEM_ROOT"]
		    mutableCopy]);
	  [system appendString: @"/Libraries"];

	  _executable_path = nil;
#ifdef HAVE_PROC_FS_EXE_LINK
	  _executable_path = [[NSFileManager defaultManager]
	    pathContentOfSymbolicLinkAtPath: @"/proc/self/exe"];
#endif
	  if (_executable_path == nil || [_executable_path length] == 0)
	    {
	      _executable_path =
		[[[NSProcessInfo processInfo] arguments] objectAtIndex: 0];
	      _executable_path = 
		[NSBundle _absolutePathOfExecutable: _executable_path];
	      NSAssert(_executable_path, NSInternalInconsistencyException);
	    }

	  RETAIN(_executable_path);
	  _gnustep_bundle = RETAIN([NSBundle bundleWithPath: system]);
	}
    }
}

+ (NSArray *) allBundles
{
  NSMapEnumerator	enumerate;
  NSMutableArray	*array = [NSMutableArray arrayWithCapacity: 2];
  void			*key;
  NSBundle		*bundle;

  [load_lock lock];
  enumerate = NSEnumerateMapTable(_bundles);
  while (NSNextMapEnumeratorPair(&enumerate, &key, (void **)&bundle))
    {
      if ([array indexOfObjectIdenticalTo: bundle] == NSNotFound)
	{
	  /* FIXME - must ignore frameworks here */
	  [array addObject: bundle];
	}
    }
  [load_lock unlock];
  return array;
}

+ (NSArray *) allFrameworks
{
  return [self notImplemented: _cmd];
}

+ (NSString *) _absolutePathOfExecutable: (NSString *)path
{
  NSFileManager *mgr;
  NSDictionary   *env;
  NSString *pathlist, *prefix;
  id patharr;

  path = [path stringByStandardizingPath];
  if ([path isAbsolutePath])
    return path;

  mgr = [NSFileManager defaultManager];
  env = [[NSProcessInfo processInfo] environment];
  pathlist = [env objectForKey:@"PATH"];
#if defined(__MINGW__)
  patharr = [pathlist componentsSeparatedByString:@";"];
#else
  patharr = [pathlist componentsSeparatedByString:@":"];
#endif
  patharr = [patharr objectEnumerator];
  while ((prefix = [patharr nextObject]))
    {
      if ([prefix isEqual:@"."])
	prefix = [mgr currentDirectoryPath];
      prefix = [prefix stringByAppendingPathComponent: path];
      if ([mgr isExecutableFileAtPath: prefix])
	return [prefix stringByStandardizingPath];
#if defined(__WIN32__)
      /* Also add common executable extensions on windows */
      if ([path pathExtension] == nil)
	{
	  NSString *wpath;
	  wpath = [prefix stringByAppendingPathExtension: @"exe"];
	  if ([mgr isExecutableFileAtPath: wpath])
	    return [wpath stringByStandardizingPath];
	  wpath = [prefix stringByAppendingPathExtension: @"com"];
	  if ([mgr isExecutableFileAtPath: wpath])
	    return [wpath stringByStandardizingPath];
	  wpath = [prefix stringByAppendingPathExtension: @"cmd"];
	  if ([mgr isExecutableFileAtPath: wpath])
	    return [wpath stringByStandardizingPath];
	}
#endif
    }
  return nil;
}

+ (NSBundle *)mainBundle
{
  [load_lock lock];
  if ( !_mainBundle ) 
    {
      NSString *path, *s;
      
      /* Strip off the name of the program */
      path = [_executable_path stringByDeletingLastPathComponent];

      /* The executable may not lie in the main bundle directory
	 so we need to chop off the extra subdirectories, the library
	 combo and the target cpu/os if they exist.  The executable and
	 this library should match so that is why we can use the
	 compiled-in settings. */
      /* library combo */
      s = [path lastPathComponent];
      if ([s isEqual: library_combo])
	path = [path stringByDeletingLastPathComponent];
      /* target os */
      s = [path lastPathComponent];
      if ([s isEqual: gnustep_target_os])
	path = [path stringByDeletingLastPathComponent];
      /* target cpu */
      s = [path lastPathComponent];
      if ([s isEqual: gnustep_target_cpu])
	path = [path stringByDeletingLastPathComponent];
      /* object dir */
      s = [path lastPathComponent];
      if ([s hasSuffix: @"_obj"])
	path = [path stringByDeletingLastPathComponent];

      NSDebugMLLog(@"NSBundle", @"Found main in %@\n", path);
      /* We do alloc and init separately so initWithPath: knows
          we are the _mainBundle */
      _mainBundle = [NSBundle alloc];
      _mainBundle = [_mainBundle initWithPath:path];
    }
  
  [load_lock unlock];
  return _mainBundle;
}

/* Due to lazy evaluation, we will not find a class if either classNamed: or
   principalClass has not been called on the particular bundle that contains
   the class. (FIXME)
*/
+ (NSBundle *) bundleForClass: (Class)aClass
{
  void*     key;
  NSBundle* bundle;
  NSMapEnumerator enumerate;
  if (!aClass)
    return nil;

  [load_lock lock];
  bundle = nil;
  enumerate = NSEnumerateMapTable(_bundles);
  while (NSNextMapEnumeratorPair(&enumerate, &key, (void **)&bundle))
    {
      int j;
      j = [[bundle _bundleClasses] indexOfObject: aClass];
      if (j != NSNotFound && [bundle _bundleClasses])
	break;
      bundle = nil;
    }
  [load_lock unlock];
  if (!bundle) 
    {
      /* Is it in the main bundle? */
      if (class_is_class(aClass))
	bundle = [NSBundle mainBundle];
    }

  return bundle;
}

+ (NSBundle *)bundleWithPath:(NSString *)path
{
  return AUTORELEASE([[NSBundle alloc] initWithPath: path]);
}

- initWithPath:(NSString *)path;
{
  [super init];

  if (!path || [path length] == 0) 
    {
      NSLog(@"No path specified for bundle");
      return nil;
    }
  if ([path isAbsolutePath] == NO)
    {
      NSLog(@"WARNING: NSBundle -initWithPath: requires absolute path names!");
      path = [[[NSFileManager defaultManager] currentDirectoryPath]
        stringByAppendingPathComponent: path];
    }

  /* Check if we were already initialized for this directory */
  [load_lock lock];
  if (_bundles) 
    {
      NSBundle* bundle = (NSBundle *)NSMapGet(_bundles, path);
      if (bundle)
	{
	  RETAIN(bundle); /* retain - look as if we were alloc'ed */
	  [load_lock unlock];
	  [self dealloc];
	  return bundle;
	}
    }
  if (_releasedBundles)
    {
      NSBundle* loaded = (NSBundle *)NSMapGet(_releasedBundles, path);
      if (loaded)
	{
	  NSMapInsert(_bundles, path, loaded);
	  NSMapRemove(_releasedBundles, path);
	  RETAIN(loaded); /* retain - look as if we were alloc'ed */
	  [load_lock unlock];
	  [self dealloc];
	  return loaded;
	}
    }
  [load_lock unlock];

  if (bundle_directory_readable(path) == NO)
    {
      NSDebugMLLog(@"NSBundle", @"Could not access path %@ for bundle", path);
      //[self dealloc];
      //return nil;
    }

  _path = [path copy];
  _bundleType = (unsigned int)NSBUNDLE_BUNDLE;
  if (self == _mainBundle)
    _bundleType = (unsigned int)NSBUNDLE_APPLICATION;

  [load_lock lock];
  if (!_bundles)
    {
      _bundles = NSCreateMapTable(NSObjectMapKeyCallBacks,
				  NSNonOwnedPointerMapValueCallBacks, 0);
      _releasedBundles = NSCreateMapTable(NSObjectMapKeyCallBacks,
				  NSNonOwnedPointerMapValueCallBacks, 0);
    }
  NSMapInsert(_bundles, _path, self);
  [load_lock unlock];

  return self;
}

/* Some bundles should not be dealloced, such as the main bundle. So we
   keep track of our own retain count to avoid this.
   Currently, the objc runtime can't unload modules, so we actually
   avoid deallocating any bundle with code loaded */
- (oneway void) release
{
  if (_codeLoaded == YES || self == _mainBundle || self == _gnustep_bundle) 
    {
      if ([self retainCount] == 1)
	{
	  [load_lock lock];
	  if (self == NSMapGet(_releasedBundles, _path))
	    {
	      [load_lock unlock];
	      [NSException raise: NSGenericException
		format: @"Bundle for path %@ released too many times", _path];
	    }
      
	  NSMapRemove(_bundles, _path);
	  NSMapInsert(_releasedBundles, _path, self);
	  [load_lock unlock];
	  return;
	}
    }
  [super release];
}

- (void) dealloc
{
  if (_path != nil)
    {
      [load_lock lock];
      NSMapRemove(_bundles, _path);
      [load_lock unlock];
      RELEASE(_path);
    }
  TEST_RELEASE(_bundleClasses);
  TEST_RELEASE(_infoDict);
  TEST_RELEASE(_localizations);
  [super dealloc];
}

- (NSString *) bundlePath
{
  return _path;
}

- (Class) classNamed: (NSString *)className
{
  int     j;
  Class   theClass = Nil;
  if (!_codeLoaded) 
    {
      if (self != _mainBundle && ![self load]) 
	{
	  NSLog(@"No classes in bundle");
	  return Nil;
	}
    }

  if (self == _mainBundle || self == _gnustep_bundle)
    {
      theClass = NSClassFromString(className);
      if (theClass && [[self class] bundleForClass:theClass] != _mainBundle)
	theClass = Nil;
    } 
  else 
    {
      j = [_bundleClasses indexOfObject: NSClassFromString(className)];
      if (j != NSNotFound)
	theClass = [_bundleClasses objectAtIndex: j];
    }
  
  return theClass;
}

- (Class) principalClass
{
  NSString* class_name;

  if (_principalClass)
    return _principalClass;

  class_name = [[self infoDictionary] objectForKey: @"NSPrincipalClass"];

  if (self == _mainBundle || self == _gnustep_bundle) 
    {
      _codeLoaded = YES;
      if (class_name)
	_principalClass = NSClassFromString(class_name);
      return _principalClass;
    }

  if ([self load] == NO)
    return Nil;

  if (class_name)
    _principalClass = NSClassFromString(class_name);
  else if ([_bundleClasses count])
    _principalClass = [_bundleClasses objectAtIndex:0];
  return _principalClass;
}

- (BOOL) load
{
  if (self == _mainBundle || self == _gnustep_bundle) 
    {
      _codeLoaded = YES;
      return YES;
    }

  [load_lock lock];
  if (!_codeLoaded) 
    {
      NSString* object;
      object = [[self infoDictionary] objectForKey: @"NSExecutable"];
      if (object == nil || [object length] == 0)
	{
	  [load_lock unlock];
	  return NO;
	}
      object = bundle_object_name(_path, object);
      _loadingBundle = self;
      _bundleClasses = RETAIN([NSMutableArray arrayWithCapacity: 2]);
      if (objc_load_module([object cString], 
			   stderr, _bundle_load_callback, NULL, NULL))
	{
	  [load_lock unlock];
	  return NO;
	}
      _codeLoaded = YES;
      _loadingBundle = nil;
      [load_lock unlock];
      [[NSNotificationCenter defaultCenter]
        postNotificationName: NSBundleDidLoadNotification 
        object: self
        userInfo: [NSDictionary dictionaryWithObjects: &_bundleClasses
	       forKeys: &NSLoadedClasses count: 1]];
      return YES;
    }
  [load_lock unlock];
  return YES;
}

/* This method is the backbone of the resource searching for NSBundle. It
   constructs an array of paths, where each path is a possible location
   for a resource in the bundle.  The current algorithm for searching goes:

     <main bundle>/Resources/<bundlePath>
     <main bundle>/Resources/<bundlePath>/<language.lproj>
     <main bundle>/<bundlePath>
     <main bundle>/<bundlePath>/<language.lproj>
*/
+ (NSArray *) _bundleResourcePathsWithRootPath: (NSString *)rootPath
                                 subPath: (NSString *)bundlePath
{
  NSString* primary;
  NSString* language;
  NSArray* languages;
  NSMutableArray* array;
  NSEnumerator* enumerate;

  array = [NSMutableArray arrayWithCapacity: 8];
  languages = [NSUserDefaults userLanguages];

  primary = [rootPath stringByAppendingPathComponent: @"Resources"];
  [array addObject: _bundle_resource_path(primary, bundlePath, nil)];
  enumerate = [languages objectEnumerator];
  while ((language = [enumerate nextObject]))
    [array addObject: _bundle_resource_path(primary, bundlePath, language)];
     
  primary = rootPath;
  [array addObject: _bundle_resource_path(primary, bundlePath, nil)];
  enumerate = [languages objectEnumerator];
  while ((language = [enumerate nextObject]))
    [array addObject: _bundle_resource_path(primary, bundlePath, language)];

  return array;
}

+ (NSString *) pathForResource: (NSString *)name
		ofType: (NSString *)ext	
		inRootPath: (NSString *)rootPath
		inDirectory: (NSString *)bundlePath
		withVersion: (int)version
{
  NSString *path, *fullpath;
  NSEnumerator* pathlist;
    
  if (!name || [name length] == 0) 
    {
      [NSException raise: NSInvalidArgumentException
        format: @"No resource name specified."];
      /* NOT REACHED */
    }

  pathlist = [[NSBundle _bundleResourcePathsWithRootPath: rootPath
	       subPath: bundlePath] objectEnumerator];
  fullpath = nil;
  while((path = [pathlist nextObject]))
    {
      if (!bundle_directory_readable(path))
	continue;

      if (ext && [ext length] != 0)
	{
	  fullpath = [path stringByAppendingPathComponent:
		        [NSString stringWithFormat: @"%@.%@", name, ext]];
	  if ( bundle_file_readable(fullpath) )
	    {
	      if (gnustep_target_os)
		{
		  NSString* platpath;
		  platpath = [path stringByAppendingPathComponent:
			      [NSString stringWithFormat: @"%@-%@.%@", 
			       name, gnustep_target_os, ext]];
		  if ( bundle_file_readable(platpath) )
		    fullpath = platpath;
		}
	    }
	  else
	    fullpath = nil;
	}
      else
	{
	  fullpath = _bundle_name_first_match(path, name);
	  if (fullpath && gnustep_target_os)
	    {
	      NSString* platpath;
	      platpath = _bundle_name_first_match(path, 
				   [NSString stringWithFormat: @"%@-%@", 
				   name, gnustep_target_os]);
	      if (platpath)
		fullpath = platpath;
	    }
	}
      if (fullpath)
	break;
    }

  return fullpath;
}

+ (NSString *) pathForResource: (NSString *)name
		ofType: (NSString *)ext	
		inDirectory: (NSString *)bundlePath
		withVersion: (int) version
{
    return [self pathForResource: name
			  ofType: ext
                      inRootPath: bundlePath
		     inDirectory: nil
		     withVersion: version];
}

+ (NSString *) pathForResource: (NSString *)name
		ofType: (NSString *)ext	
		inDirectory: (NSString *)bundlePath
{
    return [self pathForResource: name
			  ofType: ext
                      inRootPath: bundlePath
		     inDirectory: nil
		     withVersion: 0];
}

- (NSString *) pathForResource: (NSString *)name
		ofType: (NSString *)ext;
{
  return [self pathForResource: name
	   ofType: ext 
	   inDirectory: nil];
}

- (NSString *) pathForResource: (NSString *)name
		ofType: (NSString *)ext
                inDirectory: (NSString *)bundlePath;
{
  return [NSBundle pathForResource: name
	   ofType: ext
	   inRootPath: [self bundlePath]
	   inDirectory: bundlePath
	   withVersion: _version];
}

- (NSArray *) pathsForResourcesOfType: (NSString *)extension
			  inDirectory: (NSString *)bundlePath
{
  BOOL allfiles;
  NSString *path;
  NSMutableArray *resources;
  NSEnumerator *pathlist;
  NSFileManager	*mgr = [NSFileManager defaultManager];
    
  pathlist = [[NSBundle _bundleResourcePathsWithRootPath: [self bundlePath]
	        subPath: bundlePath] objectEnumerator];
  resources = [NSMutableArray arrayWithCapacity: 2];
  allfiles = (extension == nil || [extension length] == 0);

  while((path = [pathlist nextObject]))
    {
      NSEnumerator *filelist;
      NSString *match;

      filelist = [[mgr directoryContentsAtPath: path] objectEnumerator];
      while ((match = [filelist nextObject]))
	{
	  if (allfiles || [extension isEqual: [match pathExtension]])
	    [resources addObject: [path stringByAppendingPathComponent: match]];
	}
    }

  return resources;
}

- (NSString *) localizedStringForKey: (NSString *)key	
			       value: (NSString *)value
			       table: (NSString *)tableName
{
  NSDictionary	*table;
  NSString	*newString;

  if (_localizations == nil)
    _localizations = [[NSMutableDictionary alloc] initWithCapacity: 1];

  if (tableName == nil || [tableName isEqualToString: @""] == YES)
    {
      tableName = @"Localizable";
      table = [_localizations objectForKey: tableName];
    }
  else if ((table = [_localizations objectForKey: tableName]) == nil
    && [@"strings" isEqual: [tableName pathExtension]] == YES)
    {
      tableName = [tableName stringByDeletingPathExtension];
      table = [_localizations objectForKey: tableName];
    }

  if (table == nil)
    {
      NSString			*tablePath;

      /*
       * Make sure we have an empty table in place in case anything
       * we do somehow causes recursion.  The recusive call will look
       * up the string in the empty table.
       */
      [_localizations setObject: _emptyTable forKey: tableName];

      tablePath = [self pathForResource: tableName ofType: @"strings"];
      if (tablePath)
	{
	  NSString	*tableContent;

	  tableContent = [NSString stringWithContentsOfFile: tablePath];
	  NS_DURING
	    {
	      table = [tableContent propertyListFromStringsFileFormat]; 
	    }
	  NS_HANDLER
	    {
	      NSLog(@"Failed to parse strings file %@ - %@",
			tablePath, localException);
	      table = nil;
	    }
	  NS_ENDHANDLER
	}
      else
	NSLog(@"Failed to locate strings file %@", tableName);
	
      /*
       * If we couldn't found and parsed the strings table, we put it in
       * the cache of strings tables in this bundle, otherwise we will just
       * be keeping the empty table in the cache so we don't keep retrying.
       */
      if (table != nil)
	[_localizations setObject: table forKey: tableName];
    }

  if (key == nil || (newString = [table objectForKey: key]) == nil)
    {
      NSString	*show = [[NSUserDefaults standardUserDefaults]
			 objectForKey: NSShowNonLocalizedStrings];
      if (show && [show isEqual: @"YES"])
        {
	  /* It would be bad to localize this string! */
	  NSLog(@"Non-localized string: %@\n", newString);
	  newString = [key uppercaseString];
	}
      else
	{
	  newString = value;
	  if (newString == nil || [newString isEqualToString: @""] == YES)
	    newString = key;
	}
      if (newString == nil)
	newString = @"";
    }
  
  return newString;
}

+ (void) stripAfterLoading: (BOOL)flag
{
  _strip_after_loading = flag;
}

- (NSString *) resourcePath
{
  return [_path stringByAppendingPathComponent: @"Resources"];
}

- (NSDictionary *) infoDictionary
{
  NSString* path;

  if (_infoDict)
    return _infoDict;

  path = [self pathForResource: @"Info-gnustep" ofType: @"plist"];
  if (path)
    _infoDict = [[NSDictionary alloc] initWithContentsOfFile: path];
  else
    {
      path = [self pathForResource: @"Info" ofType: @"plist"];
      if (path)
	_infoDict = [[NSDictionary alloc] initWithContentsOfFile: path];
      else
	_infoDict = RETAIN([NSDictionary dictionary]);
    }
  return _infoDict;
}

- (unsigned)bundleVersion
{
  return _version;
}

/* Since I don't know how version numbers should behave - the version
   number is not used. (FIXME)
*/
- (void)setBundleVersion:(unsigned)version
{
  _version = version;
}

@end

@implementation NSBundle (GNUstep)

/* These are convenience methods for searching for resource files
   within the GNUstep directory structure specified by the environment
   variables. */

+ (NSBundle *) gnustepBundle
{
  return _gnustep_bundle;
}

+ (NSString *) pathForGNUstepResource: (NSString *)name
			       ofType: (NSString *)ext	
			  inDirectory: (NSString *)bundlePath;
{
  NSString *path;
  NSBundle *user_bundle = nil, *local_bundle = nil;
  NSProcessInfo *pInfo;
  NSDictionary *env;
  NSMutableString *user, *local;

  /*
    The path of where to search for the resource files
    is based upon environment variables.
    GNUSTEP_USER_ROOT
    GNUSTEP_LOCAL_ROOT
    GNUSTEP_SYSTEM_ROOT
    */
  pInfo = [NSProcessInfo processInfo];
  env = [pInfo environment];
  user = AUTORELEASE([[env objectForKey: @"GNUSTEP_USER_ROOT"] mutableCopy]);
  [user appendString: @"/Libraries"];
  local = AUTORELEASE([[env objectForKey: @"GNUSTEP_LOCAL_ROOT"] mutableCopy]);
  [local appendString: @"/Libraries"];

  if (user)
    user_bundle = [NSBundle bundleWithPath: user];
  if (local)
    local_bundle = [NSBundle bundleWithPath: local];

  /* Gather up the paths */

  /* Search user first */
  path = [user_bundle pathForResource: name
			   ofType: ext
			   inDirectory: bundlePath];
  if (path)
    return path;

  /* Search local second */
  path = [local_bundle pathForResource: name
			     ofType: ext
			     inDirectory: bundlePath];
  if (path)
    return path;

  /* Search system last */
  path = [_gnustep_bundle pathForResource: name
			       ofType: ext
			       inDirectory: bundlePath];
  if (path)
    return path;

  /* Didn't find it */
  return nil;
}

+ (NSString*) _gnustep_target_cpu
{
  return gnustep_target_cpu;
}

+ (NSString*) _gnustep_target_dir
{
  return gnustep_target_dir;
}

+ (NSString*) _gnustep_target_os
{
  return gnustep_target_os;
}

+ (NSString*) _library_combo
{
  return library_combo;
}

@end

