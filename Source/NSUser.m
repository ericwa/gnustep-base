/** Implementation of login-related functions for GNUstep
   Copyright (C) 1996 Free Software Foundation, Inc.
   
   Written by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Created: May 1996
   
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

   <title>NSUser class reference</title>
   $Date$ $Revision$
   */ 

#include "config.h"
#include "GNUstepBase/preface.h"
#include "Foundation/NSObjCRuntime.h"
#include "Foundation/NSString.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSException.h"
#include "Foundation/NSArray.h"
#include "Foundation/NSDictionary.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSProcessInfo.h"
#include "Foundation/NSString.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSUserDefaults.h"
#include "GNUstepBase/GSCategories.h"

#include "GSPrivate.h"

#include <stdlib.h>		// for getenv()
#ifdef HAVE_UNISTD_H
#include <unistd.h>		// for getlogin()
#endif
#ifdef	HAVE_PWD_H
#include <pwd.h>		// for getpwnam()
#endif
#include <sys/types.h>
#include <stdio.h>

#define lowlevelstringify(X) #X
#define stringify(X) lowlevelstringify(X)

static NSString	*theUserName = nil;
/* We read these four only once */
static NSString	*gnustep_user_root = nil;    /* GNUSTEP_USER_ROOT */
static NSString	*gnustep_local_root = nil;   /* GNUSTEP_LOCAL_ROOT */
static NSString	*gnustep_network_root = nil; /* GNUSTEP_NETWORK_ROOT */
static NSString	*gnustep_system_root = nil;  /* GNUSTEP_SYSTEM_ROOT */

static void	setupPathNames();
static NSString	*userDirectory(NSString *name, BOOL defaults);

static NSString*
ImportPath(NSString *s, const char *c)
{
  static NSFileManager	*mgr = nil;
  const char		*ptr = c;
  unsigned		len;

  if (mgr == nil)
    {
      mgr = [NSFileManager defaultManager];
      RETAIN(mgr);
    }
  if (ptr == 0)
    {
      if (s == nil)
	{
	  return nil;
	}
      ptr = [s cString];
    }
  len = strlen(ptr);
  return [mgr stringWithFileSystemRepresentation: ptr length: len]; 
}

/**
 * Sets the user name for this process.  This method is supplied to enable
 * setuid programs to run properly as the user indicated by their effective
 * user Id.<br />
 * This function calls [NSUserDefaults+resetStandardUserDefaults] as well
 * as changing the value returned by NSUserName() and modifying the user
 * root directory for the process.
 */
void
GSSetUserName(NSString* name)
{
  if (theUserName == nil)
    {
      NSUserName();	// Ensure we know the old user name.
    }
  /*
   * We can destroy the cached user path so that next time
   * anything wants it, it will be regenerated.
   */
  DESTROY(gnustep_user_root);
  /*
   * Next we can set up the new user name, and reset the user defaults
   * system so that standard user defaults will be those of the new
   * user.
   */
  ASSIGN(theUserName, name);
  [NSUserDefaults resetStandardUserDefaults];
}

/**
 * Return the caller's login name as an NSString object.<br />
 * Under ms-windows, the 'LOGNAME' environment variable is used as the
 * user name.<br />
 * Under unix-like systems, the name associated with the current
 * effective user ID is used.
 */
/* NOTE FOR DEVELOPERS.
 * If you change the behavior of this method you must also change
 * user_home.c in the makefiles package to match.
 */
