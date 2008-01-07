/* Implementation for NSURLProtocol for GNUstep
   Copyright (C) 2006 Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <frm@gnu.org>
   Date: 2006
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */ 

#import <Foundation/NSError.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSValue.h>

#import "GNUstepBase/GSMime.h"

#import "GSPrivate.h"
#import "GSURLPrivate.h"


@interface _NSAboutURLProtocol : NSURLProtocol
@end

@interface _NSFTPURLProtocol : NSURLProtocol
@end

@interface _NSFileURLProtocol : NSURLProtocol
@end

@interface _NSHTTPURLProtocol : NSURLProtocol
  <NSURLAuthenticationChallengeSender>
{
  GSMimeParser		*_parser;	// Parser handling incoming data
  unsigned		_parseOffset;	// Bytes of body loaded in parser.
  float			_version;	// The HTTP version in use.
  int			_statusCode;	// The HTTP status code returned.
  NSInputStream		*_body;		// for sending the body
  unsigned		_writeOffset;	// Request data to write
  NSData		*_writeData;	// Request bytes written so far
  BOOL			_complete;
  BOOL			_debug;
  BOOL			_isLoading;
  BOOL			_shouldClose;
  NSURLAuthenticationChallenge	*_challenge;
  NSURLCredential		*_credential;
  NSHTTPURLResponse		*_response;
}
@end

@interface _NSHTTPSURLProtocol : _NSHTTPURLProtocol
@end



// Internal data storage
typedef struct {
  NSInputStream			*input;
  NSOutputStream		*output;
  NSCachedURLResponse		*cachedResponse;
  id <NSURLProtocolClient>	client;		// Not retained
  NSURLRequest			*request;
} Internal;
 
typedef struct {
  @defs(NSURLProtocol)
} priv;
#define	this	((Internal*)(((priv*)self)->_NSURLProtocolInternal))
#define	inst	((Internal*)(((priv*)o)->_NSURLProtocolInternal))

static NSMutableArray	*registered = nil;
static NSLock		*regLock = nil;
static Class		abstractClass = nil;
static NSURLProtocol	*placeholder = nil;

@implementation	NSURLProtocol

+ (id) allocWithZone: (NSZone*)z
{
  NSURLProtocol	*o;

  if ((self == abstractClass) && (z == 0 || z == NSDefaultMallocZone()))
    {
      /* Return a default placeholder instance to avoid the overhead of
       * creating and destroying instances of the abstract class.
       */
      o = placeholder;
    }
  else
    {
      /* Create and return an instance of the concrete subclass.
       */
      o = (NSURLProtocol*)NSAllocateObject(self, 0, z);
    }
  return o;
}

+ (void) initialize
{
  if (registered == nil)
    {
      abstractClass = [NSURLProtocol class];
      placeholder = (NSURLProtocol*)NSAllocateObject(abstractClass, 0,
	NSDefaultMallocZone());
      registered = [NSMutableArray new];
      regLock = [NSLock new];
      [self registerClass: [_NSHTTPURLProtocol class]];
      [self registerClass: [_NSHTTPSURLProtocol class]];
      [self registerClass: [_NSFTPURLProtocol class]];
      [self registerClass: [_NSFileURLProtocol class]];
      [self registerClass: [_NSAboutURLProtocol class]];
    }
}

+ (id) propertyForKey: (NSString *)key inRequest: (NSURLRequest *)request
{
  return [request _propertyForKey: key];
}

+ (BOOL) registerClass: (Class)protocolClass
{
  if ([protocolClass isSubclassOfClass: [NSURLProtocol class]] == YES)
    {
      [regLock lock];
      [registered addObject: protocolClass];
      [regLock unlock];
      return YES;
    }
  return NO;
}

+ (void) setProperty: (id)value
	      forKey: (NSString *)key
	   inRequest: (NSMutableURLRequest *)request
{
  [request _setProperty: value forKey: key];
}

+ (void) unregisterClass: (Class)protocolClass
{
  [regLock lock];
  [registered removeObjectIdenticalTo: protocolClass];
  [regLock unlock];
}

- (NSCachedURLResponse *) cachedResponse
{
  return this->cachedResponse;
}

- (id <NSURLProtocolClient>) client
{
  return this->client;
}

- (void) dealloc
{
  if (self == placeholder)
    {
      [self retain];
      return;
    }
  if (this != 0)
    {
      [self stopLoading];
      RELEASE(this->input);
      RELEASE(this->output);
      RELEASE(this->cachedResponse);
      RELEASE(this->request);
      NSZoneFree([self zone], this);
      _NSURLProtocolInternal = 0;
    }
  [super dealloc];
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"%@ %@",
    [super description], this ? (id)this->request : nil];
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      if (isa != abstractClass)
	{
	  _NSURLProtocolInternal = NSZoneCalloc(GSObjCZone(self),
	    1, sizeof(Internal));
	}
    }
  return self;
}

