/** GSHTTPURLHandle.m - Class GSHTTPURLHandle
   Copyright (C) 2000 Free Software Foundation, Inc.

   Written by: 		Mark Allison <mark@brainstorm.co.uk>
   Integrated by:	Richard Frith-Macdonald <rfm@gnu.org>
   Date:		November 2000 		

   This file is part of the GNUstep Library.

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

#include "config.h"
#include "Foundation/NSArray.h"
#include "Foundation/NSString.h"
#include "Foundation/NSException.h"
#include "Foundation/NSValue.h"
#include "Foundation/NSData.h"
#include "Foundation/NSURL.h"
#include "Foundation/NSURLHandle.h"
#include "Foundation/NSNotification.h"
#include "Foundation/NSRunLoop.h"
#include "Foundation/NSByteOrder.h"
#include "Foundation/NSLock.h"
#include "Foundation/NSFileHandle.h"
#include "Foundation/NSDebug.h"
#include "Foundation/NSHost.h"
#include "Foundation/NSProcessInfo.h"
#include "Foundation/NSPathUtilities.h"
#include "GNUstepBase/GSMime.h"
#include "GNUstepBase/GSLock.h"
#include <string.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/file.h>

#ifdef HAVE_SYS_FCNTL_H
#include <sys/fcntl.h>		// For O_WRONLY, etc
#endif

static NSString	*httpVersion = @"1.1";

@interface GSHTTPURLHandle : NSURLHandle
{
  BOOL			tunnel;
  BOOL			debug;
  BOOL			keepalive;
  NSFileHandle          *sock;
  NSURL                 *url;
  NSURL                 *u;
  NSMutableData         *dat;
  GSMimeParser		*parser;
  GSMimeDocument	*document;
  NSMutableDictionary   *pageInfo;
  NSMutableDictionary   *wProperties;
  NSData		*wData;
  NSMutableDictionary   *request;
  unsigned int          bodyPos;
  unsigned int		redirects;
  enum {
    idle,
    connecting,
    writing,
    reading,
  } connectionState;
}
- (void) setDebug: (BOOL)flag;
- (void) _tryLoadInBackground: (NSURL*)fromURL;
@end

/**
 * <p>
 *   This is a <em>PRIVATE</em> subclass of NSURLHandle.
 *   It is documented here in order to give you information about the
 *   default behavior of an NSURLHandle created to deal with a URL
 *   that has either the <code>http</code> or <code>https</code> scheme.
 *   The name and/or other implementation details of this class
 *   may be changed at any time.
 * </p>
 * <p>
 *   A GSHTTPURLHandle instance is used to manage connections to
 *   <code>http</code> and <code>https</code> URLs.
 *    Secure connections are handled automatically
 *   (using openSSL) for URLs with the scheme <code>https</code>.
 *   Connection via proxy server is supported, as is proxy tunneling
 *   for secure connections.  Basic parsing of <code>http</code>
 *   headers is performed to extract <code>http</code> status
 *   information, cookies etc.  Cookies are
 *   retained and automatically sent during subsequent requests where
 *   the cookie is valid.
 * </p>
 * <p>
 *   Header information from the current page may be obtained using
 *   -propertyForKey and -propertyForKeyIfAvailable.  <code>HTTP</code>
 *   status information can be retrieved as by calling either of these
 *   methods specifying one of the following keys:
 * </p>
 * <list>
 *   <item>
 *     NSHTTPPropertyStatusCodeKey - numeric status code
 *   </item>
 *   <item>
 *     NSHTTPPropertyStatusReasonKey - text describing status
 *   </item>
 *   <item>
 *     NSHTTPPropertyServerHTTPVersionKey - <code>http</code>
 *     version supported by remote server
 *   </item>
 * </list>
 * <p>
 *   According to MacOS-X headers, the following should also
 *   be supported, but currently are not:
 * </p>
 * <list>
 *   <item>NSHTTPPropertyRedirectionHeadersKey</item>
 *   <item>NSHTTPPropertyErrorPageDataKey</item>
 * </list>
 * <p>
 *   The omission of these headers is not viewed as important at
 *   present, since the MacOS-X public beta implementation doesn't
 *   work either.
 * </p>
 * <p>
 *   Other calls to -propertyForKey and -propertyForKeyIfAvailable may
 *   be made specifying a <code>http</code> header field name.
 *   For example specifying a key name of &quot;Content-Length&quot;
 *   would return the value of the &quot;Content-Length&quot; header
 *   field.
 * </p>
 * <p>
 *   [GSHTTPURLHandle-writeProperty:forKey:]
 *   can be used to specify the parameters
 *   for the <code>http</code> request.  The default request uses the
 *   &quot;GET&quot; method when fetching a page, and the
 *   &quot;POST&quot; method when using -writeData:.
 *   This can be over-ridden by calling -writeProperty:forKey: with
 *   the key name &quot;GSHTTPPropertyMethodKey&quot; and specifying an
 *   alternative method (i.e &quot;PUT&quot;).
 * </p>
 * <p>
 *   A Proxy may be specified by calling -writeProperty:forKey:
 *   with the keys &quot;GSHTTPPropertyProxyHostKey&quot; and
 *   &quot;GSHTTPPropertyProxyPortKey&quot; to set the host and port
 *   of the proxy server respectively.  The GSHTTPPropertyProxyHostKey
 *   property can be set to either the IP address or the hostname of
 *   the proxy server.  If an attempt is made to load a page via a
 *   secure connection when a proxy is specified, GSHTTPURLHandle will
 *   attempt to open an SSL Tunnel through the proxy.
 * </p>
 * <p>
 *   Requests to the remote server may be forced to be bound to a
 *   particular local IP address by using the key
 *   &quot;GSHTTPPropertyLocalHostKey&quot;  which must contain the
 *   IP address of a network interface on the local host.
 * </p>
 */