NSString *
NSUserName(void)
{
#if defined(__WIN32__)
  if (theUserName == nil)
    {
      const char *loginName = 0;
      /* The GetUserName function returns the current user name */
      char buf[1024];
      DWORD n = 1024;

      if (GetEnvironmentVariable("LOGNAME", buf, 1024) != 0 && buf[0] != '\0')
	loginName = buf;
      else if (GetUserName(buf, &n) != 0 && buf[0] != '\0')
	loginName = buf;
      if (loginName)
	theUserName = [[NSString alloc] initWithCString: loginName];
      else
	[NSException raise: NSInternalInconsistencyException
		    format: @"Unable to determine current user name"];
    }
#else
  /* Set olduid to some invalid uid that we could never start off running
     as.  */
  static int	olduid = -1;
#ifdef HAVE_GETEUID
  int uid = geteuid();
#else
  int uid = getuid();
#endif /* HAVE_GETEUID */

  if (theUserName == nil || uid != olduid)
    {
      const char *loginName = 0;
#ifdef HAVE_GETPWUID
      struct passwd *pwent = getpwuid (uid);
      loginName = pwent->pw_name;
#endif /* HAVE_GETPWUID */
      olduid = uid;
      if (loginName)
	theUserName = [[NSString alloc] initWithCString: loginName];
      else
	[NSException raise: NSInternalInconsistencyException
		    format: @"Unable to determine current user name"];
    }
#endif
  return theUserName;
}

/**
 * Return the caller's home directory as an NSString object.
 * Calls NSHomeDirectoryForUser() to do this.
 */
NSString *
NSHomeDirectory(void)
{
  return NSHomeDirectoryForUser (NSUserName ());
}

#if defined(__MINGW__)
NSString *
GSStringFromWin32EnvironmentVariable(const char * envVar)
{
  char buf[1024], *nb;
  DWORD n;
  NSString *s = nil;

  [gnustep_global_lock lock];
  n = GetEnvironmentVariable(envVar, buf, 1024);
  if (n > 1024)
    {
      /* Buffer not big enough, so dynamically allocate it */
      nb = (char *)NSZoneMalloc(NSDefaultMallocZone(), sizeof(char)*(n+1));
      n = GetEnvironmentVariable(envVar, nb, n+1);
      nb[n] = '\0';
      s = [NSString stringWithCString: nb];
      NSZoneFree(NSDefaultMallocZone(), nb);
    }
  else if (n > 0)
    {
      /* null terminate it and return the string */
      buf[n] = '\0';
      s = [NSString stringWithCString: buf];
    }
  [gnustep_global_lock unlock];
  return s;
}
#endif

/**
 * Returns loginName's home directory as an NSString object.
 */
/* NOTE FOR DEVELOPERS.
 * If you change the behavior of this method you must also change
 * user_home.c in the makefiles package to match.
 */
NSString *
NSHomeDirectoryForUser(NSString *loginName)
{
  NSString	*s = nil;
#if !defined(__MINGW__)
  struct passwd *pw;

  [gnustep_global_lock lock];
  pw = getpwnam ([loginName cString]);
  if (pw != 0)
    {
      s = [NSString stringWithCString: pw->pw_dir];
    }
  [gnustep_global_lock unlock];
#else
  if ([loginName isEqual: NSUserName()] == YES)
    {
      [gnustep_global_lock lock];
      /*
       * The environment variable HOMEPATH holds the home directory
       * for the user on Windows NT; Win95 has no concept of home.
       * For OPENSTEP compatibility (and because USERPROFILE is usually
       * unusable because it contains spaces), we use HOMEPATH in
       * preference to USERPROFILE.
       */
      s = GSStringFromWin32EnvironmentVariable("HOMEPATH");
      if (s != nil && ([s length] < 2 || [s characterAtIndex: 1] != ':'))
	{
	  s = [GSStringFromWin32EnvironmentVariable("HOMEDRIVE")
	    stringByAppendingString: s];
	}
      if (s == nil)
	{
	  /* The environment variable USERPROFILE holds the home directory
	     for the user on more modern versions of windoze. */
	  s = GSStringFromWin32EnvironmentVariable("USERPROFILE");
	}
      [gnustep_global_lock unlock];
    }
  if ([s length] == 0 && [loginName length] != 1)
    {
      s = nil;
      NSLog(@"NSHomeDirectoryForUser(%@) failed", loginName);
    }
#endif
  s = ImportPath(s, 0);
// NSLog(@"Home for %@ is %@", loginName, s);
  return s;
}

/**
 * Returns the full username of the current user.
 * If unable to determine this, returns the standard user name.
 */