- (id) initWithRequest: (NSURLRequest *)request
	cachedResponse: (NSCachedURLResponse *)cachedResponse
		client: (id <NSURLProtocolClient>)client
{
  if (isa == abstractClass)
    {
      unsigned	count;

      DESTROY(self);
      [regLock lock];
      count = [registered count];
      while (count-- > 0)
        {
	  Class	proto = [registered objectAtIndex: count];

	  if ([proto canInitWithRequest: request] == YES)
	    {
	      self = [proto alloc];
	      break;
	    }
	}
      [regLock unlock];
      return [self initWithRequest: request
		    cachedResponse: cachedResponse
			    client: client];
    }
  if ((self = [self init]) != nil)
    {
      this->request = [request copy];
      this->cachedResponse = RETAIN(cachedResponse);
      this->client = client;	// Not retained
    }
  return self;
}

- (NSURLRequest *) request
{
  return this->request;
}

@end


@implementation	NSURLProtocol (Subclassing)

+ (BOOL) canInitWithRequest: (NSURLRequest *)request
{
  [self subclassResponsibility: _cmd];
  return NO;
}

+ (NSURLRequest *) canonicalRequestForRequest: (NSURLRequest *)request
{
  return request;
}

+ (BOOL) requestIsCacheEquivalent: (NSURLRequest *)a
			toRequest: (NSURLRequest *)b
{
  a = [self canonicalRequestForRequest: a];
  b = [self canonicalRequestForRequest: b];
  return [a isEqual: b];
}

- (void) startLoading
{
  [self subclassResponsibility: _cmd];
}

- (void) stopLoading
{
  [self subclassResponsibility: _cmd];
}

@end






@implementation _NSHTTPURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"http"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) cancelAuthenticationChallenge: (NSURLAuthenticationChallenge*)c
{
  if (c == _challenge)
    {
      DESTROY(_challenge);	// We should cancel the download
    }
}

- (void) continueWithoutCredentialForAuthenticationChallenge:
  (NSURLAuthenticationChallenge*)c
{
  if (c == _challenge)
    {
      DESTROY(_credential);	// We download the challenge page
    }
}

- (void) _didInitializeOutputStream: (NSOutputStream*)stream
{
  return;
}

- (void) dealloc
{
  [_parser release];			// received headers
  [_body release];			// for sending the body
  [_response release];
  [_credential release];
  [_credential release];
  [super dealloc];
}

- (void) _schedule
{
  [this->input scheduleInRunLoop: [NSRunLoop currentRunLoop]
			 forMode: NSDefaultRunLoopMode];
  [this->output scheduleInRunLoop: [NSRunLoop currentRunLoop]
			  forMode: NSDefaultRunLoopMode];
}