@implementation GSHTTPURLHandle

static NSMutableDictionary	*urlCache = nil;
static NSLock			*urlLock = nil;

static Class			sslClass = 0;

static NSLock			*debugLock = nil;
static NSString			*debugFile;

static void debugRead(GSHTTPURLHandle *handle, NSData *data)
{
  NSString	*s;
  int		d;

  [debugLock lock];
  d = open([debugFile  fileSystemRepresentation],
	   O_WRONLY|O_CREAT|O_APPEND, 0644);
  if (d >= 0)
    {
      s = [NSString stringWithFormat: @"\nRead for %x at %@ %u bytes - '",
	handle, [NSDate date], [data length]];
      write(d, [s cString], [s cStringLength]);
      write(d, [data bytes], [data length]);
      write(d, "'", 1);
      close(d);
    }
  [debugLock unlock];
}
static void debugWrite(GSHTTPURLHandle *handle, NSData *data)
{
  NSString	*s;
  int		d;

  [debugLock lock];
  d = open([debugFile  fileSystemRepresentation],
	   O_WRONLY|O_CREAT|O_APPEND, 0644);
  if (d >= 0)
    {
      s = [NSString stringWithFormat: @"\nWrite for %x at %@ %u bytes - '",
	handle, [NSDate date], [data length]];
      write(d, [s cString], [s cStringLength]);
      write(d, [data bytes], [data length]);
      write(d, "'", 1);
      close(d);
    }
  [debugLock unlock];
}

+ (NSURLHandle*) cachedHandleForURL: (NSURL*)newUrl
{
  NSURLHandle	*obj = nil;

  if ([[newUrl scheme] caseInsensitiveCompare: @"http"] == NSOrderedSame
    || [[newUrl scheme] caseInsensitiveCompare: @"https"] == NSOrderedSame)
    {
      NSString	*page = [newUrl absoluteString];
      //NSLog(@"Lookup for handle for '%@'", page);
      [urlLock lock];
      obj = [urlCache objectForKey: page];
      AUTORELEASE(RETAIN(obj));
      [urlLock unlock];
      //NSLog(@"Found handle %@", obj);
    }
  return obj;
}

+ (void) initialize
{
  if (self == [GSHTTPURLHandle class])
    {
      urlCache = [NSMutableDictionary new];
      urlLock = [GSLazyLock new];
      debugLock = [GSLazyLock new];
      debugFile = [NSString stringWithFormat: @"%@/GSHTTP.%d",
			     NSTemporaryDirectory(),
			     [[NSProcessInfo processInfo] processIdentifier]];
      RETAIN(debugFile);

#ifndef __MINGW__
      sslClass = [NSFileHandle sslClass];
#endif
    }
}

- (void) dealloc
{
  if (sock != nil)
    {
      NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];

      /*
       * We might be in an idle state with an outstandng read on the
       * socket, keeping the connection alive, but waiting for the
       * remote end to drop it.
       */
      [nc removeObserver: self
		    name: NSFileHandleReadCompletionNotification
		  object: sock];
      [sock closeFile];
      DESTROY(sock);
    }
  DESTROY(u);
  DESTROY(url);
  DESTROY(dat);
  DESTROY(parser);
  DESTROY(document);
  DESTROY(pageInfo);
  DESTROY(wData);
  DESTROY(wProperties);
  DESTROY(request);
  [super dealloc];
}