NSString *
NSFullUserName(void)
{
#ifdef HAVE_PWD_H
  struct passwd	*pw;

  pw = getpwnam([NSUserName() cString]);
  return [NSString stringWithCString: pw->pw_gecos];
#else
  NSLog(@"Warning: NSFullUserName not implemented\n");
  return NSUserName();
#endif
}

static BOOL
setupSystemRoot(NSDictionary *env)
{
  BOOL	warned = NO;
	  
  if (gnustep_system_root == nil)
    {
      /* Any of the following might be nil */
      gnustep_system_root = [env objectForKey: @"GNUSTEP_SYSTEM_ROOT"];
      gnustep_system_root = ImportPath(gnustep_system_root, 0);
      TEST_RETAIN (gnustep_system_root);
      if (gnustep_system_root == nil)
	{
	  /*
	   * This is pretty important as we need it to load
	   * character sets, language settings and similar
	   * resources.  Use fprintf to avoid recursive calls.
	   */
	  warned = YES;
	  gnustep_system_root
	    = ImportPath(nil, stringify(GNUSTEP_INSTALL_PREFIX));
	  RETAIN(gnustep_system_root);
	  fprintf (stderr, 
	    "Warning - GNUSTEP_SYSTEM_ROOT is not set "
		    "- using %s\n", [gnustep_system_root lossyCString]);
	}
    }
  return warned;
}

static BOOL
setupLocalRoot(NSDictionary *env, BOOL warned)
{
  if (gnustep_local_root == nil)
    {
      gnustep_local_root = [env objectForKey: @"GNUSTEP_LOCAL_ROOT"];
      gnustep_local_root = ImportPath(gnustep_local_root, 0);
      TEST_RETAIN (gnustep_local_root);
      if (gnustep_local_root == nil)
	{
	  gnustep_local_root
	    = ImportPath(nil, stringify(GNUSTEP_LOCAL_ROOT));
	  if ([gnustep_local_root length] == 0)
	    {
	      gnustep_local_root = nil;
	    }
	  else
	    {
	      RETAIN(gnustep_local_root);
	    }
	}
      if (gnustep_local_root == nil)
	{
	  if ([[gnustep_system_root lastPathComponent] isEqual:
	    @"System"] == YES)
	    {
	      gnustep_local_root = [[gnustep_system_root
		stringByDeletingLastPathComponent]
		stringByAppendingPathComponent: @"Local"];
	      TEST_RETAIN (gnustep_local_root);
	    }
	  else
	    {
	      gnustep_local_root = @"/usr/GNUstep/Local";
	    }
#ifndef	NDEBUG
	  if (warned == NO)
	    {
	      warned = YES;
	      fprintf (stderr, 
		"Warning - GNUSTEP_LOCAL_ROOT is not set "
		"- using %s\n", [gnustep_local_root lossyCString]);
	    }
#endif
	}
    }
  return warned;
}

static BOOL
setupNetworkRoot(NSDictionary *env, BOOL warned)
{
  if (gnustep_network_root == nil)
    {
      gnustep_network_root = [env objectForKey: @"GNUSTEP_NETWORK_ROOT"];
      gnustep_network_root = ImportPath(gnustep_network_root, 0);
      TEST_RETAIN (gnustep_network_root);
      if (gnustep_network_root == nil)
	{
	  gnustep_network_root
	    = ImportPath(nil, stringify(GNUSTEP_NETWORK_ROOT));
	  if ([gnustep_network_root length] == 0)
	    {
	      gnustep_network_root = nil;
	    }
	  else
	    {
	      RETAIN(gnustep_network_root);
	    }
	}
      if (gnustep_network_root == nil)
	{
	  if ([[gnustep_system_root lastPathComponent] isEqual:
	    @"System"] == YES)
	    {
	      gnustep_network_root = [[gnustep_system_root
		stringByDeletingLastPathComponent]
		stringByAppendingPathComponent: @"Network"];
	      TEST_RETAIN (gnustep_network_root);
	    }
	  else
	    {
	      gnustep_network_root = @"/usr/GNUstep/Network";
	    }
#ifndef	NDEBUG
	  if (warned == NO)
	    {
	      warned = YES;
	      fprintf (stderr, 
		"Warning - GNUSTEP_NETWORK_ROOT is not set "
		"- using %s\n", [gnustep_network_root lossyCString]);
	    }
#endif
	}
    }
  return warned;
}