- (void) startLoading
{
  static NSDictionary *methods = nil;

  if (methods == nil)
    {
      methods = [[NSDictionary alloc] initWithObjectsAndKeys: 
	self, @"HEAD",
	self, @"GET",
	self, @"POST",
	self, @"PUT",
	self, @"DELETE",
	self, @"TRACE",
	self, @"OPTIONS",
	self, @"CONNECT",
	nil];
      }
  if ([methods objectForKey: [this->request HTTPMethod]] == nil)
    {
      NSLog(@"Invalid HTTP Method: %@", this->request);
      [self stopLoading];
      [this->client URLProtocol: self didFailWithError:
	[NSError errorWithDomain: @"Invalid HTTP Method"
			    code: 0
			userInfo: nil]];
      return;
    }
  if (_isLoading == YES)
    {
      NSLog(@"startLoading when load in progress");
      return;
    }

  _statusCode = 0;	/* No status returned yet.	*/
  _isLoading = YES;
  _complete = NO;
  _debug = NO;

  /* Perform a redirect if the path is empty.
   * As per MacOs-X documentation.
   */
  if ([[[this->request URL] path] length] == 0)
    {
      NSString		*s = [[this->request URL] absoluteString];
      NSURL		*url;

      if ([s rangeOfString: @"?"].length > 0)
        {
	  s = [s stringByReplacingString: @"?" withString: @"/?"];
	}
      else if ([s rangeOfString: @"#"].length > 0)
        {
	  s = [s stringByReplacingString: @"#" withString: @"/#"];
	}
      else
        {
          s = [s stringByAppendingString: @"/"];
	}
      url = [NSURL URLWithString: s];
      if (url == nil)
	{
	  NSError	*e;

	  e = [NSError errorWithDomain: @"Invalid redirect request"
				  code: 0
			      userInfo: nil];
	  [self stopLoading];
	  [this->client URLProtocol: self
		   didFailWithError: e];
	}
      else
	{
	  NSMutableURLRequest	*request;

	  request = [this->request mutableCopy];
	  [request setURL: url];
	  [this->client URLProtocol: self
	     wasRedirectedToRequest: request
		   redirectResponse: nil];
	}
      if (_isLoading == NO)
        {
	  return;
	}
    }

  if (0 && this->cachedResponse)
    {
    }
  else
    {
      NSURL	*url = [this->request URL];
      NSHost	*host = [NSHost hostWithName: [url host]];
      int	port = [[url port] intValue];

      _parseOffset = 0;
      DESTROY(_parser);

      if (host == nil)
        {
	  host = [NSHost hostWithAddress: [url host]];	// try dotted notation
	}
      if (host == nil)
        {
	  host = [NSHost hostWithAddress: @"127.0.0.1"];	// final default
	}
      if (port == 0)
        {
	  // default if not specified
	  port = [[url scheme] isEqualToString: @"https"] ? 433 : 80;
	}

      [NSStream getStreamsToHost: host
			    port: port
		     inputStream: &this->input
		    outputStream: &this->output];
      if (!this->input || !this->output)
	{
	  if (_debug == YES)
	    {
	      NSLog(@"did not create streams for %@:%@", host, [url port]);
	    }
	  [self stopLoading];
	  [this->client URLProtocol: self didFailWithError:
	    [NSError errorWithDomain: @"can't connect" code: 0 userInfo: 
	      [NSDictionary dictionaryWithObjectsAndKeys: 
		url, @"NSErrorFailingURLKey",
		host, @"NSErrorFailingURLStringKey",
		@"can't find host", @"NSLocalizedDescription",
		nil]]];
	  return;
	}
      RETAIN(this->input);
      RETAIN(this->output);
      [self _didInitializeOutputStream: this->output];
      if ([[url scheme] isEqualToString: @"https"] == YES)
        {
          [this->input setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                            forKey: NSStreamSocketSecurityLevelKey];
          [this->output setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                             forKey: NSStreamSocketSecurityLevelKey];
        }
      [this->input setDelegate: self];
      [this->output setDelegate: self];
      [self _schedule];
      [this->input open];
      [this->output open];
    }
}

- (void) _unschedule
{
  [this->input removeFromRunLoop: [NSRunLoop currentRunLoop]
			 forMode: NSDefaultRunLoopMode];
  [this->output removeFromRunLoop: [NSRunLoop currentRunLoop]
			  forMode: NSDefaultRunLoopMode];
}

- (void) stopLoading
{
  if (_debug == YES)
    {
      NSLog(@"stopLoading: %@", self);
    }
  _isLoading = NO;
  DESTROY(_writeData);
  if (this->input != nil)
    {
      [self _unschedule];
      [this->input close];
      [this->output close];
      DESTROY(this->input);
      DESTROY(this->output);
    }
}


