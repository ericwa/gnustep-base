/* NSURL.h - Class NSURL
   Copyright (C) 1999 Free Software Foundation, Inc.
   
   Written by: 	Manuel Guesdon <mguesdon@sbuilders.com>
   Date:	Jan 1999
   
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

#ifndef _NSURL_h__
#define _NSURL_h__

#include <Foundation/NSURLHandle.h>

#ifndef	STRICT_OPENSTEP

@class NSNumber;

/**
 *  URL scheme constant for use with [NSURL-initWithScheme:host:path:].
 */
GS_EXPORT NSString* NSURLFileScheme;

@interface NSURL: NSObject <NSCoding, NSCopying, NSURLHandleClient>
{
  NSString	*_urlString;
  NSURL		*_baseURL;
  void		*_clients;
  void		*_data;
}
        
+ (id) fileURLWithPath: (NSString*)aPath;
+ (id) URLWithString: (NSString*)aUrlString;
+ (id) URLWithString: (NSString*)aUrlString
       relativeToURL: (NSURL*)aBaseUrl;

- (id) initFileURLWithPath: (NSString*)aPath;
- (id) initWithScheme: (NSString*)aScheme
		 host: (NSString*)aHost
		 path: (NSString*)aPath;
- (id) initWithString: (NSString*)aUrlString;
- (id) initWithString: (NSString*)aUrlString
	relativeToURL: (NSURL*)aBaseUrl;

- (NSString*) absoluteString;
- (NSURL*) absoluteURL;
- (NSURL*) baseURL;
- (NSString*) fragment;
- (NSString*) host;
- (BOOL) isFileURL;
- (void) loadResourceDataNotifyingClient: (id)client
			      usingCache: (BOOL)shouldUseCache;
- (NSString*) parameterString;
- (NSString*) password;
- (NSString*) path;
- (NSNumber*) port;
- (id) propertyForKey: (NSString*)propertyKey;
- (NSString*) query;
- (NSString*) relativePath;
- (NSString*) relativeString;
- (NSData*) resourceDataUsingCache: (BOOL)shouldUseCache;
- (NSString*) resourceSpecifier;
- (NSString*) scheme;
- (BOOL) setProperty: (id)property
	      forKey: (NSString*)propertyKey;
- (BOOL) setResourceData: (NSData*)data;
- (NSURL*) standardizedURL;
- (NSURLHandle*)URLHandleUsingCache: (BOOL)shouldUseCache;
- (NSString*) user;

@end

@interface NSObject (NSURLClient)

/**
 * Some data has become available.  Note that this does not mean that all data
 * has become available, only that a chunk of data has arrived.
 */
- (void) URL: (NSURL*)sender
  resourceDataDidBecomeAvailable: (NSData*)newBytes;

/**
 * Loading of resource data is complete.
 */
- (void) URLResourceDidFinishLoading: (NSURL*)sender;

/**
 * Loading of resource data was canceled by programmatic request (not an error).
 */
- (void) URLResourceDidCancelLoading: (NSURL*)sender;

/**
 * Loading of resource data has failed, for given human-readable reason.
 */
- (void) URL: (NSURL*)sender
  resourceDidFailLoadingWithReason: (NSString*)reason;
@end

#endif

#endif //_NSUrl_h__