static void
setupPathNames()
{
  if (gnustep_user_root == nil)
    {
      NS_DURING
	{
	  BOOL	warned = NO;
	  NSDictionary	*env = [[NSProcessInfo processInfo] environment];
	  
	  [gnustep_global_lock lock];

	  warned = setupSystemRoot(env);
	  warned = setupLocalRoot(env, warned);
	  warned = setupNetworkRoot(env, warned);
	  if (gnustep_user_root == nil)
	    {
	      gnustep_user_root = [userDirectory(NSUserName(), NO) copy];
	    }

	  [gnustep_global_lock unlock];
	}
      NS_HANDLER
	{
	  // unlock then re-raise the exception
	  [gnustep_global_lock unlock];
	  [localException raise];
	}
      NS_ENDHANDLER
    }
}

/** Returns a string containing the path to the GNUstep system
    installation directory. This function is guarenteed to return a non-nil
    answer (unless something is seriously wrong, in which case the application
    will probably crash anyway) */
NSString *
GSSystemRootDirectory(void)
{
  if (gnustep_system_root == nil)
    {
      setupPathNames();
    }
  return gnustep_system_root;
}

/**
 * Return the path of the defaults directory for name.<br />
 * This examines the .GNUsteprc file in the home directory of the
 * user for the GNUSTEP_DEFAULTS_ROOT or the GNUSTEP_USER_ROOT
 * directory definitions.
 */
NSString*
GSDefaultsRootForUser(NSString *userName)
{
  return userDirectory(userName, YES);
}