- (void) _got: (NSStream*)stream
{
  unsigned char	buffer[BUFSIZ*64];
  int 		readCount;
  NSError	*e;
  NSData	*d;
  BOOL		wasInHeaders = NO;

  readCount = [(NSInputStream *)stream read: buffer
				  maxLength: sizeof(buffer)];
  if (readCount < 0)
    {
      if ([stream  streamStatus] == NSStreamStatusError)
        {
	  e = [stream streamError];
	  if (_debug)
	    {
	      NSLog(@"receive error %@", e);
	    }
	  [self stopLoading];
	  [this->client URLProtocol: self didFailWithError: e];
	}
      return;
    }
  if (_debug)
    {
      NSLog(@"Read %d bytes: '%*.*s'", readCount, readCount, readCount, buffer);
    }

  if (_parser == nil)
    {
      _parser = [GSMimeParser new];
      [_parser setIsHttp];
    }
  wasInHeaders = [_parser isInHeaders];
  d = [NSData dataWithBytes: buffer length: readCount];
  if ([_parser parse: d] == NO && (_complete = [_parser isComplete]) == NO)
    {
      if (_debug == YES)
	{
	  NSLog(@"HTTP parse failure - %@", _parser);
	}
      e = [NSError errorWithDomain: @"parse error"
			      code: 0
			  userInfo: nil];
      [self stopLoading];
      [this->client URLProtocol: self didFailWithError: e];
      return;
    }
  else
    {
      BOOL		isInHeaders = [_parser isInHeaders];
      GSMimeDocument	*document = [_parser mimeDocument];
      unsigned		bodyLength;

      if (wasInHeaders == YES && isInHeaders == NO)
        {
	  GSMimeHeader		*info;
	  NSString		*enc;
	  int			len = -1;
	  NSString		*s;

	  info = [document headerNamed: @"http"];

	  _version = [[info value] floatValue];
	  if (_version < 1.1)
	    {
	      _shouldClose = YES;
	    }
	  else if ((s = [[document headerNamed: @"connection"] value]) != nil
	    && [s caseInsensitiveCompare: @"close"] == NSOrderedSame)
	    {
	      _shouldClose = YES;
	    }
	  else
	    {
	      _shouldClose = NO;	// Keep connection alive.
	    }

	  s = [info objectForKey: NSHTTPPropertyStatusCodeKey];
	  _statusCode = [s intValue];

	  s = [[document headerNamed: @"content-length"] value];
	  if ([s length] > 0)
	    {
	      len = [s intValue];
	    }

	  s = [info objectForKey: NSHTTPPropertyStatusReasonKey];
	  enc = [[document headerNamed: @"content-transfer-encoding"] value];
	  if (enc == nil)
	    {
	      enc = [[document headerNamed: @"transfer-encoding"] value];
	    }

	  _response = [[NSHTTPURLResponse alloc]
	    initWithURL: [this->request URL]
	    MIMEType: nil
	    expectedContentLength: len
	    textEncodingName: nil];
	  [_response _setStatusCode: _statusCode text: s];
	  [document deleteHeaderNamed: @"http"];
	  [_response _setHeaders: [document allHeaders]];

	  if (_statusCode == 204 || _statusCode == 304)
	    {
	      _complete = YES;	// No body expected.
	    }
	  else if ([enc isEqualToString: @"chunked"] == YES)	
	    {
	      _complete = NO;	// Read chunked body data
	    }
	  if (_complete == NO && [d length] == 0)
	    {
	      _complete = YES;	// Had EOF ... terminate
	    }

	  if (_statusCode == 401)
	    {
	      /* This is an authentication challenge, so we keep reading
	       * until the challenge is complete, then try to deal with it.
	       */
	    }
	  else if ((s = [[document headerNamed: @"location"] value]) != nil)
	    {
	      NSURL	*url;

	      url = [NSURL URLWithString: s];
	      if (url == nil)
	        {
		  NSError	*e;

		  e = [NSError errorWithDomain: @"Invalid redirect request"
					  code: 0
				      userInfo: nil];
		  [self stopLoading];
		  [this->client URLProtocol: self
			   didFailWithError: e];
		}
	      else
	        {
		  NSMutableURLRequest	*request;

		  request = [this->request mutableCopy];
		  [request setURL: url];
		  [this->client URLProtocol: self
		     wasRedirectedToRequest: request
			   redirectResponse: _response];
		}
	    }
	  else
	    {
	      NSURLCacheStoragePolicy policy;

	      /* Tell the client that we have a response and how
	       * it should be cached.
	       */
	      policy = [this->request cachePolicy];
	      if (policy == NSURLRequestUseProtocolCachePolicy)
		{
		  if ([self isKindOfClass: [_NSHTTPSURLProtocol class]] == YES)
		    {
		      /* For HTTPS we should not allow caching unless the
		       * request explicitly wants it.
		       */
		      policy = NSURLCacheStorageNotAllowed;
		    }
		  else
		    {
		      /* For HTTP we allow caching unless the request
		       * specifically denies it.
		       */
		      policy = NSURLCacheStorageAllowed;
		    }
		}
	      [this->client URLProtocol: self
		     didReceiveResponse: _response
		     cacheStoragePolicy: policy];
	    }
	}

      if (_complete == YES)
	{
	  if (_statusCode == 401)
	    {
	      NSURLProtectionSpace	*space;
	      NSString			*hdr;
	      NSURL			*url;
	      int			failures = 0;

	      /* This was an authentication challenge.
	       */
	      hdr = [[document headerNamed: @"WWW-Authenticate"] value];
	      url = [this->request URL];
	      space = [GSHTTPAuthentication
		protectionSpaceForAuthentication: hdr requestURL: url];
	      DESTROY(_credential);	
	      if (space != nil)
		{
		  /* Create credential from user and password
		   * stored in the URL.
		   * Returns nil if we have no username or password.
		   */
		  _credential = [[NSURLCredential alloc]
		    initWithUser: [url user]
		    password: [url password]
		    persistence: NSURLCredentialPersistenceForSession];
		  if (_credential == nil)
		    {
		      /* No credential from the URL, so we try using the
		       * default credential for the protection space.
		       */
		      ASSIGN(_credential,
			[[NSURLCredentialStorage sharedCredentialStorage]
			  defaultCredentialForProtectionSpace: space]);
		    }
		}

	      if (_challenge != nil)
		{
		  /* The failure count is incremented if we have just
		   * tried a request in the same protection space.
		   */
		  if (YES == [[_challenge protectionSpace] isEqual: space])
		    {
		      failures = [_challenge previousFailureCount] + 1; 
		    }
		}
	      else if ([this->request valueForHTTPHeaderField:@"Authorization"])
		{
		  /* Our request had an authorization header, so we should
		   * count that as a failure or we wouldn't have been
		   * challenged.
		   */
		  failures = 1;
		}
	      DESTROY(_challenge);

	      _challenge = [[NSURLAuthenticationChallenge alloc]
		initWithProtectionSpace: space
		proposedCredential: _credential
		previousFailureCount: failures
		failureResponse: _response
		error: nil
		sender: self];

	      /* Allow the client to control the credential we send
	       * or whether we actually send at all.
	       */
	      [this->client URLProtocol: self
		didReceiveAuthenticationChallenge: _challenge];

	      if (_challenge == nil)
		{
		  NSError	*e;

		  /* The client cancelled the authentication challenge
		   * so we must cancel the download.
		   */
		  e = [NSError errorWithDomain: @"Authentication cancelled"
					  code: 0
				      userInfo: nil];
		  [self stopLoading];
		  [this->client URLProtocol: self
			   didFailWithError: e];
		}
	      else
		{
		  NSString	*auth = nil;

		  if (_credential != nil)
		    {
		      GSHTTPAuthentication	*authentication;

		      /* Get information about basic or
		       * digest authentication.
		       */
		      authentication = [GSHTTPAuthentication
			authenticationWithCredential: _credential
			inProtectionSpace: space];

		      /* Generate authentication header value for the
		       * authentication type in the challenge.
		       */
		      auth = [authentication
			authorizationForAuthentication: hdr
			method: [this->request HTTPMethod]
			path: [url path]];
		    }

		  if (auth == nil)
		    {
		      NSURLCacheStoragePolicy policy;

		      /* We have no authentication credentials so we
		       * treat this as a download of the challenge page.
		       */

		      /* Tell the client that we have a response and how
		       * it should be cached.
		       */
		      policy = [this->request cachePolicy];
		      if (policy == NSURLRequestUseProtocolCachePolicy)
			{
			  if ([self isKindOfClass: [_NSHTTPSURLProtocol class]])
			    {
			      /* For HTTPS we should not allow caching unless
			       * the request explicitly wants it.
			       */
			      policy = NSURLCacheStorageNotAllowed;
			    }
			  else
			    {
			      /* For HTTP we allow caching unless the request
			       * specifically denies it.
			       */
			      policy = NSURLCacheStorageAllowed;
			    }
			}
		      [this->client URLProtocol: self
			     didReceiveResponse: _response
			     cacheStoragePolicy: policy];
		      /* Fall through to code providing page data.
		       */
		    }
		  else
		    {
		      NSMutableURLRequest	*request;

		      /* To answer the authentication challenge,
		       * we must retry with a modified request and
		       * with the cached response cleared.
		       */
		      request = [this->request mutableCopy];
		      [request setValue: auth
			forHTTPHeaderField: @"Authorization"];
		      [self stopLoading];
		      DESTROY(this->cachedResponse);
		      [self startLoading];
		    }
		}
	    }

	  [self _unschedule];
	  if (_shouldClose == YES)
	    {
	      [this->input close];
	      [this->output close];
	      DESTROY(this->input);
	      DESTROY(this->output);
	    }

	  /*
	   * Tell superclass that we have successfully loaded the data
	   * (as long as we haven't had the load terminated by the client).
	   */
	  if (_isLoading == YES)
	    {
	      d = [_parser data];
	      bodyLength = [d length];
	      if (bodyLength > _parseOffset)
		{
		  if (_parseOffset > 0)
		    {
		      d = [d subdataWithRange: 
			NSMakeRange(_parseOffset, bodyLength - _parseOffset)];
		    }
		  _parseOffset = bodyLength;
		  [this->client URLProtocol: self didLoadData: d];
		}

	      /* Check again in case the client cancelled the load inside
	       * the URLProtocol:didLoadData: callback.
	       */
	      if (_isLoading == YES)
	        {
		  _isLoading = NO;
	          [this->client URLProtocolDidFinishLoading: self];
		}
	    }
	}
      else if (_isLoading == YES && _statusCode != 401)
	{
	  /*
	   * Report partial data if possible.
	   */
	  if ([_parser isInBody])
	    {
	      d = [_parser data];
	      bodyLength = [d length];
	      if (bodyLength > _parseOffset)
	        {
		  if (_parseOffset > 0)
		    {
		      d = [d subdataWithRange: 
			NSMakeRange(_parseOffset, [d length] - _parseOffset)];
		    }
		  _parseOffset = bodyLength;
		  [this->client URLProtocol: self didLoadData: d];
		}
	    }
	}

      if (_complete == NO && readCount == 0 && _isLoading == YES)
	{
	  /* The read failed ... dropped, but parsing is not complete.
	   * The request was sent, so we can't know whether it was
	   * lost in the network or the remote end received it and
	   * the response was lost.
	   */
	  if (_debug == YES)
	    {
	      NSLog(@"HTTP response not received - %@", _parser);
	    }
	  [self stopLoading];
	  [this->client URLProtocol: self didFailWithError:
	    [NSError errorWithDomain: @"receive incomplete"
				code: 0
			    userInfo: nil]];
	}
    }
}