- (id) initWithURL: (NSURL*)newUrl
	    cached: (BOOL)cached
{
  if ((self = [super initWithURL: newUrl cached: cached]) != nil)
    {
      dat = [NSMutableData new];
      pageInfo = [NSMutableDictionary new];
      wProperties = [NSMutableDictionary new];
      request = [NSMutableDictionary new];

      ASSIGN(url, newUrl);
      connectionState = idle;
      if (cached == YES)
        {
	  NSString	*page = [newUrl absoluteString];

	  [urlLock lock];
	  [urlCache setObject: self forKey: page];
	  [urlLock unlock];
	  //NSLog(@"Cache handle %@ for '%@'", self, page);
	}
    }
  return self;
}

+ (BOOL) canInitWithURL: (NSURL*)newUrl
{
  if ([[newUrl scheme] isEqualToString: @"http"]
    || [[newUrl scheme] isEqualToString: @"https"])
    {
      return YES;
    }
  return NO;
}

- (void) bgdApply: (NSString*)basic
{
  NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
  NSEnumerator          *wpEnumerator;
  NSMutableString	*s;
  NSString              *key;
  NSMutableData		*buf;
  NSString		*version;

  if (debug) NSLog(@"%@ %s", NSStringFromSelector(_cmd), keepalive?"K":"");

  s = [basic mutableCopy];
  if ([[u query] length] > 0)
    {
      [s appendFormat: @"?%@", [u query]];
    }

  version = [request objectForKey: NSHTTPPropertyServerHTTPVersionKey];
  if (version == nil)
    {
      version = httpVersion;
    }
  [s appendFormat: @" HTTP/%@\r\n", version];

  if ([wProperties objectForKey: @"host"] == nil)
    {
      [wProperties setObject: [u host] forKey: @"host"];
    }

  if ([wData length] > 0)
    {
      [wProperties setObject: [NSString stringWithFormat: @"%d", [wData length]]
		      forKey: @"content-length"];
      /*
       * Assume content type if not specified.
       */
      if ([wProperties objectForKey: @"content-type"] == nil)
	{
	  [wProperties setObject: @"application/x-www-form-urlencoded"
			  forKey: @"content-type"];
	}
    }
  if ([wProperties objectForKey: @"authorization"] == nil)
    {
      if ([u user] != nil)
	{
	  NSString	*auth;

	  if ([[u password] length] > 0)
	    {
	      auth = [NSString stringWithFormat: @"%@:%@",
		[u user], [u password]];
	    }
	  else
	    {
	      auth = [NSString stringWithFormat: @"%@", [u user]];
	    }
	  auth = [NSString stringWithFormat: @"Basic %@",
	    [GSMimeDocument encodeBase64String: auth]];
	  [wProperties setObject: auth
			  forKey: @"authorization"];
	}
    }

  wpEnumerator = [wProperties keyEnumerator];
  while ((key = [wpEnumerator nextObject]))
    {
      [s appendFormat: @"%@: %@\r\n", key, [wProperties objectForKey: key]];
    }
  [s appendString: @"\r\n"];
  buf = [[s dataUsingEncoding: NSASCIIStringEncoding] mutableCopy];

  /*
   * Append any data to be sent
   */
  if (wData != nil)
    {
      [buf appendData: wData];
    }

  /*
   * Watch for write completion.
   */
  [nc addObserver: self
         selector: @selector(bgdWrite:)
             name: GSFileHandleWriteCompletionNotification
           object: sock];
  connectionState = writing;

  /*
   * Send request to server.
   */
  if (debug == YES) debugWrite(self, buf);
  [sock writeInBackgroundAndNotify: buf];
  RELEASE(buf);
  RELEASE(s);
}