static NSString *
userDirectory(NSString *name, BOOL defaults)
{
  NSFileManager	*manager;
  NSString	*home;
  NSString	*path = nil;
  NSString	*file;
  NSString	*user = nil;
  NSString	*defs = nil;
  BOOL		forceD = NO;
  BOOL		forceU = NO;
  NSDictionary	*attributes;

  NSCAssert([name length] > 0, NSInvalidArgumentException);

  home = NSHomeDirectoryForUser(name);
  manager = [NSFileManager defaultManager];

  if (gnustep_system_root == nil)
    {
      NSDictionary	*env = [[NSProcessInfo processInfo] environment];
	  
      [gnustep_global_lock lock];
      setupSystemRoot(env);
      [gnustep_global_lock unlock];
    }
  file = [gnustep_system_root stringByAppendingPathComponent: @".GNUsteprc"];
  attributes = [manager fileAttributesAtPath: file traverseLink: YES];
  if (([attributes filePosixPermissions] & 022) != 0)
    {
      fprintf(stderr, "The file '%s' is writable by someone other than"
	" its owner.\nIgnoring it.\n", [file fileSystemRepresentation]);
    }
  else if ([manager isReadableFileAtPath: file] == YES)
    {
      NSArray	*lines;
      unsigned	count;

      file = [NSString stringWithContentsOfFile: file];
      lines = [file componentsSeparatedByString: @"\n"];
      count = [lines count];
      while (count-- > 0)
	{
	  NSRange	r;
	  NSString	*line;
	  NSString	*key;
	  NSString	*val;

	  line = [[lines objectAtIndex: count] stringByTrimmingSpaces];
	  r = [line rangeOfString: @"="];
	  if (r.length == 1)
	    {
	      key = [line substringToIndex: r.location];
	      val = [line substringFromIndex: NSMaxRange(r)];

	      key = [key stringByTrimmingSpaces];
	      val = [val stringByTrimmingSpaces];
	    }
	  else
	    {
	      key = [line stringByTrimmingSpaces];
	      val = nil;
	    }

	  if ([key isEqualToString: @"GNUSTEP_USER_ROOT"] == YES)
	    {
	      if ([val length] > 0 && [val characterAtIndex: 0] == '~')
		{
		  val = [home stringByAppendingString:
		    [val substringFromIndex: 1]];
		}
	      user = val;
	    }
	  else if ([key isEqualToString: @"GNUSTEP_DEFAULTS_ROOT"] == YES)
	    {
	      if ([val length] > 0 && [val characterAtIndex: 0] == '~')
		{
		  val = [home stringByAppendingString:
		    [val substringFromIndex: 1]];
		}
	      defs = val;
	    }
	  else if ([key isEqualToString: @"FORCE_USER_ROOT"] == YES)
	    {
	      forceU = YES;
	    }
	  else if ([key isEqualToString: @"FORCE_DEFAULTS_ROOT"] == YES)
	    {
	      forceD = YES;
	    }
	}
    }

  if (forceD == NO || defs == nil || forceU == NO || user == nil)
    {
      file = [home stringByAppendingPathComponent: @".GNUsteprc"];

      attributes = [manager fileAttributesAtPath: file traverseLink: YES];
      if (([attributes filePosixPermissions] & 022) != 0)
	{
	  fprintf(stderr, "The file '%s' is writable by someone other than"
	    " its owner.\nIgnoring it.\n", [file fileSystemRepresentation]);
	}
#ifndef	__MINGW__
/* FIXME ... need to get mingw working */
      else if (attributes != nil
	&& [[attributes fileOwnerAccountName] isEqual: NSUserName()] == NO)
	{
	  fprintf(stderr, "The file '%s' is not owned by the current user."
	    "\nIgnoring it.\n", [file fileSystemRepresentation]);
	}
#endif
      else if ([manager isReadableFileAtPath: file] == YES)
	{
	  NSArray	*lines;
	  unsigned	count;

	  file = [NSString stringWithContentsOfFile: file];
	  lines = [file componentsSeparatedByString: @"\n"];
	  count = [lines count];
	  while (count-- > 0)
	    {
	      NSRange	r;
	      NSString	*line;

	      line = [[lines objectAtIndex: count] stringByTrimmingSpaces];
	      r = [line rangeOfString: @"="];
	      if (r.length == 1)
		{
		  NSString	*key = [line substringToIndex: r.location];
		  NSString	*val = [line substringFromIndex: NSMaxRange(r)];

		  key = [key stringByTrimmingSpaces];
		  val = [val stringByTrimmingSpaces];
		  if ([key isEqualToString: @"GNUSTEP_USER_ROOT"] == YES)
		    {
		      if ([val length] > 0 && [val characterAtIndex: 0] == '~')
			{
			  val = [home stringByAppendingString:
			    [val substringFromIndex: 1]];
			}
		      if (user == nil || forceU == NO)
			{
			  user = val;
			}
		    }
		  else if ([key isEqualToString: @"GNUSTEP_DEFAULTS_ROOT"])
		    {
		      if ([val length] > 0 && [val characterAtIndex: 0] == '~')
			{
			  val = [home stringByAppendingString:
			    [val substringFromIndex: 1]];
			}
		      if (defs == nil || forceD == NO)
			{
			  defs = val;
			}
		    }
		}
	    }
	}
    }

  if (defaults == YES)
    {
      path = defs;
      /*
       * defaults root may default to user root
       */
      if (path == nil)
	{
	  path = user;
	}
    }
  else
    {
      path = user;
    }

  /*
   * If not specified in file, default to standard location.
   */
  if (path == nil)
    {
      path = [home stringByAppendingPathComponent: @"GNUstep"];
    }

  return ImportPath(path, 0);
}

/** Returns an array of strings which contain paths that should be in
    the standard search order for resources, etc. If the environment
    variable GNUSTEP_PATHPREFIX_LIST is set. It returns the list of
    paths set in that variable. Otherwise, it returns the user, local,
    network, and system paths, in that order.  This function is
    guarenteed to return a non-nil answer (unless something is
    seriously wrong, in which case the application will probably crash
    anyway) */