- (void) stream: (NSStream*) stream handleEvent: (NSStreamEvent) event
{
  /* Make sure no action triggered by anything else destroys us prematurely.
   */
  AUTORELEASE(RETAIN(self));

#if 0
  NSLog(@"stream: %@ handleEvent: %x for: %@", stream, event, self);
#endif

  if (stream == this->input) 
    {
      switch(event)
	{
	  case NSStreamEventHasBytesAvailable: 
	  case NSStreamEventEndEncountered:
	    [self _got: stream];
	    return;

	  case NSStreamEventOpenCompleted: 
	    if (_debug == YES)
	      {
		NSLog(@"HTTP input stream opened");
	      }
	    return;

	  default: 
	    break;
	}
    }
  else if (stream == this->output)
    {
      switch(event)
	{
	  case NSStreamEventOpenCompleted: 
	    {
	      NSMutableString	*m;
	      NSDictionary	*d;
	      NSEnumerator	*e;
	      NSString		*s;
	      NSURL		*u;
	      int		l;		

	      if (_debug == YES)
	        {
	          NSLog(@"HTTP output stream opened");
	        }
	      DESTROY(_writeData);
	      _writeOffset = 0;
	      if ([this->request HTTPBodyStream] == nil)
	        {
		  // Not streaming
		  l = [[this->request HTTPBody] length];
		  _version = 1.1;
		}
	      else
	        {
		  // Stream and close
		  l = -1;
	          _version = 1.0;
		  _shouldClose = YES;
		}

	      m = [[NSMutableString alloc] initWithCapacity: 1024];

	      /* The request line is of the form:
	       * method /path#fragment?query HTTP/version
	       * where the fragment and query parts may be missing
	       */
	      [m appendString: [this->request HTTPMethod]];
	      [m appendString: @" "];
	      u = [this->request URL];
	      s = [u path];
	      if ([s hasPrefix: @"/"] == NO)
	        {
		  [m appendString: @"/"];
		}
	      [m appendString: s];
	      s = [u fragment];
	      if ([s length] > 0)
	        {
		  [m appendString: @"#"];
		  [m appendString: s];
		}
	      s = [u query];
	      if ([s length] > 0)
	        {
		  [m appendString: @"?"];
		  [m appendString: s];
		}
	      [m appendFormat: @" HTTP/%0.1f\r\n", _version];

	      d = [this->request allHTTPHeaderFields];
	      e = [d keyEnumerator];
	      while ((s = [e nextObject]) != nil)
	        {
		  [m appendString: s];
		  [m appendString: @": "];
		  [m appendString: [d objectForKey: s]];
		  [m appendString: @"\r\n"];
		}
	      if ([this->request valueForHTTPHeaderField: @"Host"] == nil)
		{
		  [m appendFormat: @"Host: %@\r\n", [u host]];
		}
	      if (l >= 0 && [this->request
	        valueForHTTPHeaderField: @"Content-Length"] == nil)
		{
		  [m appendFormat: @"Content-Length: %d\r\n", l];
		}
	      [m appendString: @"\r\n"];	// End of headers
	      _writeData = RETAIN([m dataUsingEncoding: NSASCIIStringEncoding]);
	      RELEASE(m);
	    }			// Fall through to do the write

	  case NSStreamEventHasSpaceAvailable: 
	    {
	      int	written;
	      BOOL	sent = NO;

	      // FIXME: should also send out relevant Cookies
	      if (_writeData != nil)
		{
		  const unsigned char	*bytes = [_writeData bytes];
		  unsigned		len = [_writeData length];

		  written = [this->output write: bytes + _writeOffset
				      maxLength: len - _writeOffset];
		  if (written > 0)
		    {
		      if (_debug == YES)
		        {
			  NSLog(@"Wrote %d bytes: '%*.*s'", written,
			    written, written, bytes + _writeOffset);
			}
		      _writeOffset += written;
		      if (_writeOffset >= len)
		        {
			  DESTROY(_writeData);
			  if (_body == nil)
			    {
			      _body = RETAIN([this->request HTTPBodyStream]);
			      if (_body == nil)
				{
				  NSData	*d = [this->request HTTPBody];

				  if (d != nil)
				    {
				      _body = [NSInputStream alloc];
				      _body = [_body initWithData: d];
				      [_body open];
				    }
				  else
				    {
				      sent = YES;
				    }
				}
			    }
			}
		    }
		}
	      else if (_body != nil)
		{
		  if ([_body hasBytesAvailable])
		    {
		      unsigned char	buffer[BUFSIZ*64];
		      int		len;

		      len = [_body read: buffer maxLength: sizeof(buffer)];
		      if (len < 0)
			{
			  if (_debug == YES)
			    {
			      NSLog(@"error reading from HTTPBody stream %@",
				[NSError _last]);
			    }
			  [self stopLoading];
			  [this->client URLProtocol: self didFailWithError:
			    [NSError errorWithDomain: @"can't read body"
						code: 0
					    userInfo: nil]];
			  return;
			}
		      else if (len > 0)
		        {
			  written = [this->output write: buffer maxLength: len];
			  if (written > 0)
			    {
			      if (_debug == YES)
				{
				  NSLog(@"Wrote %d bytes: '%*.*s'", written,
				    written, written, buffer);
				}
			      len -= written;
			      if (len > 0)
			        {
				  /* Couldn't write it all now, save and try
				   * again later.
				   */
				  _writeData = [[NSData alloc] initWithBytes:
				    buffer + written length: len];
				  _writeOffset = 0;
				}
			    }
			}
		      else
		        {
			  [_body close];
			  DESTROY(_body);
			  sent = YES;
			}
		    }
		  else
		    {
		      [_body close];
		      DESTROY(_body);
		      sent = YES;
		    }
		}
	      if (sent == YES)
		{
		  if (_debug)
		    {
		      NSLog(@"request sent");
		    }
		  if (_shouldClose == YES)
		    {
		      [this->output removeFromRunLoop:
			[NSRunLoop currentRunLoop]
			forMode: NSDefaultRunLoopMode];
		      [this->output close];
		      DESTROY(this->output);
		    }
		}
	      return;  // done
	    }
	  default: 
	    break;
	}
    }
  NSLog(@"An error %@ occurred on the event %08x of stream %@ of %@", [stream streamError], event, stream, self);
  [self stopLoading];
  [this->client URLProtocol: self didFailWithError: [stream streamError]];
}

