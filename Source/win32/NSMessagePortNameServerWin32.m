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
#include "Foundation/NSError.h"
#include "Foundation/NSException.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSMapTable.h"
#include "Foundation/NSPathUtilities.h"
#include "Foundation/NSPort.h"
#include "Foundation/NSFileManager.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSThread.h"
#include "Foundation/NSUserDefaults.h"

#include "GNUstepBase/GSMime.h"

#include "../GSPrivate.h"
#include "GSPortPrivate.h"

#define	UNISTR(X) \
((const unichar*)[(X) cStringUsingEncoding: NSUnicodeStringEncoding])

extern int	errno;

static NSRecursiveLock *serverLock = nil;
static NSMessagePortNameServer *defaultServer = nil;
static NSMapTable portToNamesMap;
static NSString	*registry;
static HKEY	key;

static SECURITY_ATTRIBUTES	security;

@interface NSMessagePortNameServer (private)
+ (NSString *) _query: (NSString *)name;
+ (NSString *) _translate: (NSString *)name;
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
  RegCloseKey(key);
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
      int	rc;

      serverLock = [NSRecursiveLock new];
      portToNamesMap = NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks,
	NSObjectMapValueCallBacks, 0);
      atexit(clean_up_names);

      security.nLength = sizeof(SECURITY_ATTRIBUTES);
      security.lpSecurityDescriptor = 0;	// Default
      security.bInheritHandle = TRUE;

      registry = @"Software\\GNUstepNSMessagePort";
      rc = RegCreateKeyExW(
	HKEY_CURRENT_USER,
	UNISTR(registry),
	0,
	L"",
	REG_OPTION_VOLATILE,
	STANDARD_RIGHTS_WRITE|STANDARD_RIGHTS_READ|KEY_SET_VALUE
	|KEY_QUERY_VALUE|KEY_NOTIFY,
	&security,
	&key,
	NULL);
      if (rc == ERROR_SUCCESS)
	{
	  rc = RegFlushKey(key);
	  if (rc != ERROR_SUCCESS)
	    {
	      NSLog(@"Failed to flush registry HKEY_CURRENT_USER\\%@ (%x)",
		registry, rc);
	    }
	}
      else
	{
	  NSLog(@"Failed to create registry HKEY_CURRENT_USER\\%@ (%x)",
	    registry, rc);
	}
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


+ (NSString *) _query: (NSString *)name
{
  NSString	*n;
  NSString	*p;
  unsigned char	buf[1024];
  unsigned char	*ptr = buf;
  DWORD		max = 1024;
  DWORD		len = 1024;
  DWORD		type;
  HANDLE	h;
  int		rc;

  n = [[self class] _translate: name];

/* FIXME ... wierd hack.
 * It appears that RegQueryValueExW does not always read from the registry,
 * but will in fact return cached results (even if you close and re-open the
 * registry key between the calls to RegQueryValueExW).  This is a problem
 * if we look up a server which is not running, and then try to look it up
 * again when it is running, or if we have one address recorded but the server
 * has been restarted and is using a new address.
 * I couldn't find any mention of this behavior ... but accidentally discovered
 * that a call to OutputDebugStringW stops it ... presumably something in the
 * debug system invalidates whatever registry caching is being done.
 * Anyway, on my XP SP2 system, this next line is needed to fix things.
 *
 * You can test this by running a GNUstep application without starting
 * gdnc beforehand.  If the bug is occurring, the app will try to start gdnc
 * then poll to connect to it, and after 5 seconds will abort because it
 * hasn't seen the gdnc port registered even though gdnc did start.
 * If the hack has fixed the bug, the app will just pause briefly during
 * startup (as it starts gdnc) and then continue when it finds the server
 * port.
 */
OutputDebugStringW(L"");

  rc = RegQueryValueExW(
    key,
    UNISTR(n),
    (LPDWORD)0,
    &type,
    (LPBYTE)ptr,
    &len);
  while (rc == ERROR_MORE_DATA)
    {
      if (ptr != buf)
        {
	  objc_free(ptr);
	}
      max += 1024;
      ptr = objc_malloc(max);
      len = max;
      rc = RegQueryValueExW(
	key,
	UNISTR(n),
	(LPDWORD)0,
	&type,
	(LPBYTE)ptr,
	&len);
    }
  if (rc != ERROR_SUCCESS)
    {
      if (ptr != buf)
        {
	  objc_free(ptr);
	}
      return nil;
    }

  p = [NSString stringWithUTF8String: ptr];
  if (ptr != buf)
    {
      objc_free(ptr);
    }

  /*
   * See if we can open the port mailslot ... if not, the query returned
   * an old name, and we can remove it.
   */
  p = [NSString stringWithFormat:
    @"\\\\.\\mailslot\\GNUstep\\NSMessagePort\\%@", p];
  h = CreateFileW(
    UNISTR(p),
    GENERIC_WRITE,
    FILE_SHARE_READ|FILE_SHARE_WRITE,
    &security,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    (HANDLE)0);
  if (h == INVALID_HANDLE_VALUE)
    {
      RegDeleteValueW(key, UNISTR(n));
      return nil;
    }
  else
    {
      CloseHandle(h);	// OK
      return n;
    }
}