NSArray *
GSStandardPathPrefixes(void)
{
  NSDictionary	*env;
  NSString	*prefixes;
  NSArray	*prefixArray;
    
  env = [[NSProcessInfo processInfo] environment];
  prefixes = [env objectForKey: @"GNUSTEP_PATHPREFIX_LIST"];
  if (prefixes != nil)
    {
      unsigned	c;

#if	defined(__WIN32__)
      prefixArray = [prefixes componentsSeparatedByString: @";"];
#else
      prefixArray = [prefixes componentsSeparatedByString: @":"];
#endif
      if ((c = [prefixArray count]) <= 1)
	{
	  /* This probably means there was some parsing error, but who
	     knows. Play it safe though... */
	  prefixArray = nil;
	}
      else
	{
	  NSString	*a[c];
	  unsigned	i;

	  [prefixArray getObjects: a];
	  for (i = 0; i < c; i++)
	    {
	      a[c] = ImportPath(a[c], 0);
	    }
	  prefixArray = [NSArray arrayWithObjects: a count: c];
	}
    }
  if (prefixes == nil)
    {
      NSString	*strings[4];
      NSString	*str;
      unsigned	count = 0;

      if (gnustep_user_root == nil)
	{
	  setupPathNames();
	}
      str = gnustep_user_root;
      if (str != nil)
	strings[count++] = str;

      str = gnustep_local_root;
      if (str != nil)
	strings[count++] = str;

      str = gnustep_network_root;
      if (str != nil)
        strings[count++] = str;

      str = gnustep_system_root;
      if (str != nil)
	strings[count++] = str;

      if (count)
	prefixArray = [NSArray arrayWithObjects: strings count: count];
      else
	prefixArray = [NSArray array];
    }
  return prefixArray;
}

/**
 * Returns the standard paths in which applications are stored and
 * should be searched for.  Calls NSSearchPathForDirectoriesInDomains()
 */
NSArray *
NSStandardApplicationPaths(void)
{
  return NSSearchPathForDirectoriesInDomains(NSAllApplicationsDirectory,
                                             NSAllDomainsMask, YES);
}

/**
 * Returns the standard paths in which libraries are stored and
 * should be searched for.  Calls NSSearchPathForDirectoriesInDomains()
 */
NSArray *
NSStandardLibraryPaths(void)
{
  return NSSearchPathForDirectoriesInDomains(NSAllLibrariesDirectory,
                                             NSAllDomainsMask, YES);
}

/**
 * Returns the name of a directory in which temporary files can be stored.
 * Under GNUstep this is a location which is not readable by other users.
 * <br />
 * If a suitable directory can't be found or created, this function raises an
 * NSGenericException.
 */