- (void) useCredential: (NSURLCredential*)credential
  forAuthenticationChallenge: (NSURLAuthenticationChallenge*)challenge
{
  if (challenge == _challenge)
    {
      ASSIGN(_credential, credential);
    }
}
@end

@implementation _NSHTTPSURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"https"];
}

- (void) _didInitializeOutputStream: (NSOutputStream *) stream
{
  [stream setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
	       forKey: NSStreamSocketSecurityLevelKey];
}

@end

@implementation _NSFTPURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"ftp"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) startLoading
{
  if (this->cachedResponse)
    { // handle from cache
    }
  else
    {
      NSURL	*url = [this->request URL];
      NSHost	*host = [NSHost hostWithName: [url host]];

      if (host == nil)
        {
	  host = [NSHost hostWithAddress: [url host]];
	}
      [NSStream getStreamsToHost: host
			    port: [[url port] intValue]
		     inputStream: &this->input
		    outputStream: &this->output];
      if (this->input == nil || this->output == nil)
	{
	  [this->client URLProtocol: self didFailWithError:
	    [NSError errorWithDomain: @"can't connect"
				code: 0
			    userInfo: nil]];
	  return;
	}
      RETAIN(this->input);
      RETAIN(this->output);
      if ([[url scheme] isEqualToString: @"https"] == YES)
        {
          [this->input setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                            forKey: NSStreamSocketSecurityLevelKey];
          [this->output setProperty: NSStreamSocketSecurityLevelNegotiatedSSL
                             forKey: NSStreamSocketSecurityLevelKey];
        }
      [this->input setDelegate: self];
      [this->output setDelegate: self];
      [this->input scheduleInRunLoop: [NSRunLoop currentRunLoop]
			     forMode: NSDefaultRunLoopMode];
      [this->output scheduleInRunLoop: [NSRunLoop currentRunLoop]
			      forMode: NSDefaultRunLoopMode];
      // set socket options for ftps requests
      [this->input open];
      [this->output open];
    }
}

