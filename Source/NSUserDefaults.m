/** Implementation for NSUserDefaults for GNUstep
   Copyright (C) 1995-2001 Free Software Foundation, Inc.

   Written by:  Georg Tuparev <Tuparev@EMBL-Heidelberg.de>
   		EMBL & Academia Naturalis,
                Heidelberg, Germany
   Modified by:  Richard Frith-Macdonald <rfm@gnu.org>

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

   <title>NSUserDefaults class reference</title>
   $Date$ $Revision$
*/

#include "config.h"
#include "GNUstepBase/preface.h"
#include <sys/stat.h>
#include <sys/types.h>
#include <errno.h>

#include "Foundation/NSUserDefaults.h"
#include "Foundation/NSArchiver.h"
#include "Foundation/NSArray.h"
#include "Foundation/NSBundle.h"
#include "Foundation/NSDate.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSDistributedLock.h"
#include "Foundation/NSException.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSNotification.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSProcessInfo.h"
#include "Foundation/NSRunLoop.h"
#include "Foundation/NSSet.h"
#include "Foundation/NSThread.h"
#include "Foundation/NSTimer.h"
#include "Foundation/NSUtilities.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSDebug.h"
#include "GNUstepBase/GSLocale.h"
#ifdef HAVE_LOCALE_H
#include <locale.h>
#endif

#include "GSPrivate.h"

/* Wait for access */
#define _MAX_COUNT 5          /* Max 10 sec. */

/*************************************************************************
 *** Class variables
 *************************************************************************/
static SEL	nextObjectSel;
static SEL	objectForKeySel;
static SEL	addSel;

static Class	NSArrayClass;
static Class	NSDataClass;
static Class	NSDateClass;
static Class	NSDictionaryClass;
static Class	NSNumberClass;
static Class	NSMutableDictionaryClass;
static Class	NSStringClass;

static NSUserDefaults	*sharedDefaults = nil;
static NSMutableString	*processName = nil;
static NSMutableArray	*userLanguages = nil;
static NSRecursiveLock	*classLock = nil;

/*
 * Caching some defaults.
 */
static BOOL	flags[GSUserDefaultMaxFlag] = { 0 };

static void updateCache(NSUserDefaults *self)
{
  if (self == sharedDefaults)
    {
      NSArray	*debug;

      /**
       * If there is an array NSUserDefault called GNU-Debug,
       * we add its contents to the set of active debug levels.
       */
      debug = [self arrayForKey: @"GNU-Debug"];
      if (debug != nil)
        {
	  unsigned	c = [debug count];
	  NSMutableSet	*s;

	  s = [[NSProcessInfo processInfo] debugSet];
	  while (c-- > 0)
	    {
	      NSString	*level = [debug objectAtIndex: c];

	      [s addObject: level];
	    }
	}

      flags[GSMacOSXCompatible]
	= [self boolForKey: @"GSMacOSXCompatible"];
      flags[GSOldStyleGeometry]
	= [self boolForKey: @"GSOldStyleGeometry"];
      flags[GSLogSyslog]
	= [self boolForKey: @"GSLogSyslog"];
      flags[NSWriteOldStylePropertyLists]
	= [self boolForKey: @"NSWriteOldStylePropertyLists"];
    }
}

/*************************************************************************
 *** Local method definitions
 *************************************************************************/
@interface NSUserDefaults (__local_NSUserDefaults)
- (void) __createStandardSearchList;
- (NSDictionary*) __createArgumentDictionary;
- (void) __changePersistentDomain: (NSString*)domainName;
@end

/**
 * <p>
 *   NSUserDefaults provides an interface to the defaults system,
 *   which allows an application access to global and/or application
 *   specific defualts set by the user. A particular instance of
 *   NSUserDefaults, standardUserDefaults, is provided as a
 *   convenience. Most of the information described below
 *   pertains to the standardUserDefaults. It is unlikely
 *   that you would want to instantiate your own userDefaults
 *   object, since it would not be set up in the same way as the
 *   standardUserDefaults.
 * </p>
 * <p>
 *   Defaults are managed based on <em>domains</em>. Certain
 *   domains, such as <code>NSGlobalDomain</code>, are
 *   persistant. These domains have defaults that are stored
 *   externally. Other domains are volitale. The defaults in
 *   these domains remain in effect only during the existance of
 *   the application and may in fact be different for
 *   applications running at the same time. When asking for a
 *   default value from standardUserDefaults, NSUserDefaults
 *   looks through the various domains in a particular order.
 * </p>
 * <deflist>
 *   <term><code>NSArgumentDomain</code> ... volatile</term>
 *   <desc>
 *     Contains defaults read from the arguments provided
 *     to the application at startup.
 *   </desc>
 *   <term>Application (name of the current process) ... persistent</term>
 *   <desc>
 *     Contains application specific defaults,
 *     such as window positions.</desc>
 *   <term><code>NSGlobalDomain</code> ... persistent</term>
 *   <desc>
 *     Global defaults applicable to all applications.
 *   </desc>
 *   <term>Language (name based on users's language) ... volatile</term>
 *   <desc>
 *     Constants that help with localization to the users's
 *     language.
 *   </desc>
 *   <term><code>NSRegistrationDomain</code> ... volatile</term>
 *   <desc>
 *     Temporary defaults set up by the application.
 *   </desc>
 * </deflist>
 * <p>
 *   The <em>NSLanguages</em> default value is used to set up the
 *   constants for localization. GNUstep will also look for the
 *   <code>LANGUAGES</code> environment variable if it is not set
 *   in the defaults system. If it exists, it consists of an
 *   array of languages that the user prefers. At least one of
 *   the languages should have a corresponding localization file
 *   (typically located in the <file>Languages</file> directory
 *   of the GNUstep resources).
 * </p>
 * <p>
 *   As a special extension, on systems that support locales
 *   (e.g. GNU/Linux and Solaris), GNUstep will use information
 *   from the user specified locale, if the <em>NSLanguages</em>
 *   default value is not found. Typically the locale is
 *   specified in the environment with the <code>LANG</code>
 *   environment variable.
 * </p>
 * <p>
 *   The first change to a persistent domain after a -synchronize
 *   will cause an NSUserDefaultsDidChangeNotification to be posted
 *   (as will any change caused by reading new values from disk),
 *   so your application can keep track of changes made to the
 *   defaults by other software.
 * </p>
 * <p>
 *   NB. The GNUstep implementation differs from the Apple one in
 *   that it is thread-safe while Apples (as of MacOS-X 10.1) is not.
 * </p>
 */
@implementation NSUserDefaults: NSObject

static BOOL setSharedDefaults = NO;	/* Flag to prevent infinite recursion */