NSString *
NSTemporaryDirectory(void)
{
  NSFileManager	*manager;
  NSString	*tempDirName;
  NSString	*baseTempDirName = nil;
  NSDictionary	*attr;
  int		perm;
  int		owner;
  int		uid;
  BOOL		flag;
#if	defined(__WIN32__)
  char buffer[1024];

  if (GetTempPath(1024, buffer))
    {
      baseTempDirName = ImportPath(nil, buffer);
    }
#endif

  /*
   * If the user has supplied a directory name in the TEMP or TMP
   * environment variable, attempt to use that unless we already
   * have a tem porary directory specified.
   */
  if (baseTempDirName == nil)
    {
      NSDictionary	*env = [[NSProcessInfo processInfo] environment];

      baseTempDirName = [env objectForKey: @"TEMP"];
      if (baseTempDirName == nil)
	{
	  baseTempDirName = [env objectForKey: @"TMP"];
	  if (baseTempDirName == nil)
	    {
#if	defined(__MINGW__)
#ifdef  __CYGWIN__
	      baseTempDirName = @"/cygdrive/c/";
#else
	      baseTempDirName = @"/c/";
#endif
#else
	      baseTempDirName = @"/tmp";
#endif
	    }
	}
    }

  /*
   * Check that the base directory exists ... if it doesn't we can't
   * go any further.
   */
  tempDirName = baseTempDirName;
  manager = [NSFileManager defaultManager];
  if ([manager fileExistsAtPath: tempDirName isDirectory: &flag] == NO
    || flag == NO)
    {
      [NSException raise: NSGenericException
		  format: @"Temporary directory (%@) does not exist",
			  tempDirName];
      return nil; /* Not reached. */
    }

  /*
   * Check that we are the directory owner, and that we, and nobody else,
   * have access to it. If other people have access, try to create a secure
   * subdirectory.
   */
  attr = [manager fileAttributesAtPath: tempDirName traverseLink: YES];
  owner = [[attr objectForKey: NSFileOwnerAccountID] intValue];
  perm = [[attr objectForKey: NSFilePosixPermissions] intValue];
  perm = perm & 0777;

#if	defined(__MINGW__)
  uid = owner;
#else
#ifdef HAVE_GETEUID
  uid = geteuid();
#else
  uid = getuid();
#endif /* HAVE_GETEUID */
#endif
  if ((perm != 0700 && perm != 0600) || owner != uid)
    {
      /*
      NSLog(@"Temporary directory (%@) may be insecure ... attempting to "
	@"add secure subdirectory", tempDirName);
      */

      tempDirName
	= [baseTempDirName stringByAppendingPathComponent: NSUserName()];
      if ([manager fileExistsAtPath: tempDirName] == NO)
	{
	  NSNumber	*p = [NSNumber numberWithInt: 0700];

	  attr = [NSDictionary dictionaryWithObject: p
					     forKey: NSFilePosixPermissions];
	  if ([manager createDirectoryAtPath: tempDirName
				  attributes: attr] == NO)
	    {
	      [NSException raise: NSGenericException
			  format: @"Attempt to create a secure temporary directory (%@) failed.",
				  tempDirName];
	      return nil; /* Not reached. */
	    }
	}

      /*
       * Check that the new directory is really secure.
       */
      attr = [manager fileAttributesAtPath: tempDirName traverseLink: YES];
      owner = [[attr objectForKey: NSFileOwnerAccountID] intValue];
      perm = [[attr objectForKey: NSFilePosixPermissions] intValue];
      perm = perm & 0777;
      if ((perm != 0700 && perm != 0600) || owner != uid)
	{
	  [NSException raise: NSGenericException
		      format: @"Attempt to create a secure temporary directory (%@) failed.",
			      tempDirName];
	  return nil; /* Not reached. */
	}
    }

  if ([manager isWritableFileAtPath: tempDirName] == NO)
    {
      [NSException raise: NSGenericException
		  format: @"Temporary directory (%@) is not writable",
			  tempDirName];
      return nil; /* Not reached. */
    }
  return tempDirName;
}

/**
 * Returns the root directory for the OpenStep (GNUstep) installation.
 * This is determined by the GNUSTEP_ROOT environment variable if available.
 */
NSString *
NSOpenStepRootDirectory(void)
{
  NSString	*root;

  root = [[[NSProcessInfo processInfo] environment]
    objectForKey: @"GNUSTEP_ROOT"];
  if (root == nil)
    {
#if	defined(__MINGW__)
#ifdef  __CYGWIN__
      root = @"/cygdrive/c/";
#else
      root = @"/c/";
#endif
#else
      root = @"/";
#endif
    }
  else
    {
      root = ImportPath(root, 0);
    }
  return root;
}

/**
 * Returns an array of search paths to look at for resources.
 */