+ (NSString *) _translate: (NSString *)name
{
  NSData		*data;

  /*
   * Make sure name is representable in the registry ...
   * assume base64 encoded strings are valid.
   */
  data = [name dataUsingEncoding: NSUTF8StringEncoding];
  data = [GSMimeDocument encodeBase64: data];
  name = [[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding];
  AUTORELEASE(name);
  return name;
}

- (NSPort*) portForName: (NSString *)name
{
  return [self portForName: name onHost: @""];
}

- (NSPort*) portForName: (NSString *)name
		 onHost: (NSString *)host
{
  NSString	*n;

  NSDebugLLog(@"NSMessagePortNameServer",
    @"portForName: %@ host: %@", name, host);

  if ([host length] != 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Attempt to contact a named host using a "
	@"message port name server.  This name server can only be used "
	@"to contact processes owned by the same user on the local host "
	@"(host name must be an empty string).  To contact processes "
	@"owned by other users or on other hosts you must use an instance "
	@"of the NSSocketPortNameServer class."];
    }

  n = [[self class] _query: name];
  if (n == nil)
    {
      NSDebugLLog(@"NSMessagePortNameServer", @"got no port for %@", name);
      return nil;
    }
  else
    {
      NSDebugLLog(@"NSMessagePortNameServer", @"got %@ for %@", n, name);
      return AUTORELEASE([NSMessagePort newWithName: n]);
    }
}

- (BOOL) registerPort: (NSPort *)port
	      forName: (NSString *)name
{
  NSMutableArray	*a;
  NSString		*n;
  int			rc;
  const unsigned char	*str;

  NSDebugLLog(@"NSMessagePortNameServer", @"register %@ as %@\n", port, name);
  if ([port isKindOfClass: [NSMessagePort class]] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Attempted to register a non-NSMessagePort (%@)",
	port];
      return NO;
    }

  if ([[self class] _query: name] != nil)
    {
      NSDebugLLog(@"NSMessagePortNameServer", @"fail, is a live port");
      return NO;
    }

  n = [[self class] _translate: name];
  str = [[(NSMessagePort*)port name] UTF8String];

  rc = RegSetValueExW(
    key,
    UNISTR(n),
    0,
    REG_BINARY,
    str,
    strlen(str)+1);
  if (rc == ERROR_SUCCESS)
    {
      rc = RegFlushKey(key);
      if (rc != ERROR_SUCCESS)
	{
	  NSLog(@"Failed to flush registry HKEY_CURRENT_USER\\%@\\%@ (%x)",
	    registry, n, rc);
	}
    }
  else
    {
      NSLog(@"Failed to insert HKEY_CURRENT_USER\\%@\\%@ (%x) %@",
	registry, n, rc, [NSError _last]);
      return NO;
    }

  [serverLock lock];
  a = NSMapGet(portToNamesMap, port);
  if (a != nil)
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
  NSString	*n;
  int		rc;

  NSDebugLLog(@"NSMessagePortNameServer", @"removePortForName: %@", name);
  n = [[self class] _translate: name];
  rc = RegDeleteValueW(key, UNISTR(n));

  return YES;
}

- (NSArray *) namesForPort: (NSPort *)port
{
  NSMutableArray	*a;

  [serverLock lock];
  a = NSMapGet(portToNamesMap, port);
  a = [a copy];
  [serverLock unlock];
  return AUTORELEASE(a);
}

- (BOOL) removePort: (NSPort *)port
{
  NSMutableArray *a;
  int		i;

  NSDebugLLog(@"NSMessagePortNameServer", @"removePort: %@", port);

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
  NSDebugLLog(@"NSMessagePortNameServer",
    @"removePort: %@  forName: %@", port, name);

  if ([self portForName: name onHost: @""] == port)
    {
      return [self removePortForName: name];
    }
  return NO;
}

@end