- (void) bgdRead: (NSNotification*) not
{
  NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
  NSDictionary		*dict = [not userInfo];
  NSData		*d;
  NSRange		r;

  if (debug) NSLog(@"%@ %s", NSStringFromSelector(_cmd), keepalive?"K":"");
  d = [dict objectForKey: NSFileHandleNotificationDataItem];
  if (debug == YES) debugRead(self, d);

  if (connectionState == idle)
    {
      /*
       * We received an event on a handle which is not in use ...
       * it should just be the connection being closed by the other
       * end because of a timeout etc.
       */
      if (debug == YES && [d length] != 0)
	{
	  NSLog(@"%@ %s Unexpected data from remote!",
	    NSStringFromSelector(_cmd), keepalive?"K":"");
	}
      [nc removeObserver: self
		    name: NSFileHandleReadCompletionNotification
		  object: sock];
      [sock closeFile];
      DESTROY(sock);
    }
  else if ([parser parse: d] == NO)
    {
      if (debug == YES)
	{
	  NSLog(@"HTTP parse failure - %@", parser);
	}
      [self endLoadInBackground];
      [self backgroundLoadDidFailWithReason: @"Response parse failed"];
    }
  else
    {
      BOOL	complete = [parser isComplete];

      if (complete == NO && [parser isInHeaders] == NO)
	{
	  GSMimeHeader	*info;
	  NSString	*enc;
	  NSString	*len;
	  NSString	*status;
	  float		ver;

	  info = [document headerNamed: @"http"];
	  ver = [[info value] floatValue];
	  status = [info objectForKey: NSHTTPPropertyStatusCodeKey];
	  len = [[document headerNamed: @"content-length"] value];
	  enc = [[document headerNamed: @"content-transfer-encoding"] value];
	  if (enc == nil)
	    {
	      enc = [[document headerNamed: @"transfer-encoding"] value];
	    }

	  if ([status isEqual: @"204"] || [status isEqual: @"304"])
	    {
	      complete = YES;	// No body expected.
	    }
	  else if ([enc isEqualToString: @"chunked"] == YES)	
	    {
	      complete = NO;	// Read chunked body data
	    }
	  else
	    {
	      complete = NO;	// No
	    }
	}
      if (complete == YES)
	{
	  GSMimeHeader	*info;
	  NSString	*val;
	  float		ver;

	  connectionState = idle;

	  ver = [[[document headerNamed: @"http"] value] floatValue];
	  val = [[document headerNamed: @"connection"] value];
	  if (ver < 1.1 || (val != nil && [val isEqual: @"close"] == YES))
	    {
	      [nc removeObserver: self
			    name: NSFileHandleReadCompletionNotification
			  object: sock];
	      [sock closeFile];
	      DESTROY(sock);
	    }

	  /*
	   * Retrieve essential keys from document
	   */
	  info = [document headerNamed: @"http"];
	  val = [info objectForKey: NSHTTPPropertyServerHTTPVersionKey];
	  if (val != nil)
	    {
	      [pageInfo setObject: val
			   forKey: NSHTTPPropertyServerHTTPVersionKey];
	    }
	  val = [info objectForKey: NSHTTPPropertyStatusCodeKey];
	  if (val != nil)
	    {
	      [pageInfo setObject: val forKey: NSHTTPPropertyStatusCodeKey];
	    }
	  val = [info objectForKey: NSHTTPPropertyStatusReasonKey];
	  if (val != nil)
	    {
	      [pageInfo setObject: val forKey: NSHTTPPropertyStatusReasonKey];
	    }
	  /*
	   * Tell superclass that we have successfully loaded the data.
	   */
	  d = [parser data];
	  r = NSMakeRange(bodyPos, [d length] - bodyPos);
	  bodyPos = 0;
	  DESTROY(wData);
	  [wProperties removeAllObjects];
	  [self didLoadBytes: [d subdataWithRange: r]
		loadComplete: YES];
	}
      else
	{
	  /*
	   * Report partial data if possible.
	   */
	  if ([parser isInBody])
	    {
	      d = [parser data];
	      r = NSMakeRange(bodyPos, [d length] - bodyPos);
	      bodyPos = [d length];
	      [self didLoadBytes: [d subdataWithRange: r]
		    loadComplete: NO];
	    }
	}
      if (sock != nil)
	{
	  [sock readInBackgroundAndNotify];
	}
    }
}