NSArray *
NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directoryKey,
  NSSearchPathDomainMask domainMask, BOOL expandTilde)
{
  NSFileManager		*fm;
  NSString		*adminDir = @"Administrator";
  NSString		*appsDir = @"Applications";
  NSString		*demosDir = @"Demos";
  NSString		*devDir = @"Developer";
  NSString		*libraryDir = @"Library";
  NSString		*libsDir = @"Library/Libraries";
  NSString		*toolsDir = @"Tools";
  NSString		*docDir = @"Library/Documentation";
  NSString		*supportDir = @"Library/ApplicationSupport";
  NSMutableArray	*paths = [NSMutableArray new];
  NSString		*path;
  unsigned		i;
  unsigned		count;

  if (gnustep_user_root == nil)
    {
      setupPathNames();
    }

  /*
   * The order in which we return paths is important - user must come
   * first, followed by local, followed by network, followed by system.
   * The calling code can then loop on the returned paths, and stop as
   * soon as it finds something.  So things in user automatically
   * override things in system etc.
   */

  /*
   * FIXME - The following code will not respect this order for
   * NSAllApplicationsDirectory.  This should be fixed I think.
   */
  
#define ADD_PATH(mask, base_dir, add_dir) \
if (domainMask & mask) \
{ \
  path = [base_dir stringByAppendingPathComponent: add_dir]; \
  if (path != nil) \
    [paths addObject: path]; \
}

  if (directoryKey == NSApplicationDirectory
    || directoryKey == NSAllApplicationsDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, appsDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, appsDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, appsDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, appsDir);
    }
  if (directoryKey == NSDemoApplicationDirectory
    || directoryKey == NSAllApplicationsDirectory);
    {
      NSString *devDemosDir = [devDir stringByAppendingPathComponent: demosDir];
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, devDemosDir);
    }
  if (directoryKey == NSDeveloperApplicationDirectory
    || directoryKey == NSAllApplicationsDirectory)
    {
      NSString *devAppsDir = [devDir stringByAppendingPathComponent: appsDir];

      ADD_PATH(NSUserDomainMask, gnustep_user_root, devAppsDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, devAppsDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, devAppsDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, devAppsDir);
    }
  if (directoryKey == NSAdminApplicationDirectory
    || directoryKey == NSAllApplicationsDirectory)
    {
      NSString *devAdminDir = [devDir stringByAppendingPathComponent: adminDir];

      /* FIXME - NSUserDomainMask ? - users have no Administrator directory */
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, devAdminDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, devAdminDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, devAdminDir);
    }
  if (directoryKey == NSLibraryDirectory
    || directoryKey == NSAllLibrariesDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, libraryDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, libraryDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, libraryDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, libraryDir);
    }
  if (directoryKey == NSDeveloperDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_local_root, devDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, devDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, devDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, devDir);
    }
  if (directoryKey == NSUserDirectory)
    {
      if (domainMask & NSUserDomainMask)
	{
	  [paths addObject: gnustep_user_root];
	}
    }
  if (directoryKey == NSDocumentationDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, docDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, docDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, docDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, docDir);
    }
  if (directoryKey == GSLibrariesDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, libsDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, libsDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, libsDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, libsDir);
    }
  if (directoryKey == GSToolsDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, toolsDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, toolsDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, toolsDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, toolsDir);
    }
  if (directoryKey == GSApplicationSupportDirectory)
    {
      ADD_PATH(NSUserDomainMask, gnustep_user_root, supportDir);
      ADD_PATH(NSLocalDomainMask, gnustep_local_root, supportDir);
      ADD_PATH(NSNetworkDomainMask, gnustep_network_root, supportDir);
      ADD_PATH(NSSystemDomainMask, gnustep_system_root, supportDir);
    }

#undef ADD_PATH

  fm = [NSFileManager defaultManager];

  count = [paths count];

  for (i = 0; i < count; i++)
    {
      path = [paths objectAtIndex: i];
      // remove bad paths
      if ([fm fileExistsAtPath: path] == NO)
        {
          [paths removeObjectAtIndex: i];
	  i--;
	  count--;
        }
      /*
       * this may look like a performance hit at first glance, but if these
       * string methods don't alter the string, they return the receiver
       */
      else if (expandTilde == YES)
	{
	  [paths replaceObjectAtIndex: i
			   withObject: [path stringByExpandingTildeInPath]];
	}
      else
	{
	  [paths replaceObjectAtIndex: i
	    withObject: [path stringByAbbreviatingWithTildeInPath]];
	}
    }

  AUTORELEASE (paths);
  return paths;
}