- (void) stopLoading
{
  if (this->input)
    {
      [this->input removeFromRunLoop: [NSRunLoop currentRunLoop]
			     forMode: NSDefaultRunLoopMode];
      [this->output removeFromRunLoop: [NSRunLoop currentRunLoop]
			      forMode: NSDefaultRunLoopMode];
      [this->input close];
      [this->output close];
      DESTROY(this->input);
      DESTROY(this->output);
    }
}

- (void) stream: (NSStream *) stream handleEvent: (NSStreamEvent) event
{
  if (stream == this->input) 
    {
      switch(event)
	{
	  case NSStreamEventHasBytesAvailable: 
	    {
	    NSLog(@"FTP input stream has bytes available");
	    // implement FTP protocol
//			[this->client URLProtocol: self didLoadData: [NSData dataWithBytes: buffer length: len]];	// notify
	    return;
	    }
	  case NSStreamEventEndEncountered: 	// can this occur in parallel to NSStreamEventHasBytesAvailable???
		  NSLog(@"FTP input stream did end");
		  [this->client URLProtocolDidFinishLoading: self];
		  return;
	  case NSStreamEventOpenCompleted: 
		  // prepare to receive header
		  NSLog(@"FTP input stream opened");
		  return;
	  default: 
		  break;
	}
    }
  else if (stream == this->output)
    {
      NSLog(@"An event occurred on the output stream.");
  	// if successfully opened, send out FTP request header
    }
  NSLog(@"An error %@ occurred on the event %08x of stream %@ of %@",
    [stream streamError], event, stream, self);
  [this->client URLProtocol: self didFailWithError: [stream streamError]];
}

