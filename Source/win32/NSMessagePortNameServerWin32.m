/* Implementation of message port subclass of NSPortNameServer

   Copyright (C) 2005 Free Software Foundation, Inc.

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
   License along with this library; if not, write to the
   Free Software Foundation,
   Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.

   <title>NSMessagePortNameServer class reference</title>
   $Date$ $Revision$
   */

#include "Foundation/NSPortNameServer.h"

#include "Foundation/NSAutoreleasePool.h"
#include "Foundation/NSDebug.h"
#include "Foundation/NSException.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSMapTable.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSPort.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSThread.h"

#include "GSPortPrivate.h"

#if	defined(__MINGW32__)

#else	/* __MINGW32__ */


static NSRecursiveLock *serverLock = nil;
static NSMessagePortNameServer *defaultServer = nil;

/*
Maps NSMessagePort objects to NSMutableArray:s of NSString:s. The array
is an array of names the port has been registered under by _us_.

Note that this map holds the names the port has been registered under at
some time. If the name is been unregistered by some other program, we can't
update the table, so we have to deal with the case where the array contains
names that the port isn't registered under.

Since we _have_to_ deal with this anyway, we handle it in -removePort: and
-removePort:forName:, and we don't bother removing entries in the map when
unregistering a name not for a specific port.
*/
static NSMapTable portToNamesMap;


@interface NSMessagePortNameServer (private)
+(NSString *) _pathForName: (NSString *)name;
@end


static void clean_up_names(void)
{
  NSMapEnumerator mEnum;
  NSMessagePort	*port;
  NSString	*name;
  BOOL	unknownThread = GSRegisterCurrentThread();
  CREATE_AUTORELEASE_POOL(arp);

  mEnum = NSEnumerateMapTable(portToNamesMap);
  while (NSNextMapEnumeratorPair(&mEnum, (void *)&port, (void *)&name))
    {
      [defaultServer removePort: port];
    }
  NSEndMapTableEnumeration(&mEnum);
  DESTROY(arp);
  if (unknownThread == YES)
    {
      GSUnregisterCurrentThread();
    }
}

/**
 * Subclass of [NSPortNameServer] taking/returning instances of [NSMessagePort].
 * Port removal functionality is not supported; if you want to cancel a service,
 * you have to destroy the port (invalidate the [NSMessagePort] given to
 * [NSPortNameServer-registerPort:forName:]).
 */
@implementation NSMessagePortNameServer

+ (void) initialize
{
  if (self == [NSMessagePortNameServer class])
    {
      serverLock = [NSRecursiveLock new];
      portToNamesMap = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
			 NSObjectMapValueCallBacks, 0);
      atexit(clean_up_names);
    }
}

/**
 *  Obtain single instance for this host.
 */
+ (id) sharedInstance
{
  if (defaultServer == nil)
    {
      [serverLock lock];
      if (defaultServer == nil)
	{
	  defaultServer = (NSMessagePortNameServer *)NSAllocateObject(self,
	    0, NSDefaultMallocZone());
	}
      [serverLock unlock];
    }
  return defaultServer;
}


+ (NSString *) _pathForName: (NSString *)name
{
  static NSString	*base_path = nil;
  NSString		*path;

  [serverLock lock];
  if (!base_path)
    {
      NSNumber		*p = [NSNumber numberWithInt: 0700];
      NSDictionary	*attr;

      path = NSTemporaryDirectory();
      attr = [NSDictionary dictionaryWithObject: p
				     forKey: NSFilePosixPermissions];

      path = [path stringByAppendingPathComponent: @"NSMessagePort"];
      [[NSFileManager defaultManager] createDirectoryAtPath: path
				      attributes: attr];

      path = [path stringByAppendingPathComponent: @"names"];
      [[NSFileManager defaultManager] createDirectoryAtPath: path
				      attributes: attr];

      base_path = RETAIN(path);
    }
  else
    {
      path = base_path;
    }
  [serverLock unlock];

  path = [path stringByAppendingPathComponent: name];
  return path;
}


+ (BOOL) _livePort: (NSString *)path
{
  FILE	*f;
  char	socket_path[512];
  int	pid;
  struct stat sb;

  NSDebugLLog(@"NSMessagePort", @"_livePort: %@", path);

  f = fopen([path fileSystemRepresentation], "rt");
  if (!f)
    {
      NSDebugLLog(@"NSMessagePort", @"not live, couldn't open file (%m)");
      return NO;
    }

  fgets(socket_path, sizeof(socket_path), f);
  if (strlen(socket_path) > 0) socket_path[strlen(socket_path) - 1] = 0;

  fscanf(f, "%i", &pid);

  fclose(f);

  if (stat(socket_path, &sb) < 0)
    {
      unlink([path fileSystemRepresentation]);
      NSDebugLLog(@"NSMessagePort", @"not live, couldn't stat socket (%m)");
      return NO;
    }

  if (kill(pid, 0) < 0)
    {
      unlink([path fileSystemRepresentation]);
      unlink(socket_path);
      NSDebugLLog(@"NSMessagePort", @"not live, no such process (%m)");
      return NO;
    }
  else
    {
      struct sockaddr_un sockAddr;
      int desc;

      memset(&sockAddr, '\0', sizeof(sockAddr));
      sockAddr.sun_family = AF_LOCAL;
      strncpy(sockAddr.sun_path, socket_path, sizeof(sockAddr.sun_path));

      if ((desc = socket(PF_LOCAL, SOCK_STREAM, PF_UNSPEC)) < 0)
	{
	  unlink([path fileSystemRepresentation]);
	  unlink(socket_path);
	  NSDebugLLog(@"NSMessagePort",
	    @"couldn't create socket, assuming not live (%m)");
	  return NO;
	}
      if (connect(desc, (struct sockaddr*)&sockAddr, SUN_LEN(&sockAddr)) < 0)
	{
	  unlink([path fileSystemRepresentation]);
	  unlink(socket_path);
	  NSDebugLLog(@"NSMessagePort", @"not live, can't connect (%m)");
	  return NO;
	}
      close(desc);
      NSDebugLLog(@"NSMessagePort", @"port is live");
      return YES;
    }
}