+ (void) initialize
{
  if (self == [NSUserDefaults class])
    {
      nextObjectSel = @selector(nextObject);
      objectForKeySel = @selector(objectForKey:);
      addSel = @selector(addEntriesFromDictionary:);
      /*
       * Cache class info for more rapid testing of the types of defaults.
       */
      NSArrayClass = [NSArray class];
      NSDataClass = [NSData class];
      NSDateClass = [NSDate class];
      NSDictionaryClass = [NSDictionary class];
      NSNumberClass = [NSNumber class];
      NSMutableDictionaryClass = [NSMutableDictionary class];
      NSStringClass = [NSString class];
      classLock = [NSRecursiveLock new];
    }
}

/**
 * Resets the shared user defaults object to reflect the current
 * user ID.  Needed by setuid processes which change the user they
 * are running as.<br />
 * In GNUstep you should call GSSetUserName() when changing your
 * effective user ID, and that class will call this function for you.
 */
+ (void) resetStandardUserDefaults
{
  [classLock lock];
  if (sharedDefaults != nil)
    {
      NSDictionary	*regDefs;

      [sharedDefaults synchronize];	// Ensure changes are written.
      regDefs = RETAIN([sharedDefaults->_tempDomains
	objectForKey: NSRegistrationDomain]);
      setSharedDefaults = NO;
      AUTORELEASE(sharedDefaults);	// Let tother threads keep it.
      sharedDefaults = nil;
      if (regDefs != nil)
	{
	  [self standardUserDefaults];
	  if (sharedDefaults != nil)
	    {
	      [sharedDefaults->_tempDomains setObject: regDefs
					       forKey: NSRegistrationDomain];
	    }
	  RELEASE(regDefs);
	}
    }
  [classLock unlock];
}

/* Create a locale dictionary when we have absolutely no information
   about the locale. This method should go away, since it will never
   be called in a properly installed system. */
+ (NSDictionary *) _unlocalizedDefaults
{
  NSDictionary   *registrationDefaults;
  NSArray	 *ampm;
  NSArray	 *long_day;
  NSArray	 *long_month;
  NSArray	 *short_day;
  NSArray	 *short_month;
  NSArray	 *earlyt;
  NSArray	 *latert;
  NSArray	 *hour_names;
  NSArray	 *ymw_names;

  ampm = [NSArray arrayWithObjects: @"AM", @"PM", nil];

  short_month = [NSArray arrayWithObjects:
    @"Jan",
    @"Feb",
    @"Mar",
    @"Apr",
    @"May",
    @"Jun",
    @"Jul",
    @"Aug",
    @"Sep",
    @"Oct",
    @"Nov",
    @"Dec",
    nil];

  long_month = [NSArray arrayWithObjects:
    @"January",
    @"February",
    @"March",
    @"April",
    @"May",
    @"June",
    @"July",
    @"August",
    @"September",
    @"October",
    @"November",
    @"December",
    nil];

  short_day = [NSArray arrayWithObjects:
    @"Sun",
    @"Mon",
    @"Tue",
    @"Wed",
    @"Thu",
    @"Fri",
    @"Sat",
    nil];

  long_day = [NSArray arrayWithObjects:
    @"Sunday",
    @"Monday",
    @"Tuesday",
    @"Wednesday",
    @"Thursday",
    @"Friday",
    @"Saturday",
    nil];

  earlyt = [NSArray arrayWithObjects:
    @"prior",
    @"last",
    @"past",
    @"ago",
    nil];

  latert = [NSArray arrayWithObjects: @"next", nil];

  ymw_names = [NSArray arrayWithObjects: @"year", @"month", @"week", nil];

  hour_names = [NSArray arrayWithObjects:
    [NSArray arrayWithObjects: @"0", @"midnight", nil],
    [NSArray arrayWithObjects: @"12", @"noon", @"lunch", nil],
    [NSArray arrayWithObjects: @"10", @"morning", nil],
    [NSArray arrayWithObjects: @"14", @"afternoon", nil],
    [NSArray arrayWithObjects: @"19", @"dinner", nil],
    nil];

  registrationDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
    ampm, NSAMPMDesignation,
    long_month, NSMonthNameArray,
    long_day, NSWeekDayNameArray,
    short_month, NSShortMonthNameArray,
    short_day, NSShortWeekDayNameArray,
    @"DMYH", NSDateTimeOrdering,
    [NSArray arrayWithObject: @"tomorrow"], NSNextDayDesignations,
    [NSArray arrayWithObject: @"nextday"], NSNextNextDayDesignations,
    [NSArray arrayWithObject: @"yesterday"], NSPriorDayDesignations,
    [NSArray arrayWithObject: @"today"], NSThisDayDesignations,
    earlyt, NSEarlierTimeDesignations,
    latert, NSLaterTimeDesignations,
    hour_names, NSHourNameDesignations,
    ymw_names, NSYearMonthWeekDesignations,
    nil];
  return registrationDefaults;
}

/**
 * Returns the shared defaults object. If it doesn't exist yet, it's
 * created. The defaults are initialized for the current user.
 * The search list is guaranteed to be standard only the first time
 * this method is invoked. The shared instance is provided as a
 * convenience; other instances may also be created.
 */