- (void) bgdTunnelRead: (NSNotification*) not
{
  NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
  NSDictionary		*dict = [not userInfo];
  NSData		*d;
  GSMimeParser		*p = [GSMimeParser new];

  if (debug) NSLog(@"%@ %s", NSStringFromSelector(_cmd), keepalive?"K":"");
  d = [dict objectForKey: NSFileHandleNotificationDataItem];
  if (debug == YES) debugRead(self, d);

  if ([d length] > 0)
    {
      [dat appendData: d];
    }
  [p parse: dat];
  if ([p isInBody] == YES || [d length] == 0)
    {
      GSMimeHeader	*info;
      NSString		*val;

      [p parse: nil];
      info = [[p mimeDocument] headerNamed: @"http"];
      val = [info objectForKey: NSHTTPPropertyServerHTTPVersionKey];
      if (val != nil)
	[pageInfo setObject: val forKey: NSHTTPPropertyServerHTTPVersionKey];
      val = [info objectForKey: NSHTTPPropertyStatusCodeKey];
      if (val != nil)
	[pageInfo setObject: val forKey: NSHTTPPropertyStatusCodeKey];
      val = [info objectForKey: NSHTTPPropertyStatusReasonKey];
      if (val != nil)
	[pageInfo setObject: val forKey: NSHTTPPropertyStatusReasonKey];
      [nc removeObserver: self
	            name: NSFileHandleReadCompletionNotification
                  object: sock];
      [dat setLength: 0];
      tunnel = NO;
    }
  else
    {
      [sock readInBackgroundAndNotify];
    }
  RELEASE(p);
}

- (void) loadInBackground
{
  [self _tryLoadInBackground: nil];
}

- (void) endLoadInBackground
{
  DESTROY(wData);
  [wProperties removeAllObjects];
  if (connectionState != idle)
    {
      NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];
      NSString			*name;

      if (connectionState == connecting)
	name = GSFileHandleConnectCompletionNotification;
      else if (connectionState == writing)
	name = GSFileHandleWriteCompletionNotification;
      else
	name = NSFileHandleReadCompletionNotification;

      [nc removeObserver: self name: name object: sock];
      [sock closeFile];
      DESTROY(sock);
      connectionState = idle;
    }
  [super endLoadInBackground];
}

- (void) bgdConnect: (NSNotification*)notification
{
  NSNotificationCenter	*nc = [NSNotificationCenter defaultCenter];

  NSDictionary          *userInfo = [notification userInfo];
  NSMutableString	*s;
  NSString		*e;
  NSString		*method;
  NSString		*path;

  if (debug) NSLog(@"%@ %s", NSStringFromSelector(_cmd), keepalive?"K":"");

  path = [[u path] stringByTrimmingSpaces];
  if ([path length] == 0)
    {
      path = @"/";
    }

  /*
   * See if the connection attempt caused an error.
   */
  e = [userInfo objectForKey: GSFileHandleNotificationError];
  if (e != nil)
    {
      NSLog(@"Unable to connect to %@:%@ via socket ... %@",
	[sock socketAddress], [sock socketService], e);
      /*
       * Tell superclass that the load failed - let it do housekeeping.
       */
      [self endLoadInBackground];
      [self backgroundLoadDidFailWithReason: e];
      return;
    }

  [nc removeObserver: self
                name: GSFileHandleConnectCompletionNotification
              object: sock];

  /*
   * Build HTTP request.
   */

  /*
   * If SSL via proxy, set up tunnel first
   */
  if ([[u scheme] isEqualToString: @"https"]
    && [[request objectForKey: GSHTTPPropertyProxyHostKey] length] > 0)
    {
      NSRunLoop		*loop = [NSRunLoop currentRunLoop];
      NSString		*cmd;
      NSTimeInterval	last = 0.0;
      NSTimeInterval	limit = 0.01;
      NSData		*buf;
      NSDate		*when;
      NSString		*status;
      NSString		*version;

      version = [request objectForKey: NSHTTPPropertyServerHTTPVersionKey];
      if (version == nil)
	{
	  version = httpVersion;
	}
      if ([u port] == nil)
	{
	  cmd = [NSString stringWithFormat: @"CONNECT %@:443 HTTP/%@\r\n\r\n",
	    [u host], version];
	}
      else
	{
	  cmd = [NSString stringWithFormat: @"CONNECT %@:%@ HTTP/%@\r\n\r\n",
	    [u host], [u port], version];
	}

      /*
       * Set up default status for if connection is lost.
       */
      [pageInfo setObject: @"1.0" forKey: NSHTTPPropertyServerHTTPVersionKey];
      [pageInfo setObject: @"503" forKey: NSHTTPPropertyStatusCodeKey];
      [pageInfo setObject: @"Connection dropped by proxy server"
		   forKey: NSHTTPPropertyStatusReasonKey];

      tunnel = YES;
      [nc addObserver: self
	     selector: @selector(bgdWrite:)
                 name: GSFileHandleWriteCompletionNotification
               object: sock];

      buf = [cmd dataUsingEncoding: NSASCIIStringEncoding];
      if (debug == YES) debugWrite(self, buf);
      [sock writeInBackgroundAndNotify: buf];

      when = [NSDate alloc];
      while (tunnel == YES)
	{
	  if (limit < 1.0)
	    {
	      NSTimeInterval	tmp = limit;

	      limit += last;
	      last = tmp;
	    }
          when = [when initWithTimeIntervalSinceNow: limit];
	  [loop runUntilDate: when];
	}
      RELEASE(when);

      status = [pageInfo objectForKey: NSHTTPPropertyStatusCodeKey];
      if ([status isEqual: @"200"] == NO)
	{
	  [self endLoadInBackground];
	  [self backgroundLoadDidFailWithReason: @"Failed proxy tunneling"];
	  return;
	}
    }
  if ([[u scheme] isEqualToString: @"https"])
    {
      /*
       * If we are an https connection, negotiate secure connection
       */
      if ([sock sslConnect] == NO)
	{
	  [self endLoadInBackground];
	  [self backgroundLoadDidFailWithReason:
	    @"Failed to make ssl connect"];
	  return;
	}
    }

  /*
   * Set up request - differs for proxy version unless tunneling via ssl.
   */
  method = [request objectForKey: GSHTTPPropertyMethodKey];
  if (method == nil)
    {
      if ([wData length] > 0)
	{
	  method = @"POST";
	}
      else
	{
	  method = @"GET";
	}
    }
  if ([[request objectForKey: GSHTTPPropertyProxyHostKey] length] > 0
    && [[u scheme] isEqualToString: @"https"] == NO)
    {
      if ([u port] == nil)
	{
	  s = [[NSMutableString alloc] initWithFormat: @"%@ http://%@%@",
	    method, [u host], path];
	}
      else
	{
	  s = [[NSMutableString alloc] initWithFormat: @"%@ http://%@:%@%@",
	    method, [u host], [u port], path];
	}
    }
  else    // no proxy
    {
      s = [[NSMutableString alloc] initWithFormat: @"%@ %@",
	method, path];
    }

  [self bgdApply: s];
  RELEASE(s);
}

