/** Interface for MIME parsing classes

   Copyright (C) 2000 Free Software Foundation, Inc.

   Written by:  Richard frith-Macdonald  <rfm@gnu.org>

   Date: October 2000
   
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

   AutogsdocSource: Additions/GSMime.m
*/

#ifndef __GSMIME_H__
#define __GSMIME_H__

#ifdef NeXT_Foundation_LIBRARY
#include <Foundation/Foundation.h>
#else
#include	<Foundation/NSObject.h>
#include	<Foundation/NSString.h>
#endif

@class	NSArray;
@class	NSMutableArray;
@class	NSData;
@class	NSMutableData;
@class	NSDictionary;
@class	NSMutableDictionary;
@class	NSScanner;

/*
 * A trivial class for mantaining state while decoding/encoding data.
 * Each encoding type requires its own subclass.
 */
@interface	GSMimeCodingContext : NSObject
{
  BOOL		atEnd;	/* Flag to say that data has ended.	*/
}
- (BOOL) atEnd;
- (BOOL) decodeData: (const void*)sData
             length: (unsigned)length
	   intoData: (NSMutableData*)dData;
- (void) setAtEnd: (BOOL)flag;
@end

@interface      GSMimeHeader : NSObject <NSCopying>
{
  NSString              *name;
  NSString              *value;
  NSMutableDictionary   *objects;
  NSMutableDictionary   *params;
}
+ (NSString*) makeQuoted: (NSString*)v always: (BOOL)flag;
+ (NSString*) makeToken: (NSString*)t;
- (id) copyWithZone: (NSZone*)z;
- (id) initWithName: (NSString*)n
	      value: (NSString*)v;
- (id) initWithName: (NSString*)n
	      value: (NSString*)v
	 parameters: (NSDictionary*)p;
- (NSString*) name;
- (id) objectForKey: (NSString*)k;
- (NSDictionary*) objects;
- (NSString*) parameterForKey: (NSString*)k;
- (NSDictionary*) parameters;
- (NSMutableData*) rawMimeData;
- (void) setName: (NSString*)s;
- (void) setObject: (id)o  forKey: (NSString*)k;
- (void) setParameter: (NSString*)v forKey: (NSString*)k;
- (void) setParameters: (NSDictionary*)d;
- (void) setValue: (NSString*)s;
- (NSString*) text;
- (NSString*) value;
@end


@interface	GSMimeDocument : NSObject <NSCopying>
{
  NSMutableArray	*headers;
  id			content;
}

+ (NSString*) charsetFromEncoding: (NSStringEncoding)enc;
+ (NSData*) decode: (NSData*)uuencoded UUName: (NSString**)namePtr;
+ (NSData*) decodeBase64: (NSData*)source;
+ (NSString*) decodeBase64String: (NSString*)source;
+ (GSMimeDocument*) documentWithContent: (id)newContent
				   type: (NSString*)type
				   name: (NSString*)name;
+ (NSData*) encode: (NSData*)data UUName: (NSString*)name;
+ (NSData*) encodeBase64: (NSData*)source;
+ (NSString*) encodeBase64String: (NSString*)source;
+ (NSStringEncoding) encodingFromCharset: (NSString*)charset;

- (void) addContent: (id)newContent;
- (void) addHeader: (GSMimeHeader*)info;
- (GSMimeHeader*) addHeader: (NSString*)name
                      value: (NSString*)value
		 parameters: (NSDictionary*)parameters;
- (NSArray*) allHeaders;
- (id) content;
- (id) contentByID: (NSString*)key;
- (id) contentByName: (NSString*)key;
- (id) copyWithZone: (NSZone*)z;
- (NSString*) contentFile;
- (NSString*) contentID;
- (NSString*) contentName;
- (NSString*) contentSubtype;
- (NSString*) contentType;
- (NSArray*) contentsByName: (NSString*)key;
- (NSData*) convertToData;
- (NSString*) convertToText;
- (void) deleteContent: (GSMimeDocument*)aPart;
- (void) deleteHeader: (GSMimeHeader*)aHeader;
- (void) deleteHeaderNamed: (NSString*)name;
- (GSMimeHeader*) headerNamed: (NSString*)name;
- (NSArray*) headersNamed: (NSString*)name;
- (NSString*) makeBoundary;
- (GSMimeHeader*) makeContentID;
- (GSMimeHeader*) makeHeader: (NSString*)name
                       value: (NSString*)value
		  parameters: (NSDictionary*)parameters;
- (GSMimeHeader*) makeMessageID;
- (NSMutableData*) rawMimeData;
- (NSMutableData*) rawMimeData: (BOOL)isOuter;
- (void) setContent: (id)newContent;
- (void) setContent: (id)newContent
	       type: (NSString*)type;
- (void) setContent: (id)newContent
	       type: (NSString*)type
	       name: (NSString*)name;
- (void) setContentType: (NSString*)newType;
- (void) setHeader: (GSMimeHeader*)info;
- (GSMimeHeader*) setHeader: (NSString*)name
                      value: (NSString*)value
		 parameters: (NSDictionary*)parameters;

@end

@interface	GSMimeParser : NSObject
{
  NSMutableData		*data;
  unsigned char		*bytes;
  unsigned		dataEnd;
  unsigned		sectionStart;
  unsigned		lineStart;
  unsigned		lineEnd;
  unsigned		input;
  unsigned		expect;
  unsigned		rawBodyLength;
  struct {
    unsigned int	inBody:1;
    unsigned int	isHttp:1;
    unsigned int	complete:1;
    unsigned int	hadErrors:1;
    unsigned int	buggyQuotes:1;
    unsigned int	wantEndOfLine:1;
  } flags;
  NSData		*boundary;
  GSMimeDocument	*document;
  GSMimeParser		*child;
  GSMimeCodingContext	*context;
}

+ (GSMimeDocument*) documentFromData: (NSData*)mimeData;
+ (GSMimeParser*) mimeParser;

- (GSMimeCodingContext*) contextFor: (GSMimeHeader*)info;
- (NSData*) data;
- (BOOL) decodeData: (NSData*)sData
	  fromRange: (NSRange)aRange
	   intoData: (NSMutableData*)dData
	withContext: (GSMimeCodingContext*)con;
- (void) expectNoHeaders;
- (BOOL) isComplete;
- (BOOL) isHttp;
- (BOOL) isInBody;
- (BOOL) isInHeaders;
- (GSMimeDocument*) mimeDocument;
- (BOOL) parse: (NSData*)d;
- (BOOL) parseHeader: (NSString*)aHeader;
- (BOOL) scanHeaderBody: (NSScanner*)scanner into: (GSMimeHeader*)info;
- (NSString*) scanName: (NSScanner*)scanner;
- (BOOL) scanPastSpace: (NSScanner*)scanner;
- (NSString*) scanSpecial: (NSScanner*)scanner;
- (NSString*) scanToken: (NSScanner*)scanner;
- (void) setBuggyQuotes: (BOOL)flag;
- (void) setIsHttp;
@end

#endif