+ (NSUserDefaults*) standardUserDefaults
{
  BOOL added_locale, added_lang;
  id lang;
  NSArray *uL;
  NSEnumerator *enumerator;

  [classLock lock];
  if (setSharedDefaults)
    {
      RETAIN(sharedDefaults);
      [classLock unlock];
      return AUTORELEASE(sharedDefaults);
    }
  setSharedDefaults = YES;
  /*
   * Get the user languages *before* setting up sharedDefaults, to avoid
   * the userLanguages method trying to look up languages in a partially
   * constructed user defaults object.
   */
  uL = [[self class] userLanguages];
  // Create new sharedDefaults (NOTE: Not added to the autorelease pool!)
  sharedDefaults = [[self alloc] init];
  if (sharedDefaults == nil)
    {
      NSLog(@"WARNING - unable to create shared user defaults!\n");
      [classLock unlock];
      return nil;
    }

  [sharedDefaults __createStandardSearchList];

  /* Set up language constants */
  added_locale = NO;
  added_lang = NO;
  enumerator = [uL objectEnumerator];
  while ((lang = [enumerator nextObject]))
    {
      NSString *path;
      NSDictionary *dict;
      NSBundle *gbundle;
      gbundle = [NSBundle bundleForLibrary: @"gnustep-base"];
      path = [gbundle pathForResource: lang
		               ofType: nil
		          inDirectory: @"Languages"];
      dict = nil;
      if (path)
	dict = [NSDictionary dictionaryWithContentsOfFile: path];
      if (dict)
	{
	  [sharedDefaults setVolatileDomain: dict forName: lang];
	  added_lang = YES;
	}
      else if (added_locale == NO)
	{
	  NSString	*locale = nil;

#ifdef HAVE_LOCALE_H
#ifdef LC_MESSAGES
	  locale = GSSetLocale(LC_MESSAGES, nil);
#endif
#endif
	  if (locale == nil)
	    {
	      continue;
	    }
	  /* See if we can get the dictionary from i18n functions.
	     Note that we get the dict from the current locale regardless
	     of what 'lang' is, since it should match anyway. */
	  /* Also, I don't think that the i18n routines can handle more than
	     one locale, but tell me if I'm wrong... */
	  if (GSLanguageFromLocale(locale))
	    {
	      lang = GSLanguageFromLocale(locale);
	    }
	  dict = GSDomainFromDefaultLocale();
	  if (dict != nil)
	    {
	      [sharedDefaults setVolatileDomain: dict forName: lang];
	    }
	  added_locale = YES;
	}
    }
  if (added_lang == NO)
    {
      /* Ack! We should never get here */
      NSLog(@"Improper installation: No language locale found");
      [sharedDefaults registerDefaults: [self _unlocalizedDefaults]];
    }
  RETAIN(sharedDefaults);
  updateCache(sharedDefaults);
  [classLock unlock];
  return AUTORELEASE(sharedDefaults);
}

/**
 * Returns the array of user languages preferences.  Uses the
 * <em>NSLanguages</em> user default if available, otherwise
 * tries to infer setup from operating system information etc
 * (in particular, uses the <em>LANGUAGES</em> environment variable).
 */
+ (NSArray*) userLanguages
{
  NSArray	*currLang = nil;
  NSString	*locale = nil;

#ifdef HAVE_LOCALE_H
#ifdef LC_MESSAGES
  locale = GSSetLocale(LC_MESSAGES, nil);
#endif
#endif
  [classLock lock];
  if (userLanguages != nil)
    {
      RETAIN(userLanguages);
      [classLock unlock];
      return AUTORELEASE(userLanguages);
    }
  userLanguages = RETAIN([NSMutableArray arrayWithCapacity: 5]);
  if (sharedDefaults == nil)
    {
      /* Create our own defaults to get "NSLanguages" since sharedDefaults
	 depends on us */
      NSUserDefaults	*tempDefaults;

      tempDefaults = [[self alloc] init];
      if (tempDefaults != nil)
	{
	  NSMutableArray	*sList;

	  /*
	   * Can't use the standard method to set up a search list,
	   * it would cause mutual recursion as it includes languages.
	   */
	  sList = [[NSMutableArray alloc] initWithCapacity: 4];
	  [sList addObject: NSArgumentDomain];
	  [sList addObject: processName];
	  [sList addObject: NSGlobalDomain];
	  [sList addObject: NSRegistrationDomain];
	  [tempDefaults setSearchList: sList];
	  RELEASE(sList);
	  currLang = [tempDefaults stringArrayForKey: @"NSLanguages"];
	  AUTORELEASE(RETAIN(currLang));
	  RELEASE(tempDefaults);
	}
    }
  else
    {
      currLang
	= [[self standardUserDefaults] stringArrayForKey: @"NSLanguages"];
    }
  if (currLang == nil && locale != nil && GSLanguageFromLocale(locale))
    {
      currLang = [NSArray arrayWithObject: GSLanguageFromLocale(locale)];
    }
#ifdef __MINGW__
  if (currLang == nil && locale != nil)
    {
      /* Check for language as the first part of the locale string */
      NSRange under = [locale rangeOfString: @"_"];
      if (under.location)
        currLang = [NSArray arrayWithObject:
	             [locale substringToIndex: under.location]];
    }
#endif
  if (currLang == nil)
    {
      const char	*env_list;
      NSString		*env;

      env_list = getenv("LANGUAGES");
      if (env_list != 0)
	{
	  env = [NSStringClass stringWithCString: env_list];
	  currLang = [env componentsSeparatedByString: @";"];
	}
    }

  if (currLang != nil)
    {
      if ([currLang containsObject: @""] == YES)
	{
	  NSMutableArray	*a = [currLang mutableCopy];

	  [a removeObject: @""];
	  currLang = (NSArray*)AUTORELEASE(a);
	}
      [userLanguages addObjectsFromArray: currLang];
    }

  /* Check if "English" is included. We do this to make sure all the
     required language constants are set somewhere if they aren't set
     in the default language */
  if ([userLanguages containsObject: @"English"] == NO)
    {
      [userLanguages addObject: @"English"];
    }
  RETAIN(userLanguages);
  [classLock unlock];
  return AUTORELEASE(userLanguages);
}

/**
 * Sets the array of user languages preferences.  Places the specified
 * array in the <em>NSLanguages</em> user default.
 */
+ (void) setUserLanguages: (NSArray*)languages
{
  NSMutableDictionary	*globDict;

  globDict = [[[self standardUserDefaults]
    persistentDomainForName: NSGlobalDomain] mutableCopy];
  if (languages == nil)          // Remove the entry
    [globDict removeObjectForKey: @"NSLanguages"];
  else
    [globDict setObject: languages forKey: @"NSLanguages"];
  [[self standardUserDefaults]
    setPersistentDomain: globDict forName: NSGlobalDomain];
  RELEASE(globDict);
}

/*************************************************************************
 *** Initializing the User Defaults
 *************************************************************************/
/**
 * Initializes defaults for current user calling initWithUser:
 */
- (id) init
{
  return [self initWithUser: NSUserName()];
}

static NSString	*pathForUser(NSString *user)
{
  NSString	*database = @".GNUstepDefaults";
  NSFileManager	*mgr = [NSFileManager defaultManager];
  NSString	*home;
  NSString	*path;
  NSString	*old;
  unsigned	desired;
  NSDictionary	*attr;
  BOOL		isDir;

  home = GSDefaultsRootForUser(user);
  if (home == nil)
    {
      /* Probably on MINGW. Where to put it? */
      NSLog(@"Could not get user root. Using NSOpenStepRootDirectory()");
      home = NSOpenStepRootDirectory();
    }
  path = [home stringByAppendingPathComponent: @"Defaults"];

#if	!(defined(S_IRUSR) && defined(S_IWUSR) && defined(S_IXUSR) \
  && defined(S_IRGRP) && defined(S_IXGRP) \
  && defined(S_IROTH) && defined(S_IXOTH))
  desired = 0755;