- (void) bgdWrite: (NSNotification*)notification
{
  NSNotificationCenter	*nc;
  NSDictionary    	*userInfo = [notification userInfo];
  NSString        	*e;

  if (debug) NSLog(@"%@ %s", NSStringFromSelector(_cmd), keepalive?"K":"");
  e = [userInfo objectForKey: GSFileHandleNotificationError];
  if (e != nil)
    {
      tunnel = NO;
      if (keepalive == YES)
	{
	  /*
	   * The write failed ... connection dropped ... and we
	   * are re-using an existing connection (keepalive = YES)
	   * then we may try again with a new connection.
	   */
	  nc = [NSNotificationCenter defaultCenter];
	  [nc removeObserver: self
			name: GSFileHandleWriteCompletionNotification
		      object: sock];
	  [sock closeFile];
	  DESTROY(sock);
	  connectionState = idle;
	  [self _tryLoadInBackground: u];
	  return;
	}
      NSLog(@"Failed to write command to socket - %@", e);
      /*
       * Tell superclass that the load failed - let it do housekeeping.
       */
      [self endLoadInBackground];
      [self backgroundLoadDidFailWithReason: @"Failed to write request"];
      return;
    }
  else
    {
      /*
       * Don't watch for write completions any more.
       */
      nc = [NSNotificationCenter defaultCenter];
      [nc removeObserver: self
		    name: GSFileHandleWriteCompletionNotification
		  object: sock];

      /*
       * Ok - write completed, let's read the response.
       */
      if (tunnel == YES)
	{
	  [nc addObserver: self
	         selector: @selector(bgdTunnelRead:)
		     name: NSFileHandleReadCompletionNotification
	           object: sock];
	}
      else
	{
	  bodyPos = 0;
	  [nc addObserver: self
	         selector: @selector(bgdRead:)
		     name: NSFileHandleReadCompletionNotification
	           object: sock];
	}
      if ([sock readInProgress] == NO)
	{
	  [sock readInBackgroundAndNotify];
	}
      connectionState = reading;
    }
}