@end

@implementation _NSFileURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"file"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) startLoading
{
  // check for GET/PUT/DELETE etc so that we can also write to a file
  NSData	*data;
  NSURLResponse	*r;

  data = [NSData dataWithContentsOfFile: [[this->request URL] path]
  /* options: error: - don't use that because it is based on self */];
  if (data == nil)
    {
      [this->client URLProtocol: self didFailWithError:
	[NSError errorWithDomain: @"can't load file" code: 0 userInfo:
	  [NSDictionary dictionaryWithObjectsAndKeys: 
	    [this->request URL], @"URL",
	    [[this->request URL] path], @"path",
	    nil]]];
      return;
    }

  /* FIXME ... maybe should infer MIME type and encoding from extension or BOM
   */
  r = [[NSURLResponse alloc] initWithURL: [this->request URL]
				MIMEType: @"text/html"
		   expectedContentLength: [data length]
			textEncodingName: @"unknown"];	
  [this->client URLProtocol: self
    didReceiveResponse: r
    cacheStoragePolicy: NSURLRequestUseProtocolCachePolicy];
  [this->client URLProtocol: self didLoadData: data];
  [this->client URLProtocolDidFinishLoading: self];
  RELEASE(r);
}

- (void) stopLoading
{
  return;
}

@end

@implementation _NSAboutURLProtocol

+ (BOOL) canInitWithRequest: (NSURLRequest*)request
{
  return [[[request URL] scheme] isEqualToString: @"about"];
}

+ (NSURLRequest*) canonicalRequestForRequest: (NSURLRequest*)request
{
  return request;
}

- (void) startLoading
{
  NSURLResponse	*r;
  NSData	*data = [NSData data];	// no data

  // we could pass different content depending on the [url path]
  r = [[NSURLResponse alloc] initWithURL: [this->request URL]
				MIMEType: @"text/html"
		   expectedContentLength: 0
			textEncodingName: @"utf-8"];	
  [this->client URLProtocol: self
    didReceiveResponse: r
    cacheStoragePolicy: NSURLRequestUseProtocolCachePolicy];
  [this->client URLProtocol: self didLoadData: data];
  [this->client URLProtocolDidFinishLoading: self];
  RELEASE(r);
}

- (void) stopLoading
{
  return;
}

@end