#else
  desired = (S_IRUSR|S_IWUSR|S_IXUSR|S_IRGRP|S_IXGRP|S_IROTH|S_IXOTH);
#endif
  attr = [NSDictionary dictionaryWithObjectsAndKeys:
    NSUserName(), NSFileOwnerAccountName,
    [NSNumberClass numberWithUnsignedLong: desired], NSFilePosixPermissions,
    nil];

  if ([mgr fileExistsAtPath: home isDirectory: &isDir] == NO)
    {
      if ([mgr createDirectoryAtPath: home attributes: attr] == NO)
	{
	  NSLog(@"Defaults home '%@' does not exist - failed to create it.",
	    home);
	  return nil;
	}
      else
	{
	  NSLog(@"Defaults home '%@' did not exist - created it", home);
	  isDir = YES;
	}
    }
  if (isDir == NO)
    {
      NSLog(@"ERROR - defaults home '%@' is not a directory!", home);
      return nil;
    }

  if ([mgr fileExistsAtPath: path isDirectory: &isDir] == NO)
    {
      if ([mgr createDirectoryAtPath: path attributes: attr] == NO)
	{
	  NSLog(@"Defaults path '%@' does not exist - failed to create it.",
	    path);
	  return nil;
	}
      else
	{
	  NSLog(@"Defaults path '%@' did not exist - created it", path);
	  isDir = YES;
	}
    }
  if (isDir == NO)
    {
      NSLog(@"ERROR - Defaults path '%@' is not a directory!", path);
      return nil;
    }

  path = [path stringByAppendingPathComponent: database];
  old = [home stringByAppendingPathComponent: database];
  if ([mgr fileExistsAtPath: path] == NO)
    {
      if ([mgr fileExistsAtPath: old] == YES)
	{
	  if ([mgr movePath: old toPath: path handler: nil] == YES)
	    {
	      NSLog(@"Moved defaults database from old location (%@) to %@",
		old, path);
	    }
	}
    }
  if ([mgr fileExistsAtPath: old] == YES)
    {
      NSLog(@"Warning - ignoring old defaults database in %@", old);
    }

  /*
   * Try to create standard directory hierarchy if necessary
   */
  home = [NSSearchPathForDirectoriesInDomains(NSUserDirectory,
    NSUserDomainMask, YES) lastObject];
  if (home != nil)
    {
      NSString	*p;

      p = [home stringByAppendingPathComponent: @"Library"];
      if ([mgr fileExistsAtPath: p isDirectory: &isDir] == NO)
	{
	  [mgr createDirectoryAtPath: p attributes: attr];
	}
    }

  return path;
}

/**
 * Initializes defaults for the specified user calling -initWithContentsOfFile:
 */
- (id) initWithUser: (NSString*)userName
{
  NSString	*path = pathForUser(userName);

  if (path == nil)
    {
      RELEASE(self);
      return nil;
    }
  return [self initWithContentsOfFile: path];
}

/**
 * <init />
 * Initializes defaults for the specified path. Returns an object with
 * an empty search list.
 */
- (id) initWithContentsOfFile: (NSString*)path
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  BOOL		flag;

  self = [super init];

  /*
   * Global variable.
   */
  if (processName == nil)
    {
      processName = RETAIN([[NSProcessInfo processInfo] processName]);
    }

  if (path == nil || [path isEqual: @""] == YES)
    {
      path = pathForUser(NSUserName());
    }
  path = [path stringByStandardizingPath];
  _defaultsDatabase = [path copy];
  path = [path stringByDeletingLastPathComponent];
  if ([mgr isWritableFileAtPath: path] == NO)
    {
      NSWarnMLog(@"Path '%@' is not writable - making user defaults for '%@' "
	@" read-only\n", path, _defaultsDatabase);
    }
  else if ([mgr fileExistsAtPath: path isDirectory: &flag] == NO && flag == NO)
    {
      NSWarnMLog(@"Path '%@' is not an accessible directory - making user "
	@"defaults for '%@' read-only\n", path, _defaultsDatabase);
    }
  else if ([mgr fileExistsAtPath: _defaultsDatabase] == YES
    && [mgr isReadableFileAtPath: _defaultsDatabase] == NO)
    {
      NSWarnMLog(@"Path '%@' is not readable - making user defaults blank\n",
	_defaultsDatabase);
    }
  else
    {
      /*
       * Only create the file lock if we can update the file ...
       * if we can't the absence of the lock tells us we must be
       * in read-only mode.
       */
      _fileLock = [[NSDistributedLock alloc] initWithPath:
	[_defaultsDatabase stringByAppendingPathExtension: @"lck"]];
    }
  _lock = [NSRecursiveLock new];

  // Create an empty search list
  _searchList = [[NSMutableArray alloc] initWithCapacity: 10];

  // Initialize _persDomains from the archived user defaults (persistent)
  _persDomains = [[NSMutableDictionaryClass alloc] initWithCapacity: 10];
  if ([self synchronize] == NO)
    {
      DESTROY(self);
      return self;
    }

  // Check and if not existent add the Application and the Global domains
  if (![_persDomains objectForKey: processName])
    {
      [_persDomains
	setObject: [NSMutableDictionaryClass dictionaryWithCapacity: 10]
	forKey: processName];
      [self __changePersistentDomain: processName];
    }
  if (![_persDomains objectForKey: NSGlobalDomain])
    {
      [_persDomains
	setObject: [NSMutableDictionaryClass dictionaryWithCapacity: 10]
	forKey: NSGlobalDomain];
      [self __changePersistentDomain: NSGlobalDomain];
    }

  // Create volatile defaults and add the Argument and the Registration domains
  _tempDomains = [[NSMutableDictionaryClass alloc] initWithCapacity: 10];
  [_tempDomains setObject: [self __createArgumentDictionary]
		   forKey: NSArgumentDomain];
  [_tempDomains
    setObject: [NSMutableDictionaryClass dictionaryWithCapacity: 10]
    forKey: NSRegistrationDomain];

  [[NSNotificationCenter defaultCenter] addObserver: self
           selector: @selector(synchronize)
               name: @"GSHousekeeping"
             object: nil];

  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  RELEASE(_lastSync);
  RELEASE(_searchList);
  RELEASE(_persDomains);
  RELEASE(_tempDomains);
  RELEASE(_changedDomains);
  RELEASE(_dictionaryRep);
  RELEASE(_fileLock);
  RELEASE(_lock);
  [super dealloc];
}