/**
 *  If necessary, this method calls -loadInForeground to send a
 *  request to the webserver, and get a page back.  It then returns
 *  the property for the specified key -
 * <list>
 *   <item>
 *     NSHTTPPropertyStatusCodeKey - numeric status code returned
 *     by the last request.
 *   </item>
 *   <item>
 *     NSHTTPPropertyStatusReasonKey - text describing status of
 *     the last request
 *   </item>
 *   <item>
 *     NSHTTPPropertyServerHTTPVersionKey - <code>http</code>
 *     version supported by remote server
 *   </item>
 *   <item>
 *     Other keys are taken to be the names of <code>http</code>
 *     headers and the corresponding header value (or nil if there
 *     is none) is returned.
 *   </item>
 * </list>
 */
- (id) propertyForKey: (NSString*) propertyKey
{
  if (document == nil)
    [self loadInForeground];
  return [self propertyForKeyIfAvailable: propertyKey];
}

- (id) propertyForKeyIfAvailable: (NSString*) propertyKey
{
  id	result = [pageInfo objectForKey: propertyKey];

  if (result == nil)
    {
      NSString	*key = [propertyKey lowercaseString];
      NSArray	*array = [document headersNamed: key];

      if ([array count] == 0)
	{
	  return nil;
	}
      else if ([array count] == 1)
	{
	  GSMimeHeader	*hdr = [array objectAtIndex: 0];

	  result = [hdr value];
	}
      else
	{
	  NSEnumerator	*enumerator = [array objectEnumerator];
	  GSMimeHeader	*val;

	  result = [NSMutableArray arrayWithCapacity: [array count]];
	  while ((val = [enumerator nextObject]) != nil)
	    {
	      [result addObject: [val value]];
	    }
	}
    }
  return result;
}

- (void) setDebug: (BOOL)flag
{
  debug = flag;
}

- (void) _tryLoadInBackground: (NSURL*)fromURL
{
  NSNotificationCenter	*nc;
  NSString		*host = nil;
  NSString		*port = nil;
  NSString		*s;

  /*
   * Don't start a load if one is in progress.
   */
  if (connectionState != idle)
    {
      NSLog(@"Attempt to load an http handle which is not idle ... ignored");
      return;
    }

  [dat setLength: 0];
  RELEASE(document);
  RELEASE(parser);
  parser = [GSMimeParser new];
  document = RETAIN([parser mimeDocument]);

  /*
   * First time round, fromURL is nil, so we use the url ivar and
   * we notify that the load is begining.  On retries we get a real
   * value in fromURL to use.
   */
  if (fromURL == nil)
    {
      redirects = 0;
      ASSIGN(u, url);
      [self beginLoadInBackground];
    }
  else
    {
      ASSIGN(u, fromURL);
    }

  host = [u host];
  port = (id)[u port];
  if (port != nil)
    {
      port = [NSString stringWithFormat: @"%u", [port intValue]];
    }
  else
    {
      port = [u scheme];
    }
  if ([port isEqualToString: @"https"])
    {
      port = @"443";
    }
  else if ([port isEqualToString: @"http"])
    {
      port = @"80";
    }

  if (sock == nil)
    {
      keepalive = NO;	// New connection
      /*
       * If we have a local address specified,
       * tell the file handle to bind to it.
       */
      s = [request objectForKey: GSHTTPPropertyLocalHostKey];
      if ([s length] > 0)
	{
	  s = [NSString stringWithFormat: @"bind-%@", s];
	}
      else
	{
	  s = @"tcp";	// Bind to any.
	}

      if ([[request objectForKey: GSHTTPPropertyProxyHostKey] length] == 0)
	{
	  if ([[u scheme] isEqualToString: @"https"])
	    {
	      NSString	*cert;

	      if (sslClass == 0)
		{
		  [self backgroundLoadDidFailWithReason:
		    @"https not supported ... needs SSL bundle"];
		  return;
		}
	      sock = [sslClass fileHandleAsClientInBackgroundAtAddress: host
							       service: port
							      protocol: s];
	      cert = [request objectForKey: GSHTTPPropertyCertificateFileKey];
	      if ([cert length] > 0)
		{
		  NSString	*key;
		  NSString	*pwd;

		  key = [request objectForKey: GSHTTPPropertyKeyFileKey];
		  pwd = [request objectForKey: GSHTTPPropertyPasswordKey];
		  [sock sslSetCertificate: cert privateKey: key PEMpasswd: pwd];
		}
	    }
	  else
	    {
	      sock = [NSFileHandle fileHandleAsClientInBackgroundAtAddress: host
								   service: port
								  protocol: s];
	    }
	}
      else
	{
	  if ([[request objectForKey: GSHTTPPropertyProxyPortKey] length] == 0)
	    {
	      [request setObject: @"8080" forKey: GSHTTPPropertyProxyPortKey];
	    }
	  if ([[u scheme] isEqualToString: @"https"])
	    {
	      if (sslClass == 0)
		{
		  [self backgroundLoadDidFailWithReason:
		    @"https not supported ... needs SSL bundle"];
		  return;
		}
	      host = [request objectForKey: GSHTTPPropertyProxyHostKey];
	      port = [request objectForKey: GSHTTPPropertyProxyPortKey];
	      sock = [sslClass fileHandleAsClientInBackgroundAtAddress: host
							       service: port
							      protocol: s];
	    }
	  else
	    {
	      host = [request objectForKey: GSHTTPPropertyProxyHostKey];
	      port = [request objectForKey: GSHTTPPropertyProxyPortKey];
	      sock = [NSFileHandle
		fileHandleAsClientInBackgroundAtAddress: host
						service: port
					       protocol: s];
	    }
	}
      if (sock == nil)
	{
	  extern int errno;

	  /*
	   * Tell superclass that the load failed - let it do housekeeping.
	   */
	  [self backgroundLoadDidFailWithReason: [NSString stringWithFormat:
	    @"Unable to connect to %@:%@ ... %s",
	    host, port, GSLastErrorStr(errno)]];
	  return;
	}
      RETAIN(sock);
      nc = [NSNotificationCenter defaultCenter];
      [nc addObserver: self
	     selector: @selector(bgdConnect:)
		 name: GSFileHandleConnectCompletionNotification
	       object: sock];
      connectionState = connecting;
    }
  else
    {
      NSString	*method;
      NSString	*path;
      NSString	*basic;

      // Stop waiting for connection to be closed down.
      nc = [NSNotificationCenter defaultCenter];
      [nc removeObserver: self
		    name: NSFileHandleReadCompletionNotification
		  object: sock];

      keepalive = YES;	// Reusing a connection.
      method = [request objectForKey: GSHTTPPropertyMethodKey];
      if (method == nil)
	{
	  if ([wData length] > 0)
	    {
	      method = @"POST";
	    }
	  else
	    {
	      method = @"GET";
	    }
	}
      path = [[u path] stringByTrimmingSpaces];
      if ([path length] == 0)
	{
	  path = @"/";
	}
      basic = [NSString stringWithFormat: @"%@ %@", method, path];
      [self bgdApply: basic];
    }
}