- (NSPort*) portForName: (NSString *)name
		 onHost: (NSString *)host
{
  NSString	*path;
  FILE		*f;
  char		socket_path[512];

  NSDebugLLog(@"NSMessagePort", @"portForName: %@ host: %@", name, host);

  if ([host length] && ![host isEqual: @"*"])
    {
      NSDebugLLog(@"NSMessagePort", @"non-local host");
      return nil;
    }

  path = [[self class] _pathForName: name];
  if (![[self class] _livePort: path])
    {
      NSDebugLLog(@"NSMessagePort", @"not a live port");
      return nil;
    }

  f = fopen([path fileSystemRepresentation], "rt");
  if (!f)
    {
      NSDebugLLog(@"NSMessagePort", @"can't open file (%m)");
      return nil;
    }

  fgets(socket_path, sizeof(socket_path), f);
  if (strlen(socket_path) > 0) socket_path[strlen(socket_path) - 1] = 0;
  fclose(f);

  NSDebugLLog(@"NSMessagePort", @"got %s", socket_path);

  return [NSMessagePort _portWithName: (unsigned char*)socket_path
			     listener: NO];
}

- (BOOL) registerPort: (NSPort *)port
	      forName: (NSString *)name
{
  int			fd;
  unsigned char		buf[32];
  NSString		*path;
  const unsigned char	*socket_name;
  NSMutableArray	*a;

  NSDebugLLog(@"NSMessagePort", @"register %@ as %@\n", port, name);
  if ([port isKindOfClass: [NSMessagePort class]] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Attempted to register a non-NSMessagePort (%@)",
	port];
      return NO;
    }

  path = [[self class] _pathForName: name];

  if ([[self class] _livePort: path])
    {
      NSDebugLLog(@"NSMessagePort", @"fail, is a live port");
      return NO;
    }

  fd = open([path fileSystemRepresentation], O_CREAT|O_EXCL|O_WRONLY, 0600);
  if (fd < 0)
    {
      NSDebugLLog(@"NSMessagePort", @"fail, can't open file (%m)");
      return NO;
    }

  socket_name = [(NSMessagePort *)port _name];

  write(fd, (char*)socket_name, strlen((char*)socket_name));
  write(fd, "\n", 1);
  sprintf((char*)buf, "%i\n", getpid());
  write(fd, (char*)buf, strlen((char*)buf));

  close(fd);

  [serverLock lock];
  a = NSMapGet(portToNamesMap, port);
  if (!a)
    {
      a = [[NSMutableArray alloc] init];
      NSMapInsert(portToNamesMap, port, a);
      RELEASE(a);
    }

  [a addObject: [name copy]];
  [serverLock unlock];

  return YES;
}

- (BOOL) removePortForName: (NSString *)name
{
  NSString	*path;

  NSDebugLLog(@"NSMessagePort", @"removePortForName: %@", name);
  path = [[self class] _pathForName: name];
  unlink([path fileSystemRepresentation]);
  return YES;
}

- (NSArray *) namesForPort: (NSPort *)port
{
  NSMutableArray	*a;

  [serverLock lock];
  a = NSMapGet(portToNamesMap, port);
  a = [a copy];
  [serverLock unlock];
  return a;
}

- (BOOL) removePort: (NSPort *)port
{
  NSMutableArray *a;
  int		i;

  NSDebugLLog(@"NSMessagePort", @"removePort: %@", port);

  [serverLock lock];
  a = NSMapGet(portToNamesMap, port);

  for (i = 0; i < [a count]; i++)
    {
      [self removePort: port  forName: [a objectAtIndex: i]];
    }

  NSMapRemove(portToNamesMap, port);
  [serverLock unlock];

  return YES;
}

- (BOOL) removePort: (NSPort*)port forName: (NSString*)name
{
  FILE			*f;
  char			socket_path[512];
  NSString		*path;
  const unsigned char	*port_path;

  NSDebugLLog(@"NSMessagePort", @"removePort: %@  forName: %@", port, name);

  path = [[self class] _pathForName: name];

  f = fopen([path fileSystemRepresentation], "rt");
  if (!f)
    return YES;

  fgets(socket_path, sizeof(socket_path), f);
  if (strlen(socket_path) > 0) socket_path[strlen(socket_path) - 1] = 0;

  fclose(f);

  port_path = [(NSMessagePort *)port _name];

  if (!strcmp((char*)socket_path, (char*)port_path))
    {
      unlink([path fileSystemRepresentation]);
    }

  return YES;
}

@end

#endif	/* __MINGW32__ */