- (NSString*) description
{
  NSMutableString *desc;

  [_lock lock];
  desc = [NSMutableString stringWithFormat: @"%@", [super description]];
  [desc appendFormat: @" SearchList: %@", _searchList];
  [desc appendFormat: @" Persistant: %@", _persDomains];
  [desc appendFormat: @" Temporary: %@", _tempDomains];
  [_lock unlock];
  return desc;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is an NSArray object.  Returns nil if it is not.
 */
- (NSArray*) arrayForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && [obj isKindOfClass: NSArrayClass])
    return obj;
  return nil;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and returns its boolean representation.<br />
 * Returns NO if it is not a boolean.<br />
 * The text 'yes' or 'true' or any non zero numeric value is considered
 * to be a boolean YES.  Other string values are NO.<br />
 * NB. This differs slightly from the documented behavior for MacOS-X
 * (August 2002) in that the GNUstep version accepts the string 'TRUE'
 * as equivalent to 'YES'.
 */
- (BOOL) boolForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && ([obj isKindOfClass: NSStringClass]
    || [obj isKindOfClass: NSNumberClass]))
    {
      return [obj boolValue];
    }
  return NO;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is an NSData object.  Returns nil if it is not.
 */
- (NSData*) dataForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && [obj isKindOfClass: NSDataClass])
    return obj;
  return nil;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is an NSDictionary object.  Returns nil if it is not.
 */
- (NSDictionary*) dictionaryForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && [obj isKindOfClass: NSDictionaryClass])
    {
      return obj;
    }
  return nil;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is a float.  Returns 0.0 if it is not.
 */
- (float) floatForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && ([obj isKindOfClass: NSStringClass]
    || [obj isKindOfClass: NSNumberClass]))
    {
      return [obj floatValue];
    }
  return 0.0;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is an integer.  Returns 0 if it is not.
 */
- (int) integerForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && ([obj isKindOfClass: NSStringClass]
    || [obj isKindOfClass: NSNumberClass]))
    {
      return [obj intValue];
    }
  return 0;
}

/**
 * Looks up a value for a specified default using.
 * The lookup is performed by accessing the domains in the order
 * given in the search list.
 * <br />Returns nil if defaultName cannot be found.
 */
- (id) objectForKey: (NSString*)defaultName
{
  NSEnumerator	*enumerator;
  IMP		nImp;
  id		object;
  id		dN;
  IMP		pImp;
  IMP		tImp;

  [_lock lock];
  enumerator = [_searchList objectEnumerator];
  nImp = [enumerator methodForSelector: nextObjectSel];
  object = nil;
  pImp = [_persDomains methodForSelector: objectForKeySel];
  tImp = [_tempDomains methodForSelector: objectForKeySel];

  while ((dN = (*nImp)(enumerator, nextObjectSel)) != nil)
    {
      id	dict;

      dict = (*pImp)(_persDomains, objectForKeySel, dN);
      if (dict != nil && (object = [dict objectForKey: defaultName]))
	break;
      dict = (*tImp)(_tempDomains, objectForKeySel, dN);
      if (dict != nil && (object = [dict objectForKey: defaultName]))
	break;
    }
  RETAIN(object);
  [_lock unlock];
  return AUTORELEASE(object);
}

/**
 * Removes the default with the specified name from the application
 * domain.
 */
- (void) removeObjectForKey: (NSString*)defaultName
{
  id	obj;

  [_lock lock];
  obj = [[_persDomains objectForKey: processName] objectForKey: defaultName];
  if (obj != nil)
    {
      NSMutableDictionary	*dict;
      id			obj = [_persDomains objectForKey: processName];

      if ([obj isKindOfClass: NSMutableDictionaryClass] == YES)
	{
	  dict = obj;
	}
      else
	{
	  dict = [obj mutableCopy];
	  [_persDomains setObject: dict forKey: processName];
	}
      [dict removeObjectForKey: defaultName];
      [self __changePersistentDomain: processName];
    }
  [_lock unlock];
}

/**
 * Sets a boolean value for defaultName in the application domain.<br />
 * The boolean value is stored as a string - either YES or NO.
 * Calls -setObject:forKey: to make the change.
 */
- (void) setBool: (BOOL)value forKey: (NSString*)defaultName
{
  NSNumber	*n = [NSNumberClass numberWithBool: value];

  [self setObject: n forKey: defaultName];
}

/**
 * Sets a float value for defaultName in the application domain.
 * <br />Calls -setObject:forKey: to make the change.
 */
- (void) setFloat: (float)value forKey: (NSString*)defaultName
{
  NSNumber	*n = [NSNumberClass numberWithFloat: value];

  [self setObject: n forKey: defaultName];
}

/**
 * Sets an integer value for defaultName in the application domain.
 * <br />Calls -setObject:forKey: to make the change.
 */
- (void) setInteger: (int)value forKey: (NSString*)defaultName
{
  NSNumber	*n = [NSNumberClass numberWithInt: value];

  [self setObject: n forKey: defaultName];
}

static BOOL isPlistObject(id o)
{
  if ([o isKindOfClass: NSStringClass] == YES)
    {
      return YES;
    }
  if ([o isKindOfClass: NSDataClass] == YES)
    {
      return YES;
    }
  if ([o isKindOfClass: NSDateClass] == YES)
    {
      return YES;
    }
  if ([o isKindOfClass: NSNumberClass] == YES)
    {
      return YES;
    }
  if ([o isKindOfClass: NSArrayClass] == YES)
    {
      NSEnumerator	*e = [o objectEnumerator];
      id		tmp;

      while ((tmp = [e nextObject]) != nil)
	{
	  if (isPlistObject(tmp) == NO)
	    {
	      return NO;
	    }
	}
      return YES;
    }
  if ([o isKindOfClass: NSDictionaryClass] == YES)
    {
      NSEnumerator	*e = [o keyEnumerator];
      id		tmp;

      while ((tmp = [e nextObject]) != nil)
	{
	  if (isPlistObject(tmp) == NO)
	    {
	      return NO;
	    }
	  tmp = [o objectForKey: tmp];
	  if (isPlistObject(tmp) == NO)
	    {
	      return NO;
	    }
	}
      return YES;
    }
  return NO;
}

/**
 * Sets an object value for defaultName in the application domain.<br />
 * The defaultName must be a non-empty string.<br />
 * The value must be an instance of one of the [NSString-propertyList]
 * classes.<br />
 * <p>Causes a NSUserDefaultsDidChangeNotification to be posted
 * if this is the first change to a persistent-domain since the
 * last -synchronize.
 * </p>
 */