/**
 * Writes the specified data as the body of an <code>http</code>
 * or <code>https</code> request to the web server.
 * Returns YES on success,
 * NO on failure.  By default, this method performs a POST operation.
 * On completion, the resource data for this handle is set to the
 * page returned by the request.
 */
- (BOOL) writeData: (NSData*)d
{
  ASSIGN(wData, d);
  return YES;
}

/**
 * Sets a property to be used in the next request made by this handle.
 * The property is set as a header in the next request, unless it is
 * one of the following -
 * <list>
 *   <item>
 *     GSHTTPPropertyBodyKey - set an NSData item to be sent to
 *     the server as the body of the request.
 *   </item>
 *   <item>
 *     GSHTTPPropertyMethodKey - override the default method of
 *     the request (eg. &quot;PUT&quot;).
 *   </item>
 *   <item>
 *     GSHTTPPropertyProxyHostKey - specify the name or IP address
 *     of a host to proxy through.
 *   </item>
 *   <item>
 *     GSHTTPPropertyProxyPortKey - specify the port number to
 *     connect to on the proxy host.  If not give, this defaults
 *     to 8080 for <code>http</code> and 4430 for <code>https</code>.
 *   </item>
 *   <item>
 *     Any NSHTTPProperty... key
 *   </item>
 * </list>
 */
- (BOOL) writeProperty: (id) property forKey: (NSString*) propertyKey
{
  if (propertyKey == nil
    || [propertyKey isKindOfClass: [NSString class]] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"%@ with invalid key", NSStringFromSelector(_cmd)];
    }
  if ([propertyKey hasPrefix: @"GSHTTPProperty"]
    || [propertyKey hasPrefix: @"NSHTTPProperty"])
    {
      if (property == nil)
	{
	  [request removeObjectForKey: propertyKey];
	}
      else
	{
	  [request setObject: property forKey: propertyKey];
	}
    }
  else
    {
      if (property == nil)
	{
	  [wProperties removeObjectForKey: [propertyKey lowercaseString]];
	}
      else
	{
	  [wProperties setObject: property
			  forKey: [propertyKey lowercaseString]];
	}
    }
  return YES;
}

@end