- (void) setObject: (id)value forKey: (NSString*)defaultName
{
  NSMutableDictionary	*dict;
  id			obj;

  if ([defaultName isKindOfClass: [NSString class]] == NO
    || [defaultName length] == 0)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"attempt to set object with bad key (%@)", defaultName];
    }
  if (value == nil)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"attempt to set nil object for key (%@)", defaultName];
    }
  if (isPlistObject(value) == NO)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"attempt to set non property list object for key (%@)",
	defaultName];
    }

  [_lock lock];
  obj = [_persDomains objectForKey: processName];
  if ([obj isKindOfClass: NSMutableDictionaryClass] == YES)
    {
      dict = obj;
    }
  else
    {
      dict = [obj mutableCopy];
      [_persDomains setObject: dict forKey: processName];
      RELEASE(dict);
    }
  [dict setObject: value forKey: defaultName];
  [self __changePersistentDomain: processName];
  [_lock unlock];
}

/**
 * Calls -arrayForKey: to get an array value for defaultName and checks
 * that the array contents are string objects ... if not, returns nil.
 */
- (NSArray*) stringArrayForKey: (NSString*)defaultName
{
  id	arr = [self arrayForKey: defaultName];

  if (arr != nil)
    {
      NSEnumerator	*enumerator = [arr objectEnumerator];
      id		obj;

      while ((obj = [enumerator nextObject]))
	{
	  if ([obj isKindOfClass: NSStringClass] == NO)
	    {
	      return nil;
	    }
	}
      return arr;
    }
  return nil;
}

/**
 * Looks up a value for a specified default using -objectForKey:
 * and checks that it is an NSString.  Returns nil if it is not.
 */
- (NSString*) stringForKey: (NSString*)defaultName
{
  id	obj = [self objectForKey: defaultName];

  if (obj != nil && [obj isKindOfClass: NSStringClass])
    return obj;
  return nil;
}

/*************************************************************************
 *** Returning the Search List
 *************************************************************************/

/**
 * Returns an array listing the domains searched in order to look up
 * a value in the defaults system.  The order of the names in the
 * array is the order in which the domains are searched.
 */
- (NSArray*) searchList
{
  NSArray	*copy;

  [_lock lock];
  copy = [_searchList copy];
  [_lock unlock];
  return AUTORELEASE(copy);
}

/**
 * Sets the list of the domains searched in order to look up
 * a value in the defaults system.  The order of the names in the
 * array is the order in which the domains are searched.<br />
 * On lookup, the first match is used.
 */
- (void) setSearchList: (NSArray*)newList
{
  [_lock lock];
  DESTROY(_dictionaryRep);
  RELEASE(_searchList);
  _searchList = [newList mutableCopy];
  [_lock unlock];
}

/**
 * Returns the persistent domain specified by domainName.
 */
- (NSDictionary*) persistentDomainForName: (NSString*)domainName
{
  NSDictionary	*copy;

  [_lock lock];
  copy = [[_persDomains objectForKey: domainName] copy];
  [_lock unlock];
  return AUTORELEASE(copy);
}

/**
 * Returns an array listing the name of all the persistent domains.
 */
- (NSArray*) persistentDomainNames
{
  NSArray	*keys;

  [_lock lock];
  keys = [_persDomains allKeys];
  [_lock unlock];
  return keys;
}

/**
 * Removes the persistent domain specified by domainName from the
 * user defaults.
 * <br />Causes a NSUserDefaultsDidChangeNotification to be posted
 * if this is the first change to a persistent-domain since the
 * last -synchronize.
 */
- (void) removePersistentDomainForName: (NSString*)domainName
{
  [_lock lock];
  if ([_persDomains objectForKey: domainName])
    {
      [_persDomains removeObjectForKey: domainName];
      [self __changePersistentDomain: domainName];
    }
  [_lock unlock];
}

/**
 * Replaces the persistent-domain specified by domainName with
 * domain ... a dictionary containing keys and defaults values.
 * <br />Raises an NSInvalidArgumentException if domainName already
 * exists as a volatile-domain.
 * <br />Causes a NSUserDefaultsDidChangeNotification to be posted
 * if this is the first change to a persistent-domain since the
 * last -synchronize.
 */
- (void) setPersistentDomain: (NSDictionary*)domain
		     forName: (NSString*)domainName
{
  NSDictionary	*dict;

  [_lock lock];
  dict = [_tempDomains objectForKey: domainName];
  if (dict != nil)
    {
      [_lock unlock];
      [NSException raise: NSInvalidArgumentException
		  format: @"a volatile domain called %@ exists", domainName];
    }
  domain = [domain mutableCopy];
  [_persDomains setObject: domain forKey: domainName];
  RELEASE(domain);
  [self __changePersistentDomain: domainName];
  [_lock unlock];
}

/**
 * Ensures that the in-memory and on-disk representations of the defaults
 * are in sync.  You may call this yourself, but probably don't need to
 * since it is invoked at intervals whenever a runloop is running.<br />
 * If any persistent domain is changed by reading new values from disk,
 * an NSUserDefaultsDidChangeNotification is posted.
 */
- (BOOL) synchronize
{
  NSFileManager		*mgr = [NSFileManager defaultManager];
  NSMutableDictionary	*newDict;
  NSDictionary		*attr;
  NSDate		*started = [NSDateClass date];
  unsigned long		desired;
  unsigned long		attributes;
  static BOOL		isLocked = NO;
  BOOL			wasLocked;

  [_lock lock];

  wasLocked = isLocked;
  if (isLocked == NO && _fileLock != nil)
    {
      while ([_fileLock tryLock] == NO)
	{
	  CREATE_AUTORELEASE_POOL(arp);
	  NSDate	*when;
	  NSDate	*lockDate;

	  lockDate = [_fileLock lockDate];
	  when = [NSDateClass dateWithTimeIntervalSinceNow: 0.1];

	  /*
	   * In case we have tried and failed to break the lock,
	   * we give up after a while ... 16 seconds should give
	   * us three lock breaks if we do them at 5 second
	   * intervals.
	   */
	  if ([when timeIntervalSinceDate: started] > 16.0)
	    {
	      NSLog(@"Failed to lock user defaults database even after "
		@"breaking old locks!");
	      [_lock unlock];
	      return NO;
	    }

	  /*
	   * If lockDate is nil, we should be able to lock again ... but we
	   * wait a little anyway ... so that in the case of a locking
	   * problem we do an idle wait rather than a busy one.
	   */ 
	  if (lockDate != nil && [when timeIntervalSinceDate: lockDate] > 5.0)
	    {
	      [_fileLock breakLock];
	    }
	  else
	    {
	      [NSThread sleepUntilDate: when];
	    }
	  RELEASE(arp);
	}
      isLocked = YES;
    }

  /*
   *	If we haven't changed anything, we only need to synchronise if
   *	the on-disk database has been changed by someone else.
   */
  attr = [mgr fileAttributesAtPath: _defaultsDatabase
		      traverseLink: YES];
  if (_changedDomains == nil)
    {
      BOOL		wantRead = NO;

      if (_lastSync == nil)
	{
	  wantRead = YES;
	}
      else
	{
	  if (attr == nil)
	    {
	      wantRead = YES;
	    }
	  else
	    {
	      NSDate	*mod;

	      /*
	       * If the database was modified since the last synchronisation
	       * we need to read it.
	       */
	      mod = [attr objectForKey: NSFileModificationDate];
	      if (mod != nil && [_lastSync laterDate: mod] != _lastSync)
		{
		  wantRead = YES;
		}
	    }
	}
      if (wantRead == NO)
	{
	  if (wasLocked == NO)
	    {
	      [_fileLock unlock];
	      isLocked = NO;
	    }
	  [_lock unlock];
	  return YES;
	}
    }

  DESTROY(_dictionaryRep);

  // Read the persistent data from the stored database
  if (attr == nil)
    {
      newDict = [[NSMutableDictionaryClass allocWithZone: [self zone]]
	initWithCapacity: 1];
      if (_fileLock != nil)
	{
	  NSLog(@"Creating defaults database file %@", _defaultsDatabase);
	  [newDict writeToFile: _defaultsDatabase atomically: YES];
	  attr = [mgr fileAttributesAtPath: _defaultsDatabase
			      traverseLink: YES];
	}
    }
  else
    {
      newDict = [[NSMutableDictionaryClass allocWithZone: [self zone]]
        initWithContentsOfFile: _defaultsDatabase];
      if (newDict == nil)
	{
	  NSLog(@"Unable to load defaults from '%@'", _defaultsDatabase);
	  if (wasLocked == NO)
	    {
	      [_fileLock unlock];
	      isLocked = NO;
	    }
	  [_lock unlock];
	  return NO;
	}
    }

  /*
   * We enforce the permission mode 0600 on the defaults database
   */
  attributes = [attr filePosixPermissions];
#if	!(defined(S_IRUSR) && defined(S_IWUSR))
  desired = 0600;
#else
  desired = (S_IRUSR|S_IWUSR);
#endif
  if (attributes != desired)
    {
      NSMutableDictionary	*enforced_attributes;
      NSNumber			*permissions;

      enforced_attributes = [NSMutableDictionary dictionaryWithDictionary:
	[mgr fileAttributesAtPath: _defaultsDatabase traverseLink: YES]];

      permissions = [NSNumberClass numberWithUnsignedLong: desired];
      [enforced_attributes setObject: permissions
			      forKey: NSFilePosixPermissions];

      [mgr changeFileAttributes: enforced_attributes
			 atPath: _defaultsDatabase];
    }

  if (_changedDomains != nil)
    {           // Synchronize both dictionaries
      NSEnumerator	*enumerator = [_changedDomains objectEnumerator];
      NSString		*domainName;
      NSDictionary	*domain;

      DESTROY(_changedDomains);	// Retained by enumerator.
      while ((domainName = [enumerator nextObject]) != nil)
	{
	  domain = [_persDomains objectForKey: domainName];
	  if (domain != nil)	// Domain was added or changed
	    {
	      [newDict setObject: domain forKey: domainName];
	    }
	  else			// Domain was removed
	    {
	      [newDict removeObjectForKey: domainName];
	    }
	}
      RELEASE(_persDomains);
      _persDomains = newDict;
      // Save the changes unless we are in read-only mode.
      if (_fileLock != nil)
	{
	  if (![_persDomains writeToFile: _defaultsDatabase atomically: YES])
	    {
	      if (wasLocked == NO)
		{
		  [_fileLock unlock];
		  isLocked = NO;
		}
	      [_lock unlock];
	      return NO;
	    }
	}
      ASSIGN(_lastSync, [NSDateClass date]);
    }
  else
    {
      ASSIGN(_lastSync, [NSDateClass date]);
      if ([_persDomains isEqual: newDict] == NO)
	{
	  RELEASE(_persDomains);
	  _persDomains = newDict;
	  updateCache(self);
	  [[NSNotificationCenter defaultCenter]
	    postNotificationName: NSUserDefaultsDidChangeNotification
			  object: self];
	}
      else
	{
	  RELEASE(newDict);
	}
    }

  if (wasLocked == NO)
    {
      [_fileLock unlock];
      isLocked = NO;
    }
  [_lock unlock];
  return YES;
}


/**
 * Removes the volatile domain specified by domainName from the
 * user defaults.
 */
- (void) removeVolatileDomainForName: (NSString*)domainName
{
  [_lock lock];
  DESTROY(_dictionaryRep);
  [_tempDomains removeObjectForKey: domainName];
  [_lock unlock];
}

/**
 * Sets the volatile-domain specified by domainName to
 * domain ... a dictionary containing keys and defaults values.<br />
 * Raises an NSInvalidArgumentException if domainName already
 * exists as either a volatile-domain or a persistent-domain.
 */
- (void) setVolatileDomain: (NSDictionary*)domain
		   forName: (NSString*)domainName
{
  id	dict;

  [_lock lock];
  dict = [_persDomains objectForKey: domainName];
  if (dict != nil)
    {
      [_lock unlock];
      [NSException raise: NSInvalidArgumentException
		  format: @"a persistent domain called %@ exists", domainName];
    }
  dict = [_tempDomains objectForKey: domainName];
  if (dict != nil)
    {
      [_lock unlock];
      [NSException raise: NSInvalidArgumentException
		  format: @"the volatile domain %@ already exists", domainName];
    }

  DESTROY(_dictionaryRep);
  domain = [domain mutableCopy];
  [_tempDomains setObject: domain forKey: domainName];
  RELEASE(domain);
  [_lock unlock];
}

/**
 * Returns the volatile domain specified by domainName.
 */
- (NSDictionary*) volatileDomainForName: (NSString*)domainName
{
  NSDictionary	*copy;

  [_lock lock];
  copy = [[_tempDomains objectForKey: domainName] copy];
  [_lock unlock];
  return AUTORELEASE(copy);
}

/**
 * Returns an array listing the name of all the volatile domains.
 */
- (NSArray*) volatileDomainNames
{
  NSArray	*keys;

  [_lock lock];
  keys = [_tempDomains allKeys];
  [_lock unlock];
  return keys;
}

/**
 * Returns a dictionary representing the current state of the defaults
 * system ... this is a merged version of all the domains in the
 * search list.
 */
- (NSDictionary*) dictionaryRepresentation
{
  NSDictionary	*rep;

  [_lock lock];
  if (_dictionaryRep == nil)
    {
      NSEnumerator		*enumerator;
      NSMutableDictionary	*dictRep;
      id			obj;
      id			dict;
      IMP			nImp;
      IMP			pImp;
      IMP			tImp;
      IMP			addImp;

      pImp = [_persDomains methodForSelector: objectForKeySel];
      tImp = [_tempDomains methodForSelector: objectForKeySel];

      enumerator = [_searchList reverseObjectEnumerator];
      nImp = [enumerator methodForSelector: nextObjectSel];

      dictRep = [NSMutableDictionaryClass allocWithZone: NSDefaultMallocZone()];
      dictRep = [dictRep initWithCapacity: 512];
      addImp = [dictRep methodForSelector: addSel];

      while ((obj = (*nImp)(enumerator, nextObjectSel)) != nil)
	{
	  if ( (dict = (*pImp)(_persDomains, objectForKeySel, obj)) != nil
	    || (dict = (*tImp)(_tempDomains, objectForKeySel, obj)) != nil)
	    (*addImp)(dictRep, addSel, dict);
	}
      _dictionaryRep = [dictRep copy];
      RELEASE(dictRep);
    }
  rep = RETAIN(_dictionaryRep);
  [_lock unlock];
  return AUTORELEASE(rep);
}

/**
 * Merges the contents of the dictionary newVals into the registration
 * domain.  Registration defaults may be added to or replaced using this
 * method, but may never be removed.  Thus, setting registration defaults
 * at any point in your program guarantees that the defaults will be
 * available thereafter.
 */
- (void) registerDefaults: (NSDictionary*)newVals
{
  NSMutableDictionary	*regDefs;

  [_lock lock];
  regDefs = [_tempDomains objectForKey: NSRegistrationDomain];
  if (regDefs == nil)
    {
      regDefs = [NSMutableDictionaryClass
	dictionaryWithCapacity: [newVals count]];
      [_tempDomains setObject: regDefs forKey: NSRegistrationDomain];
    }
  DESTROY(_dictionaryRep);
  [regDefs addEntriesFromDictionary: newVals];
  [_lock unlock];
}

/*************************************************************************
 *** Accessing the User Defaults database
 *************************************************************************/
- (void) __createStandardSearchList
{
  NSArray	*uL;
  NSEnumerator	*enumerator;
  id		object;

  [_lock lock];
  // Note: The search list should exist!

  // 1. NSArgumentDomain
  [_searchList addObject: NSArgumentDomain];

  // 2. Application
  [_searchList addObject: processName];

  // 3. NSGlobalDomain
  [_searchList addObject: NSGlobalDomain];

  // 4. User's preferred languages
  uL = [[self class] userLanguages];
  enumerator = [uL objectEnumerator];
  while ((object = [enumerator nextObject]))
    {
      [_searchList addObject: object];
    }

  // 5. NSRegistrationDomain
  [_searchList addObject: NSRegistrationDomain];

  [_lock unlock];
}

- (NSDictionary*) __createArgumentDictionary
{
  NSArray	*args;
  NSEnumerator	*enumerator;
  NSMutableDictionary *argDict;
  BOOL		done;
  id		key, val;

  [_lock lock];
  args = [[NSProcessInfo processInfo] arguments];
  enumerator = [args objectEnumerator];
  argDict = [NSMutableDictionaryClass dictionaryWithCapacity: 2];
  [enumerator nextObject];	// Skip process name.
  done = ((key = [enumerator nextObject]) == nil);

  while (!done)
    {
      if ([key hasPrefix: @"-"] == YES && [key isEqual: @"-"] == NO)
	{
	  NSString	*old = nil;

	  /* anything beginning with a '-' is a defaults key and we must strip
	      the '-' from it.  As a special case, we leave the '- in place
	      for '-GS...' and '--GS...' for backward compatibility. */
	  if ([key hasPrefix: @"-GS"] == YES || [key hasPrefix: @"--GS"] == YES)
	    {
	      old = key;
	    }
	  key = [key substringFromIndex: 1];
	  val = [enumerator nextObject];
	  if (val == nil)
	    {            // No more args
	      [argDict setObject: @"" forKey: key];		// arg is empty.
	      if (old != nil)
		{
		  [argDict setObject: @"" forKey: old];
		}
	      done = YES;
	      continue;
	    }
	  else if ([val hasPrefix: @"-"] == YES && [val isEqual: @"-"] == NO)
	    {  // Yet another argument
	      [argDict setObject: @"" forKey: key];		// arg is empty.
	      if (old != nil)
		{
		  [argDict setObject: @"" forKey: old];
		}
	      key = val;
	      continue;
	    }
	  else
	    {                            // Real parameter
	      /* Parsing the argument as a property list is very
		 delicate.  We *MUST NOT* crash here just because a
		 strange parameter (such as `(load "test.scm")`) is
		 passed, otherwise the whole library is useless in a
		 foreign environment. */
	      NSObject *plist_val;

	      NS_DURING
		{
		  plist_val = [val propertyList];
		}
	      NS_HANDLER
		{
		  plist_val = val;
		}
	      NS_ENDHANDLER

	      /* Make sure we don't crash being caught adding nil to
                 a dictionary. */
	      if (plist_val == nil)
		{
		  plist_val = val;
		}

	      [argDict setObject: plist_val  forKey: key];
	      if (old != nil)
		{
		  [argDict setObject: plist_val  forKey: old];
		}
	    }
	}
      done = ((key = [enumerator nextObject]) == nil);
    }
  [_lock unlock];
  return argDict;
}

- (void) __changePersistentDomain: (NSString*)domainName
{
  [_lock lock];
  DESTROY(_dictionaryRep);
  if (_changedDomains == nil)
    {
      _changedDomains = [[NSMutableArray alloc] initWithObjects: &domainName
							  count: 1];
      updateCache(self);
      [[NSNotificationCenter defaultCenter]
	postNotificationName: NSUserDefaultsDidChangeNotification
		      object: self];
    }
  else if ([_changedDomains containsObject: domainName] == NO)
    {
      [_changedDomains addObject: domainName];
    }
  [_lock unlock];
}
@end

NSDictionary*
GSUserDefaultsDictionaryRepresentation()
{
  NSDictionary	*defs;

  if (sharedDefaults == nil)
    {
      [NSUserDefaults standardUserDefaults];
    }
  [classLock lock];
  defs = [sharedDefaults dictionaryRepresentation];
  [classLock unlock];
  return defs;
}

/*
 * Get one of several potentially useful flags.
 */
BOOL
GSUserDefaultsFlag(GSUserDefaultFlagType type)
{
  if (sharedDefaults == nil)
    {
      [NSUserDefaults standardUserDefaults];
    }
  return flags[type];
}

