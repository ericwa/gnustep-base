/** Implementation for GSMIME

   Copyright (C) 2000,2001 Free Software Foundation, Inc.

   Written by: Richard frith-Macdonald <rfm@gnu.org>
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

   <title>The MIME parsing system</title>
   <chapter>
      <heading>Mime Parser</heading>
      <p>
        The GNUstep Mime parser.  This is collection Objective-C classes
        for representing MIME (and HTTP) documents and managing conversions
        to and from convenient internal formats.
      </p>
      <p>
        Eventually the goal is to center round three classes -
      </p>
      <deflist>
        <term>document</term>
        <desc>
          A container for the actual data (and headers) of a mime/http document.        </desc>
        <term>parser</term>
        <desc>
          An object that can be fed data and will parse it into a document.
          This object also provides various utility methods  and an API
          that permits overriding in order to extend the functionality to
          cope with new document types.
        </desc>
        <term>unparser</term>
        <desc>
          An object to take a mime/http document and produce a data object
          suitable for transmission.
        </desc>
      </deflist>
   </chapter>
   $Date$ $Revision$
*/

#include	<Foundation/Foundation.h>
#include	<gnustep/base/GSMime.h>
#include	<string.h>
#include	<ctype.h>

static unsigned		_count = 0;

static	NSCharacterSet	*specials = nil;

/*
 *	Name -		decodebase64()
 *	Purpose -	Convert 4 bytes in base64 encoding to 3 bytes raw data.
 */
static void
decodebase64(unsigned char *dst, const char *src)
{
  dst[0] =  (src[0]         << 2) | ((src[1] & 0x30) >> 4);
  dst[1] = ((src[1] & 0x0F) << 4) | ((src[2] & 0x3C) >> 2);
  dst[2] = ((src[2] & 0x03) << 6) |  (src[3] & 0x3F);
}

typedef	enum {
  WE_QUOTED,
  WE_BASE64
} WE;

/*
 *	Name -		decodeWord()
 *	Params -	dst destination
 *			src where to start decoding from
 *			end where to stop decoding (or NULL if end of buffer).
 *			enc content-transfer-encoding
 *	Purpose -	Decode text with BASE64 or QUOTED-PRINTABLE codes.
 */
static unsigned char*
decodeWord(unsigned char *dst, unsigned char *src, unsigned char *end, WE enc)
{
  int	c;

  if (enc == WE_QUOTED)
    {
      while (*src && (src != end))
	{
	  if (*src == '=')
	    {
	      src++;
	      if (*src == '\0')
		{
		  break;
		}
	      if (('\n' == *src) || ('\r' == *src))
		{
		  break;
		}
	      c = isdigit(*src) ? (*src - '0') : (*src - 55);
	      c <<= 4;
	      src++;
	      if (*src == '\0')
		{
		  break;
		}
	      c += isdigit(*src) ? (*src - '0') : (*src - 55);
	      *dst = c;
	    }
	  else if (*src == '_')
	    {
	      *dst = '\040';
	    }
	  else
	    {
	      *dst = *src;
	    }
	  dst++;
	  src++;
	}
      *dst = '\0';
      return dst;
    }
  else if (enc == WE_BASE64)
    {
      unsigned char	buf[4];
      unsigned		pos = 0;

      while (*src && (src != end))
	{
	  c = *src++;
	  if (isupper(c))
	    {
	      c -= 'A';
	    }
	  else if (islower(c))
	    {
	      c = c - 'a' + 26;
	    }
	  else if (isdigit(c))
	    {
	      c = c - '0' + 52;
	    }
	  else if (c == '/')
	    {
	      c = 63;
	    }
	  else if (c == '+')
	    {
	      c = 62;
	    }
	  else if  (c == '=')
	    {
	      c = -1;
	    }
	  else if (c == '-')
	    {
	      break;		/* end    */
	    }
	  else
	    {
	      c = -1;		/* ignore */
	    }

	  if (c >= 0)
	    {
	      buf[pos++] = c;
	      if (pos == 4)
		{
		  pos = 0;
		  decodebase64(dst, buf);
		  dst += 3;
		}
	    }
	}

      if (pos > 0)
	{
	  unsigned	i;

	  for (i = pos; i < 4; i++)
	    buf[i] = '\0';
	  pos--;
	}
      decodebase64(dst, buf);
      dst += pos;
      *dst = '\0';
      return dst;
    }
  else
    {
      NSLog(@"Unsupported encoding type");
      return end;
    }
}

static NSStringEncoding
parseCharacterSet(NSString *token)
{
  if ([token compare: @"us-ascii"] == NSOrderedSame)
    return NSASCIIStringEncoding;
  if ([token compare: @"iso-8859-1"] == NSOrderedSame)
    return NSISOLatin1StringEncoding;

  return NSASCIIStringEncoding;
}

/**
 * The most rudimentary context ... this is used for decoding plain
 * text and binary dat (ie data which is not really decoded at all)
 * and all other decoding work is done by a subclass.
 */
@implementation	GSMimeCodingContext
/**
 * Returns the current value of the 'atEnd' flag.
 */
- (BOOL) atEnd
{
  return atEnd;
}

/**
 * Copying is implemented as a simple retain.
 */
- (id) copyWithZone: (NSZone*)z
{
  return RETAIN(self);
}

/**
 * Sets the current value of the 'atEnd' flag.
 */
- (void) setAtEnd: (BOOL)flag
{
  atEnd = flag;
}
@end

@interface	GSMimeBase64DecoderContext : GSMimeCodingContext
{
@public
  unsigned char	buf[4];
  unsigned	pos;
}
@end
@implementation	GSMimeBase64DecoderContext
@end

@interface	GSMimeQuotedDecoderContext : GSMimeCodingContext
{
@public
  unsigned char	buf[4];
  unsigned	pos;
}
@end
@implementation	GSMimeQuotedDecoderContext
@end

@interface	GSMimeChunkedDecoderContext : GSMimeCodingContext
{
@public
  unsigned char	buf[8];
  unsigned	pos;
  enum {
    ChunkSize,		// Reading chunk size
    ChunkExt,		// Reading chunk extensions
    ChunkEol1,		// Reading end of line after size;ext
    ChunkData,		// Reading chunk data
    ChunkEol2,		// Reading end of line after data
    ChunkFoot,		// Reading chunk footer after newline
    ChunkFootA		// Reading chunk footer
  } state;
  unsigned	size;	// Size of buffer required.
  NSMutableData	*data;
}
@end
@implementation	GSMimeChunkedDecoderContext
- (void) dealloc
{
  RELEASE(data);
  [super dealloc];
}
- (id) init
{
  self = [super init];
  if (self != nil)
    {
      data = [NSMutableData new];
    }
  return self;
}
@end



@interface GSMimeParser (Private)
- (BOOL) _decodeBody: (NSData*)data;
- (NSString*) _decodeHeader;
- (BOOL) _unfoldHeader;
@end

/**
 * <p>
 *   This class provides support for parsing MIME messages
 *   into GSMimeDocument objects.  Each parser object maintains
 *   an associated document into which data is stored.
 * </p>
 * <p>
 *   You supply the document to be parsed as one or more data
 *   items passed to the <code>Parse:</code> method, and (if
 *   the method always returns <code>YES</code>, you give it
 *   a final <code>nil</code> argument to mark the end of the
 *   document.
 * </p>
 * <p>
 *   On completion of parsing a valid document, the
 *   <code>document</code> method returns the resulting parsed document.
 * </p>
 */
@implementation	GSMimeParser

/**
 * Convenience method to parse a single data item as a MIME message
 * and return the resulting document.
 */
+ (GSMimeDocument*) documentFromData: (NSData*)mimeData
{
  GSMimeDocument	*newDocument = nil;
  GSMimeParser		*parser = [GSMimeParser new];

  if ([parser parse: mimeData] == YES)
    {
      [parser parse: nil];
    }
  if ([parser isComplete] == YES)
    {
      newDocument = [parser mimeDocument];
      RETAIN(newDocument);
    }
  RELEASE(parser);
  return AUTORELEASE(newDocument);
}

/**
 * Create and return a parser.
 */
+ (GSMimeParser*) mimeParser
{
  return AUTORELEASE([[self alloc] init]);
}

/**
 * Return a coding context object to be used for decoding data
 * according to the scheme specified in the header.
 * <p>
 *   The default implementation supports the following transfer
 *   encodings specified in either a <code>transfer-encoding</code>
 *   of <code>content-transfer-encoding</code> header -
 * </p>
 * <list>
 *   <item>base64</item>
 *   <item>quoted-printable</item>
 *   <item>binary (no coding actually performed)</item>
 *   <item>7bit (no coding actually performed)</item>
 *   <item>8bit (no coding actually performed)</item>
 *   <item>chunked (for HTTP/1.1)</item>
 * </list>
 */
- (GSMimeCodingContext*) contextFor: (GSMimeHeader*)info
{
  NSString	*name;
  NSString	*value;

  if (info == nil)
    {
      return AUTORELEASE([GSMimeCodingContext new]);
    }

  name = [info name];
  if ([name isEqualToString: @"content-transfer-encoding"] == YES
   || [name isEqualToString: @"transfer-encoding"] == YES)
    {
      value = [[info value] lowercaseString];
      if ([value length] == 0)
	{
	  NSLog(@"Bad value for %@ header - assume binary encoding", name);
	  return AUTORELEASE([GSMimeCodingContext new]);
	}
      if ([value isEqualToString: @"base64"] == YES)
	{
	  return AUTORELEASE([GSMimeBase64DecoderContext new]);
	}
      else if ([value isEqualToString: @"quoted-printable"] == YES)
	{
	  return AUTORELEASE([GSMimeQuotedDecoderContext new]);
	}
      else if ([value isEqualToString: @"binary"] == YES)
	{
	  return AUTORELEASE([GSMimeCodingContext new]);
	}
      else if ([value characterAtIndex: 0] == '7')
	{
	  return AUTORELEASE([GSMimeCodingContext new]);
	}
      else if ([value characterAtIndex: 0] == '8')
	{
	  return AUTORELEASE([GSMimeCodingContext new]);
	}
      else if ([value isEqualToString: @"chunked"] == YES)
	{
	  return AUTORELEASE([GSMimeChunkedDecoderContext new]);
	}
    }

  NSLog(@"contextFor: - unknown header (%@) ... assumed binary encoding", name);
  return AUTORELEASE([GSMimeCodingContext new]);
}

/**
 * Return the data accumulated in the parser.  If the parser is
 * still parsing headers, this will be the header data read so far.
 * If the parse has parsed the body of the message, this will be
 * the data of the body, with any transfer encoding removed.
 */
- (NSData*) data
{
  return data;
}

- (void) dealloc
{
  RELEASE(data);
  RELEASE(child);
  RELEASE(context);
  RELEASE(boundary);
  RELEASE(document);
  [super dealloc];
}

/**
 * <p>
 *   Decodes the raw data from the specified range in the source
 *   data object and appends it to the destination data object.
 *   The context object provides information about the content
 *   encoding type in use, and the state of the decoding operation.
 * </p>
 * <p>
 *   This method may be called repeatedly to incrementally decode
 *   information as it arrives on some communications channel.
 *   It should be called with a nil source data item (or with
 *   the atEnd flag of the context set to YES) in order to flush
 *   any information held in the context to the output data
 *   object.
 * </p>
 * <p>
 *   You may override this method in order to implement
 *   additional coding schemes.
 * </p>
 */
- (BOOL) decodeData: (NSData*)sData
	  fromRange: (NSRange)aRange
	   intoData: (NSMutableData*)dData
	withContext: (GSMimeCodingContext*)con
{
  unsigned		size = [dData length];
  unsigned		len = [sData length];
  unsigned char		*beg;
  unsigned char		*dst;
  const char		*src;
  const char		*end;
  Class			ccls;

  if (dData == nil || [con isKindOfClass: [GSMimeCodingContext class]] == NO)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Bad destination data for decode"];
    }
  GS_RANGE_CHECK(aRange, len);

  /*
   * Get pointers into source data buffer.
   */
  src = (const char *)[sData bytes];
  src += aRange.location;
  end = src + aRange.length;
  
  ccls = [con class];
  if (ccls == [GSMimeBase64DecoderContext class])
    {
      GSMimeBase64DecoderContext	*ctxt;

      ctxt = (GSMimeBase64DecoderContext*)con;

      /*
       * Expand destination data buffer to have capacity to handle info.
       */
      [dData setLength: size + (3 * (end + 8 - src))/4];
      dst = (unsigned char*)[dData mutableBytes];
      beg = dst;

      /*
       * Now decode data into buffer, keeping count and temporary
       * data in context.
       */
      while (src < end)
	{
	  int	cc = *src++;

	  if (isupper(cc))
	    {
	      cc -= 'A';
	    }
	  else if (islower(cc))
	    {
	      cc = cc - 'a' + 26;
	    }
	  else if (isdigit(cc))
	    {
	      cc = cc - '0' + 52;
	    }
	  else if (cc == '+')
	    {
	      cc = 62;
	    }
	  else if (cc == '/')
	    {
	      cc = 63;
	    }
	  else if  (cc == '=')
	    {
	      [ctxt setAtEnd: YES];
	      cc = -1;
	    }
	  else if (cc == '-')
	    {
	      [ctxt setAtEnd: YES];
	      break;
	    }
	  else
	    {
	      cc = -1;		/* ignore */
	    }

	  if (cc >= 0)
	    {
	      ctxt->buf[ctxt->pos++] = cc;
	      if (ctxt->pos == 4)
		{
		  ctxt->pos = 0;
		  decodebase64(dst, ctxt->buf);
		  dst += 3;
		}
	    }
	}

      /*
       * Odd characters at end of decoded data need to be added separately.
       */
      if ([ctxt atEnd] == YES && ctxt->pos > 0)
	{
	  unsigned	len = ctxt->pos - 1;;

	  while (ctxt->pos < 4)
	    {
	      ctxt->buf[ctxt->pos++] = '\0';
	    }
	  ctxt->pos = 0;
	  decodebase64(dst, ctxt->buf);
	  size += len;
	}
      [dData setLength: size + dst - beg];
    }
  else if (ccls == [GSMimeQuotedDecoderContext class])
    {
      GSMimeQuotedDecoderContext	*ctxt;

      ctxt = (GSMimeQuotedDecoderContext*)con;

      /*
       * Expand destination data buffer to have capacity to handle info.
       */
      [dData setLength: size + (end - src)];
      dst = (unsigned char*)[dData mutableBytes];
      beg = dst;

      while (src < end)
	{
	  if (ctxt->pos > 0)
	    {
	      if ((*src == '\n') || (*src == '\r'))
		{
		  ctxt->pos = 0;
		}
	      else
		{
		  ctxt->buf[ctxt->pos++] = *src;
		  if (ctxt->pos == 3)
		    {
		      int	c;
		      int	val;

		      ctxt->pos = 0;
		      c = ctxt->buf[1];
		      val = isdigit(c) ? (c - '0') : (c - 55);
		      val *= 0x10;
		      c = ctxt->buf[2];
		      val += isdigit(c) ? (c - '0') : (c - 55);
		      *dst++ = val;
		    }
		}
	    }
	  else if (*src == '=')
	    {
	      ctxt->buf[ctxt->pos++] = '=';
	    }
	  else
	    {
	      *dst++ = *src;
	    }
	  src++;
	}
      [dData setLength: size + dst - beg];
    }
  else if (ccls == [GSMimeChunkedDecoderContext class])
    {
      GSMimeChunkedDecoderContext	*ctxt;
      const char			*footers = src;

      ctxt = (GSMimeChunkedDecoderContext*)con;

      beg = 0;
      /*
       * Make sure buffer is big enough, and set up output pointers.
       */
      [dData setLength: ctxt->size];
      dst = (unsigned char*)[dData mutableBytes];
      dst = dst + size;
      beg = dst;

      while ([ctxt atEnd] == NO && src < end)
	{
	  switch (ctxt->state)
	    {
	      case ChunkSize:
		if (isxdigit(*src) && ctxt->pos < sizeof(ctxt->buf))
		  {
		    ctxt->buf[ctxt->pos++] = *src;
		  }
		else if (*src == ';')
		  {
		    ctxt->state = ChunkExt;
		  }
		else if (*src == '\r')
		  {
		    ctxt->state = ChunkEol1;
		  }
		else if (*src == '\n')
		  {
		    ctxt->state = ChunkData;
		  }
		src++;
		if (ctxt->state != ChunkSize)
		  {
		    int	val = 0;
		    int	index;

		    for (index = 0; index < ctxt->pos; index++)
		      {
			val *= 16;
			if (isdigit(ctxt->buf[index]))
			  {
			    val += ctxt->buf[index] - '0';
			  }
			else if (isupper(ctxt->buf[index]))
			  {
			    val += ctxt->buf[index] - 'A' + 10;
			  }
			else
			  {
			    val += ctxt->buf[index] - 'a' + 10;
			  }
		      }
		    ctxt->pos = val;
		    /*
		     * If we have read a chunk already, make sure that our
		     * destination size is updated correctly before growing
		     * the buffer for another chunk.
		     */
		    size += (dst - beg);
		    ctxt->size = size + val;
		    [dData setLength: ctxt->size];
		    dst = (unsigned char*)[dData mutableBytes];
		    dst += size;
		    beg = dst;
		  }
		break;

	    case ChunkExt:
	      if (*src == '\r')
		{
		  ctxt->state = ChunkEol1;
		}
	      else if (*src == '\n')
		{
		  ctxt->state = ChunkData;
		}
	      src++;
	      break;

	    case ChunkEol1:
	      if (*src == '\n')
		{
		  ctxt->state = ChunkData;
		}
	      src++;
	      break;

	    case ChunkData:
	      /*
	       * If the pos is non-zero, we have a data chunk to read.
	       * otherwise, what we actually want it to read footers.
	       */
	      if (ctxt->pos > 0)
		{
		  *dst++ = *src++;
		  if (--ctxt->pos == 0)
		    {
		      ctxt->state = ChunkEol2;
		    }
		}
	      else
		{
		  footers = src;		// Record start position.
		  ctxt->state = ChunkFoot;
		}
	      break;

	    case ChunkEol2:
	      if (*src == '\n')
		{
		  ctxt->state = ChunkSize;
		}
	      src++;
	      break;

	    case ChunkFoot:
	      if (*src == '\r')
		{
		  src++;
		}
	      else if (*src == '\n')
		{
		  [ctxt setAtEnd: YES];
		}
	      else
		{
		  ctxt->state = ChunkFootA;
		}
	      break;

	    case ChunkFootA:
	      if (*src == '\n')
		{
		  ctxt->state = ChunkFootA;
		}
	      src++;
	      break;
	    }
	}
      if (ctxt->state == ChunkFoot || ctxt->state == ChunkFootA)
	{
	  [ctxt->data appendBytes: footers length: src - footers];
	  if ([ctxt atEnd] == YES)
	    {
	      NSMutableData	*old;

	      /*
	       * Pretend we are back parsing the original headers ...
	       */
	      old = data;
	      data = ctxt->data;
	      bytes = (unsigned char*)[data mutableBytes];
	      dataEnd = [data length];
	      inBody = NO;

	      /*
	       * Duplicate the normal header parsing process for our footers.
	       */
	      while (inBody == NO)
		{
		  if ([self _unfoldHeader] == NO)
		    {
		      break;
		    }
		  if (inBody == NO)
		    {
		      NSString		*header;

		      header = [self _decodeHeader];
		      if (header == nil)
			{
			  break;
			}
		      if ([self parseHeader: header] == NO)
			{
			  hadErrors = YES;
			  break;
			}
		    }
		}

	      /*
	       * restore original data.
	       */
	      ctxt->data = data;
	      data = old;
	      bytes = (unsigned char*)[data mutableBytes];
	      dataEnd = [data length];
	      inBody = YES;
	    }
	}
      /*
       * Correct size of output buffer.
       */	
      [dData setLength: size + dst - beg];
    }
  else
    {
      /*
       * Assume binary (no) decoding required.
       */
      [dData setLength: size + (end - src)];
      dst = (unsigned char*)[dData mutableBytes];
      memcpy(&dst[size], src, (end - src));
    }

  /*
   * A nil data item as input represents end of data.
   */
  if (sData == nil)
    {
      [con setAtEnd: YES];
    }

  return YES;
}

- (NSString*) description
{
  NSMutableString	*desc;

  desc = [NSMutableString stringWithFormat: @"GSMimeParser <%0x> -\n", self];
  [desc appendString: [document description]];
  return desc;
}

/**
 * <deprecated />
 * Returns the object into which raw mime data is being parsed.
 */
- (id) document
{
  return document;
}

/**
 * This method may be called to tell the parser that it should not expect
 * to parse any headers, and that the data it will receive is body data.<br />
 * If the parse is already in the body, or is complete, this method has
 * no effect.<br />
 * This is for use when some other utility has been used to parse headers,
 * and you have set the headers of the document owned by the parser
 * accordingly.  You can then use the GSMimeParser to read the body data
 * into the document.
 */
- (void) expectNoHeaders
{
  if (complete == NO)
    {
      inBody = YES;
    }
}

/**
 * Returns YES if the document parsing is known to be completed successfully.
 * Returns NO if either more data is needed, or if the parser encountered an
 * error.
 */
- (BOOL) isComplete
{
  if (hadErrors == YES)
    {
      return NO;
    }
  return complete;
}

/**
 * Returns YES if the parser is parsing an HTTP document rather than
 * a true MIME document.
 */
- (BOOL) isHttp
{
  return isHttp;
}

/**
 * Returns YES if all the document headers have been parsed but
 * the document body parsing may not yet be complete.
 */
- (BOOL) isInBody
{
  return inBody;
}

/**
 * Returns YES if parsing of the document headers has not yet
 * been completed.
 */
- (BOOL) isInHeaders
{
  if (inBody == YES)
    return NO;
  if (complete == YES)
    return NO;
  return YES;
}

- (id) init
{
  self = [super init];
  if (self != nil)
    {
      data = [[NSMutableData alloc] init];
      document = [[GSMimeDocument alloc] init];
    }
  return self;
}

/**
 * Returns the GSMimeDocument instance into which data is being parsed
 * or has been parsed.
 */
- (GSMimeDocument*) mimeDocument
{
  return document;
}

/**
 * <p>
 *   This method is called repeatedly to pass raw mime data into
 *   the parser.  It returns <code>YES</code> as long as it wants
 *   more data to complete parsing of a document, and <code>NO</code>
 *   if parsing is complete, either due to having reached the end of
 *   a document or due to an error.
 * </p>
 * <p>
 *   Since it is not always possible to determine if the end of a
 *   MIME document has been reached from its content, the method
 *   may need to be called with a nil or empty argument after you have
 *   passed all the data to it ... this tells it that the data
 *   is complete.
 * </p>
 * <p>
 *   The parser attempts to be as flexible as possible and to continue
 *   parsing wherever it can.  If an error occurs in parsing, the
 *   -isComplete method will always return NO, even after the -parse:
 *   method has been called with a nil argument.
 * </p>
 * <p>
 *   A multipart document will be parsed to content consisting of an
 *   NSArray of GSMimeDocument instances representing each part.<br />
 *   Otherwise, a document will become content of type NSData, unless
 *   it is of content type <em>text</em>, in which case it will be an
 *   NSString.<br />
 *   If a document has no content type specified, it will be treated as
 *   <em>text</em>, unless it is identifiable as a <em>file</em>
 *   (eg. t has a content-disposition header containing a filename parameter). 
 * </p>
 */
- (BOOL) parse: (NSData*)d
{
  unsigned	l = [d length];

  if (complete == YES)
    {
      return NO;	/* Already completely parsed! */
    }
  if (l > 0)
    {
      NSDebugMLLog(@"GSMime", @"Parse %u bytes - '%*.*s'", l, l, l, [d bytes]);
      if (inBody == NO)
	{
	  [data appendBytes: [d bytes] length: [d length]];
	  bytes = (unsigned char*)[data mutableBytes];
	  dataEnd = [data length];

	  while (inBody == NO)
	    {
	      if ([self _unfoldHeader] == NO)
		{
		  return YES;	/* Needs more data to fill line.	*/
		}
	      if (inBody == NO)
		{
		  NSString		*header;

		  header = [self _decodeHeader];
		  if (header == nil)
		    {
		      return NO;	/* Couldn't handle words.	*/
		    }
		  if ([self parseHeader: header] == NO)
		    {
		      hadErrors = YES;
		      return NO;	/* Header not parsed properly.	*/
		    }
		  NSDebugMLLog(@"GSMime", @"Parsed header '%@'", header);
		}
	      else
		{
		  NSDebugMLLog(@"GSMime", @"Parsed end of headers");
		}
	    }
	  /*
	   * All headers have been parsed, so we empty our internal buffer
	   * (which we will now use to store decoded data) and place unused
	   * information back in the incoming data object to act as input.
	   */
	  d = AUTORELEASE([data copy]);
	  [data setLength: 0];

	  /*
	   * If we have finished parsing the headers, we may have http
	   * continuation header(s), in which case, we must start parsing
	   * headers again.
	   */
	  if (inBody == YES)
	    {
	      NSDictionary	*info;

	      info = [[document headersNamed: @"http"] lastObject];
	      if (info != nil)
		{
		  NSString	*val;

		  val = [info objectForKey: NSHTTPPropertyStatusCodeKey];
		  if (val != nil)
		    {
		      int	v = [val intValue];

		      if (v >= 100 && v < 200)
			{
			  /*
			   * This is an intermediary response ... so we have
			   * to restart the parsing operation!
			   */
			  NSDebugMLLog(@"GSMime", @"Parsed http continuation");
			  inBody = NO;
			}
		    }
		}
	    }
	}

      if ([d length] > 0)
	{
	  if (inBody == YES)
	    {
	      /*
	       * We can't just re-call -parse: ...
	       * that would lead to recursion.
	       */
	      return [self _decodeBody: d];
	    }
	  else
	    {
	      return [self parse: d];
	    }
	}

      return YES;	/* Want more data for body */
    }
  else
    {
      BOOL	result;

      if (inBody == YES)
	{
	  result = [self _decodeBody: d];
	}
      else
	{
	  /*
	   * If still parsing headers, add CR-LF sequences to terminate
	   * the headers.
           */
	  result = [self parse: [NSData dataWithBytes: @"\r\n\r\n" length: 4]];
	}
      inBody = NO;
      complete = YES;	/* Finished parsing	*/
      return result;
    }
}

/**
 * <p>
 *   This method is called to parse a header line <em>for the
 *   current document</em>, split its contents into a GSMimeHeader
 *   object, and add that information to the document.<br />
 *   The method is normally used internally by the -parse: method,
 *   but you may also call it to parse an entire header line and
 *   add it to the document (this may be useful in conjunction
 *   with the -expectNoHeaders method, to parse a document body data
 *   into a document where the headers are available from a
 *   separate source).
 * </p>
 * <example>
 *   GSMimeParser *parser = [GSMimeParser mimeParser];
 *
 *   [parser parseHeader: @"content-type: text/plain"];
 *   [parser expectNoHeaders];
 *   [parser parse: bodyData];
 *   [parser parse: nil];
 * </example>
 * <p>
 *   The standard implementation of this method scans the header
 *   name and then calls -scanHeaderBody:into: to complete the
 *   parsing of the header.
 * </p>
 * <p>
 *   This method also performs consistency checks on headers scanned
 *   so it is recommended that it is not overridden, but that
 *   subclasses override -scanHeaderBody:into: to
 *   implement custom scanning.
 * </p>
 * <p>
 *   As a special case, for HTTP support, this method also parses
 *   lines in the format of HTTP responses as if they were headers
 *   named <code>http</code>.  The resulting header object contains
 *   additional object values -
 * </p>
 * <deflist>
 *   <term>HttpMajorVersion</term>
 *   <desc>The first part of the version number</desc>
 *   <term>HttpMinorVersion</term>
 *   <desc>The second part of the version number</desc>
 *   <term>NSHTTPPropertyServerHTTPVersionKey</term>
 *   <desc>The full HTTP protocol version number</desc>
 *   <term>NSHTTPPropertyStatusCodeKey</term>
 *   <desc>The HTTP status code</desc>
 *   <term>NSHTTPPropertyStatusReasonKey</term>
 *   <desc>The text message (if any) after the status code</desc>
 * </deflist>
 */
- (BOOL) parseHeader: (NSString*)aHeader
{
  NSScanner		*scanner = [NSScanner scannerWithString: aHeader];
  NSString		*name;
  NSString		*value;
  GSMimeHeader		*info;
  NSCharacterSet	*skip;

  info = AUTORELEASE([GSMimeHeader new]);

  /*
   * Special case - permit web response status line to act like a header.
   */
  if ([scanner scanString: @"HTTP" intoString: &name] == NO
    || [scanner scanString: @"/" intoString: 0] == NO)
    {
      if ([scanner scanUpToString: @":" intoString: &name] == NO)
	{
	  NSLog(@"Not a valid header (%@)", [scanner string]);
	  return NO;
	}
      /*
       * Position scanner after colon and any white space.
       */
      if ([scanner scanString: @":" intoString: 0] == NO)
	{
	  NSLog(@"No colon terminating name in header (%@)", [scanner string]);
	  return NO;
	}
    }

  /*
   * Set the header name.
   */
  [info setName: name];
  name = [info name];
  
  skip = RETAIN([scanner charactersToBeSkipped]);
  [scanner setCharactersToBeSkipped: nil];
  [scanner scanCharactersFromSet: skip intoString: 0];
  [scanner setCharactersToBeSkipped: skip];
  RELEASE(skip);

  /*
   * Break header fields out into info dictionary.
   */
  if ([self scanHeaderBody: scanner into: info] == NO)
    {
      return NO;
    }

  /*
   * Check validity of broken-out header fields.
   */
  if ([name isEqualToString: @"mime-version"] == YES)
    {
      int	majv = 0;
      int	minv = 0;

      value = [info value];
      if ([value length] == 0)
	{
	  NSLog(@"Missing value for mime-version header");
	  return NO;
	}
      if (sscanf([value lossyCString], "%d.%d", &majv, &minv) != 2)
	{
	  NSLog(@"Bad value for mime-version header (%@)", value);
	  return NO;
	}
      [document deleteHeaderNamed: name];	// Should be unique
    }
  else if ([name isEqualToString: @"content-type"] == YES)
    {
      NSString	*type;
      NSString	*subtype;
      BOOL	supported = NO;

      DESTROY(boundary);
      type = [info objectForKey: @"Type"];
      if ([type length] == 0)
	{
	  NSLog(@"Missing Mime content-type");
	  return NO;
	}
      subtype = [info objectForKey: @"SubType"];
	
      if ([type isEqualToString: @"text"] == YES)
	{
	  if (subtype == nil)
	    subtype = @"plain";
	}
      else if ([type isEqualToString: @"application"] == YES)
	{
	  if (subtype == nil)
	    subtype = @"octet-stream";
	}
      else if ([type isEqualToString: @"multipart"] == YES)
	{
	  NSString	*tmp = [info parameterForKey: @"boundary"];

	  supported = YES;
	  if (tmp != nil)
	    {
	      unsigned int	l = [tmp cStringLength] + 2;
	      unsigned char	*b = NSZoneMalloc(NSDefaultMallocZone(), l + 1);

	      b[0] = '-';
	      b[1] = '-';
	      [tmp getCString: &b[2]];
	      ASSIGN(boundary, [NSData dataWithBytesNoCopy: b length: l]);
	    }
	  else
	    {
	      NSLog(@"multipart message without boundary");
	      return NO;
	    }
	}

      [document deleteHeaderNamed: name];	// Should be unique
    }

  return [document addHeader: info];
}

- (BOOL) scanHeaderParameters: (NSScanner*)scanner into: (GSMimeHeader*)info
{
  [self scanPastSpace: scanner];
  while ([scanner scanString: @";" intoString: 0] == YES)
    {
      NSString	*paramName;

      paramName = [self scanToken: scanner];
      if ([paramName length] == 0)
	{
	  NSLog(@"Invalid Mime %@ field (parameter name)", [info name]);
	  return NO;
	}
      [self scanPastSpace: scanner];
      if ([scanner scanString: @"=" intoString: 0] == YES)
	{
	  NSString	*paramValue;

	  [self scanPastSpace: scanner];
	  paramValue = [self scanToken: scanner];
	  [self scanPastSpace: scanner];
	  if (paramValue == nil)
	    {
	      paramValue = @"";
	    }
	  [info setParameter: paramValue forKey: paramName];
	}
      else
	{
	  NSLog(@"Ignoring Mime %@ field parameter (%@)",
	    [info name], paramName);
	}
    }
  return YES;
}

/**
 * <p>
 *   This method is called to parse a header line and split its
 *   contents into an info dictionary.
 * </p>
 * <p>
 *   On entry, the dictionary is already partially filled,
 *   the name argument is a lowercase representation of the
 *   header name, and the scanner is set to a scan location
 *   immediately after the colon in the header string.
 * </p>
 * <p>
 *   If the header is parsed successfully, the method should
 *   return YES, otherwise NO.
 * </p>
 * <p>
 *   You should not call this method directly yourself, but may
 *   override it to support parsing of new headers.
 * </p>
 * <p>
 *   You should be aware of the parsing that the standard
 *   implementation performs, and that <em>needs</em> to be
 *   done for certain headers in order to permit the parser to
 *   work generally -
 * </p>
 * <deflist>
 *   <term>content-disposition</term>
 *   <desc>
 *     <deflist>
 *     <term>Value</term>
 *     <desc>
 *       The content disposition (excluding parameters) as a
 *       lowercase string.
 *     </desc>
 *     </deflist>
 *   </desc>
 *   <term>content-type</term>
 *   <desc>
 *     <deflist>
 *       <term>SubType</term>
 *       <desc>The MIME subtype lowercase</desc>
 *       <term>Type</term>
 *       <desc>The MIME type lowercase</desc>
 *       <term>value</term>
 *       <desc>The full MIME type (xxx/yyy) in lowercase</desc>
 *     </deflist>
 *   </desc>
 *   <term>content-transfer-encoding</term>
 *   <desc>
 *     <deflist>
 *     <term>Value</term>
 *     <desc>The transfer encoding type in lowercase</desc>
 *     </deflist>
 *   </desc>
 *   <term>http</term>
 *   <desc>
 *     <deflist>
 *     <term>HttpVersion</term>
 *     <desc>The HTTP protocol version number</desc>
 *     <term>HttpMajorVersion</term>
 *     <desc>The first component of the version number</desc>
 *     <term>HttpMinorVersion</term>
 *     <desc>The second component of the version number</desc>
 *     <term>HttpStatus</term>
 *     <desc>The response status value (numeric code)</desc>
 *     <term>Value</term>
 *     <desc>The text message (if any)</desc>
 *     </deflist>
 *   </desc>
 *   <term>transfer-encoding</term>
 *   <desc>
 *     <deflist>
 *      <term>Value</term>
 *      <desc>The transfer encoding type in lowercase</desc>
 *     </deflist>
 *   </desc>
 * </deflist>
 */
- (BOOL) scanHeaderBody: (NSScanner*)scanner
		   into: (GSMimeHeader*)info
{
  NSString		*name = [info name];
  NSString		*value = nil;

  /*
   *	Now see if we are interested in any of it.
   */
  if ([name isEqualToString: @"http"] == YES)
    {
      int	loc = [scanner scanLocation];
      int	major;
      int	minor;
      int	status;
      unsigned	count;
      NSArray	*hdrs;

      if ([scanner scanInt: &major] == NO || major < 0)
	{
	  NSLog(@"Bad value for http major version");
	  return NO;
	}
      if ([scanner scanString: @"." intoString: 0] == NO)
	{
	  NSLog(@"Bad format for http version");
	  return NO;
	}
      if ([scanner scanInt: &minor] == NO || minor < 0)
	{
	  NSLog(@"Bad value for http minor version");
	  return NO;
	}
      if ([scanner scanInt: &status] == NO || status < 0)
	{
	  NSLog(@"Bad value for http status");
	  return NO;
	}
      [info setObject: [NSString stringWithFormat: @"%d", minor]
	       forKey: @"HttpMinorVersion"];
      [info setObject: [NSString stringWithFormat: @"%d.%d", major, minor]
	       forKey: @"HttpVersion"];
      [info setObject: [NSString stringWithFormat: @"%d", major]
	       forKey: NSHTTPPropertyServerHTTPVersionKey];
      [info setObject: [NSString stringWithFormat: @"%d", status]
	       forKey: NSHTTPPropertyStatusCodeKey];
      [self scanPastSpace: scanner];
      value = [[scanner string] substringFromIndex: [scanner scanLocation]];
      [info setObject: value
	       forKey: NSHTTPPropertyStatusReasonKey];
      value = [[scanner string] substringFromIndex: loc];
      /*
       * Get rid of preceeding headers in case this is a continuation.
       */
      hdrs = [document allHeaders];
      for (count = 0; count < [hdrs count]; count++)
	{
	  GSMimeHeader	*h = [hdrs objectAtIndex: count];

	  [document deleteHeader: h];
	}
      /*
       * Mark to say we are parsing HTTP content
       */
      [self setIsHttp];
    }
  else if ([name isEqualToString: @"content-transfer-encoding"] == YES
    || [name isEqualToString: @"transfer-encoding"] == YES)
    {
      value = [self scanToken: scanner];
      if ([value length] == 0)
	{
	  NSLog(@"Bad value for content-transfer-encoding header");
	  return NO;
	}
      value = [value lowercaseString];
    }
  else if ([name isEqualToString: @"content-type"] == YES)
    {
      NSString	*type;
      NSString	*subtype = nil;

      type = [self scanToken: scanner];
      if ([type length] == 0)
	{
	  NSLog(@"Invalid Mime content-type");
	  return NO;
	}
      type = [type lowercaseString];
      [info setObject: type forKey: @"Type"];
      if ([scanner scanString: @"/" intoString: 0] == YES)
	{
	  subtype = [self scanToken: scanner];
	  if ([subtype length] == 0)
	    {
	      NSLog(@"Invalid Mime content-type (subtype)");
	      return NO;
	    }
	  subtype = [subtype lowercaseString];
	  [info setObject: subtype forKey: @"SubType"];
	  value = [NSString stringWithFormat: @"%@/%@", type, subtype];
	}
      else
	{
	  value = type;
	}

      [self scanHeaderParameters: scanner into: info];
    }
  else if ([name isEqualToString: @"content-disposition"] == YES)
    {
      value = [self scanToken: scanner];
      value = [value lowercaseString];
      /*
       *	Concatenate slash separated parts of field.
       */
      while ([scanner scanString: @"/" intoString: 0] == YES)
	{
	  NSString	*sub = [self scanToken: scanner];

	  if ([sub length] > 0)
	    {
	      sub = [sub lowercaseString];
	      value = [NSString stringWithFormat: @"%@/%@", value, sub];
	    }
	}

      /*
       *	Expect anything else to be 'name=value' parameters.
       */
      [self scanHeaderParameters: scanner into: info];
    }
  else
    {
      int	loc;

      [self scanPastSpace: scanner];
      loc = [scanner scanLocation];
      value = [[scanner string] substringFromIndex: loc];
    }

  if (value != nil)
    {
      [info setValue: value];
    }
  
  return YES;
}

/**
 * A convenience method to scan past any whitespace in the scanner
 * in preparation for scanning something more interesting that
 * comes after it.  Returns YES if any space was read, NO otherwise.
 */
- (BOOL) scanPastSpace: (NSScanner*)scanner
{
  NSCharacterSet	*skip;
  BOOL			scanned;

  skip = RETAIN([scanner charactersToBeSkipped]);
  [scanner setCharactersToBeSkipped: nil];
  scanned = [scanner scanCharactersFromSet: skip intoString: 0];
  [scanner setCharactersToBeSkipped: skip];
  RELEASE(skip);
  return scanned;
}

/**
 * A convenience method to use a scanner (that is set up to scan a
 * header line) to scan in a special character that terminated a
 * token previously scanned.  If the token was terminated by
 * whitespace and no other special character, the string returned
 * will contain a single space character.
 */
- (NSString*) scanSpecial: (NSScanner*)scanner
{
  unsigned		location;
  unichar		c;

  [self scanPastSpace: scanner];

  /*
   * Now return token delimiter (may be whitespace)
   */
  location = [scanner scanLocation];
  c = [[scanner string] characterAtIndex: location];

  if ([specials characterIsMember: c] == YES)
    {
      [scanner setScanLocation: location + 1];
      return [NSString stringWithCharacters: &c length: 1];
    }
  else
    {
      return @" ";
    }
}

/**
 * A convenience method to use a scanner (that is set up to scan a
 * header line) to scan a header token - either a quoted string or
 * a simple word.
 * <list>
 *   <item>Leading whitespace is ignored.</item>
 *   <item>Backslash escapes in quoted text are converted</item>
 * </list>
 */
- (NSString*) scanToken: (NSScanner*)scanner
{
  if ([scanner scanString: @"\"" intoString: 0] == YES)		// Quoted
    {
      NSString	*string = [scanner string];
      unsigned	length = [string length];
      unsigned	start = [scanner scanLocation];
      NSRange	r = NSMakeRange(start, length - start);
      BOOL	done = NO;

      while (done == NO)
	{
	  r = [string rangeOfString: @"\""
			    options: NSLiteralSearch
			      range: r];
	  if (r.length == 0)
	    {
	      NSLog(@"Parsing header value - found unterminated quoted string");
	      return nil;
	    }
	  if ([string characterAtIndex: r.location - 1] == '\\')
	    {
	      int	p;

	      /*
               * Count number of escape ('\') characters ... if it's odd
	       * then the quote has been escaped and is not a closing
	       * quote.
	       */
	      p = r.location;
	      while (p > 0 && [string characterAtIndex: p - 1] == '\\')
		{
		  p--;
		}
	      p = r.location - p;
	      if (p % 2 == 1)
		{
		  r.location++;
		  r.length = length - r.location;
		}
	      else
		{
		  done = YES;
		}
	    }
	  else
	    {
	      done = YES;
	    }
	}
      [scanner setScanLocation: r.location + 1];
      length = r.location - start;
      if (length == 0)
	{
	  return nil;
	}
      else
	{
	  unichar	buf[length];
	  unichar	*src = buf;
	  unichar	*dst = buf;

	  [string getCharacters: buf range: NSMakeRange(start, length)];
	  while (src < &buf[length])
	    {
	      if (*src == '\\')
		{
		  src++;
		}
	      *dst++ = *src++;
	    }
	  return [NSString stringWithCharacters: buf length: dst - buf];
	}
    }
  else							// Token
    {
      NSCharacterSet		*skip;
      NSString			*value;

      /*
       * Move past white space.
       */
      skip = RETAIN([scanner charactersToBeSkipped]);
      [scanner setCharactersToBeSkipped: nil];
      [scanner scanCharactersFromSet: skip intoString: 0];
      [scanner setCharactersToBeSkipped: skip];
      RELEASE(skip);

      /*
       * Scan value terminated by any special character.
       */
      if ([scanner scanUpToCharactersFromSet: specials
				  intoString: &value] == NO)
	{
	  return nil;
	}
      return value;
    }
}

/**
 * Method to inform the parser that the data it is parsing is an HTTP
 * document rather than true MIME.  This method is called internally
 * if the parser detects an HTTP response line at the start of the
 * headers it is parsing.
 */
- (void) setIsHttp
{
  isHttp = YES;
}
@end

@implementation	GSMimeParser (Private)
/*
 * This method takes the raw data of an unfolded header line, and handles
 * Method to inform the parser that the data it is parsing is an HTTP
 * document rather than true MIME.  This method is called internally
 * if the parser detects an HTTP response line at the start of the
 * headers it is parsing.
 * RFC2047 word encoding in the header by creating a string containing the
 * decoded words.
 */
- (NSString*) _decodeHeader
{
  NSStringEncoding	charset;
  WE			encoding;
  unsigned char		c;
  unsigned char		*src, *dst, *beg;
  NSMutableString	*hdr = [NSMutableString string];
  CREATE_AUTORELEASE_POOL(arp);

  /*
   * Remove any leading or trailing space - there shouldn't be any.
   */
  while (lineStart < lineEnd && isspace(bytes[lineStart]))
    {
      lineStart++;
    }
  while (lineEnd > lineStart && isspace(bytes[lineEnd-1]))
    {
      lineEnd--;
    }

  /*
   * Perform quoted text substitution.
   */
  bytes[lineEnd] = '\0';
  dst = src = beg = &bytes[lineStart];
  while (*src != 0)
    {
      if ((src[0] == '=') && (src[1] == '?'))
	{
	  unsigned char	*tmp;

	  if (dst > beg)
	    {
	      NSData	*d = [NSData dataWithBytes: beg length: dst - beg];
	      NSString	*s;

	      s = [[NSString alloc] initWithData: d
					encoding: NSASCIIStringEncoding];
	      [hdr appendString: s];
	      RELEASE(s);
	      dst = beg;
	    }

	  if (src[3] == '\0')
	    {
	      dst[0] = '=';
	      dst[1] = '?';
	      dst[2] = '\0';
	      NSLog(@"Bad encoded word - character set missing");
	      break;
	    }

	  src += 2;
	  tmp = src;
	  src = (unsigned char*)strchr((char*)src, '?'); 
	  if (src == 0)
	    {
	      NSLog(@"Bad encoded word - character set terminator missing");
	      break;
	    }
	  *src = '\0';
	  charset = parseCharacterSet([NSString stringWithCString: tmp]);
	  src++;
	  if (*src == 0)
	    {
	      NSLog(@"Bad encoded word - content type missing");
	      break;
	    }
	  c = tolower(*src);
	  if (c == 'b')
	    {
	      encoding = WE_BASE64;
	    }
	  else if (c == 'q')
	    {
	      encoding = WE_QUOTED;
	    }
	  else
	    {
	      NSLog(@"Bad encoded word - content type unknown");
	      break;
	    }
	  src = (unsigned char*)strchr((char*)src, '?');
	  if (src == 0)
	    {
	      NSLog(@"Bad encoded word - content type terminator missing");
	      break;
	    }
	  src++;
	  if (*src == 0)
	    {
	      NSLog(@"Bad encoded word - data missing");
	      break;
	    }
	  tmp = (unsigned char*)strchr((char*)src, '?');
	  if (tmp == 0)
	    {
	      NSLog(@"Bad encoded word - data terminator missing");
	      break;
	    }
	  dst = decodeWord(dst, src, tmp, encoding);
	  tmp++;
	  if (*tmp != '=')
	    {
	      NSLog(@"Bad encoded word - encoded word terminator missing");
	      break;
	    }
	  src = tmp;
	  if (dst > beg)
	    {
	      NSData	*d = [NSData dataWithBytes: beg length: dst - beg];
	      NSString	*s;

	      s = [[NSString alloc] initWithData: d
					encoding: charset];
	      [hdr appendString: s];
	      RELEASE(s);
	      dst = beg;
	    }
	}
      else
	{
	  *dst++ = *src;
	}
      src++;
    }
  if (dst > beg)
    {
      NSData	*d = [NSData dataWithBytes: beg length: dst - beg];
      NSString	*s;

      s = [[NSString alloc] initWithData: d
				encoding: NSASCIIStringEncoding];
      [hdr appendString: s];
      RELEASE(s);
      dst = beg;
    }
  RELEASE(arp);
  return hdr;
}

- (BOOL) _decodeBody: (NSData*)d
{
  unsigned	l = [d length];
  BOOL		result = NO;

  rawBodyLength += l;

  if (context == nil)
    {
      GSMimeHeader	*hdr;

      expect = 0;
      /*
       * Check for expected content length.
       */
      hdr = [document headerNamed: @"content-length"];
      if (hdr != nil)
	{
	  expect = [[hdr value] intValue];
	}

      /*
       * Set up context for decoding data.
       */
      hdr = [document headerNamed: @"transfer-encoding"];
      if (hdr == nil)
	{
	  hdr = [document headerNamed: @"content-transfer-encoding"];
	}
      else if ([[[hdr value] lowercaseString] isEqual: @"chunked"] == YES)
	{
	  /*
	   * Chunked transfer encoding overrides any content length spec.
	   */
	  expect = 0;
	}
      context = [self contextFor: hdr];
      RETAIN(context);
      NSDebugMLLog(@"GSMime", @"Parse body expects %u bytes", expect);
    }

  NSDebugMLLog(@"GSMime", @"Parse %u bytes - '%*.*s'", l, l, l, [d bytes]);

  if ([context atEnd] == YES)
    {
      inBody = NO;
      complete = YES;
      if ([d length] > 0)
	{
	  NSLog(@"Additional data (%*.*s) ignored after parse complete",
	    [d length], [d length], [d bytes]);
	}
      result = YES;	/* Nothing more to do	*/
    }
  else if (boundary == nil)
    {
      GSMimeHeader	*typeInfo;
      NSString		*type;

      typeInfo = [document headerNamed: @"content-type"];
      type = [typeInfo objectForKey: @"Type"];
      if ([type isEqualToString: @"multipart"] == YES)
	{
	  NSLog(@"multipart decode attempt without boundary");
	  inBody = NO;
	  complete = YES;
	  result = NO;
	}
      else
	{
	  [self decodeData: d
		 fromRange: NSMakeRange(0, [d length])
		  intoData: data
	       withContext: context];

	  if ([context atEnd] == YES
	    || (expect > 0 && rawBodyLength >= expect))
	    {
	      inBody = NO;
	      complete = YES;

	      NSDebugMLLog(@"GSMime", @"Parse body complete");
	      /*
	       * If no content type is supplied, we assume text ... unless
	       * we have something that's known to be a file.
	       */
	      if (type == nil)
		{
		  if ([document contentFile] != nil)
		    {
		      type = @"application";
		    }
		  else
		    {
		      type = @"text";
		    }
		}

	      if ([type isEqualToString: @"text"] == YES)
		{
		  NSDictionary		*params;
		  NSString		*charset;
		  NSStringEncoding	stringEncoding;
		  NSString		*string;

		  /*
		   * Assume that content type is best represented as NSString.
		   */
		  params = [typeInfo objectForKey: @"Parameters"];
		  charset = [params objectForKey: @"charset"];
		  stringEncoding = parseCharacterSet(charset);
		  string = [[NSString alloc] initWithData: data
						 encoding: stringEncoding];
		  [document setContent: string];
		  RELEASE(string);
		}
	      else
		{
		  /*
		   * Assume that any non-text content type is best
		   * represented as NSData.
		   */
		  [document setContent: data];
		}
	    }
	  result = YES;
	}
    }
  else
    {
      unsigned	int	bLength = [boundary length];
      unsigned char	*bBytes = (unsigned char*)[boundary bytes];
      unsigned char	bInit = bBytes[0];
      BOOL		done = NO;

      [data appendBytes: [d bytes] length: [d length]];
      bytes = (unsigned char*)[data mutableBytes];
      dataEnd = [data length];

      while (done == NO)
	{
	  /*
	   * Search our data for the next boundary.
	   */
	  while (dataEnd - lineStart >= bLength)
	    {
	      if (bytes[lineStart] == bInit
		&& memcmp(&bytes[lineStart], bBytes, bLength) == 0)
		{
		  if (lineStart == 0 || bytes[lineStart-1] == '\r'
		    || bytes[lineStart-1] == '\n')
		    {
		      lineEnd = lineStart + bLength;
		      break;
		    }
		}
	      lineStart++;
	    }
	  if (dataEnd - lineStart < bLength)
	    {
	      done = YES;	/* Needs more data.	*/
	    } 
	  else if (child == nil)
	    {
	      /*
	       * Found boundary at the start of the first section.
	       * Set sectionStart to point immediately after boundary.
	       */
	      lineStart += bLength;
	      sectionStart = lineStart;
	      child = [GSMimeParser new];
	    }
	  else
	    {
	      NSData	*d;
	      unsigned	pos;
	      BOOL	endedFinalPart = NO;

	      /*
	       * Found boundary at the end of a section.
	       * Skip past line terminator for boundary at start of section
	       * or past marker for end of multipart document.
	       */
	      if (bytes[sectionStart] == '-' && sectionStart < dataEnd
		&& bytes[sectionStart+1] == '-')
		{
		  sectionStart += 2;
		  endedFinalPart = YES;
		}
	      if (bytes[sectionStart] == '\r')
		{
		  sectionStart++;
		}
	      if (bytes[sectionStart] == '\n')
		{
		  sectionStart++;
		}

	      /*
	       * Create data object for this section and pass it to the
	       * child parser to deal with.  NB. As lineStart points to
	       * the start of the end boundary, we need to step back to
	       * before the end of line introducing it in order to have
	       * the correct length of body data for the child document.
	       */
	      pos = lineStart;
	      if (pos > 0 && bytes[pos-1] == '\n')
		{
		  pos--;
		}
	      if (pos > 0 && bytes[pos-1] == '\r')
		{
		  pos--;
		}
	      d = [NSData dataWithBytes: &bytes[sectionStart]
				 length: pos - sectionStart];
	      if ([child parse: d] == YES)
		{
		  /*
		   * The parser wants more data, so pass a nil data item
		   * to tell it that it has had all there is.
		   */
		  [child parse: nil];
		}
	      if ([child isComplete] == YES)
		{
		  GSMimeDocument	*doc;

		  /*
		   * Store the document produced by the child, and
		   * create a new parser for the next section.
	           */
		  doc = [child mimeDocument];
		  if (doc != nil)
		    {
		      [document addContent: doc];
		    }
		  RELEASE(child);
		  child = [GSMimeParser new];
		}
	      else
		{
		  /*
		   * Section failed to decode properly!
		   */
		  NSLog(@"Failed to decode section of multipart");
		  RELEASE(child);
		  child = [GSMimeParser new];
		}

	      /*
	       * Update parser data.
	       */
	      lineStart += bLength;
	      sectionStart = lineStart;
	      memcpy(bytes, &bytes[sectionStart], dataEnd - sectionStart);
	      dataEnd -= sectionStart;
	      [data setLength: dataEnd];
	      bytes = (unsigned char*)[data mutableBytes];
	      lineStart -= sectionStart;
	      sectionStart = 0;
	    }
	}
      /*
       * Check to see if we have reached content length.
       */
      if (expect > 0 && rawBodyLength >= expect)
	{
	  complete = YES;
	  inBody = NO;
	}
      result = YES;
    }
  return result;
}

- (BOOL) _unfoldHeader
{
  char		c;
  BOOL		unwrappingComplete = NO;

  lineStart = lineEnd;
  NSDebugMLLog(@"GSMime", @"entry: input:%u dataEnd:%u lineStart:%u '%*.*s'",
    input, dataEnd, lineStart, dataEnd - input, dataEnd - input, &bytes[input]);
  /*
   * RFC822 lets header fields break across lines, with continuation
   * lines beginning with whitespace.  This is called folding - and the
   * first thing we need to do is unfold any folded lines into a single
   * unfolded line (lineStart to lineEnd).
   */
  while (input < dataEnd && unwrappingComplete == NO)
    {
      unsigned	pos = input;

      if ((c = bytes[pos]) != '\r' && c != '\n')
	{
	  while (pos < dataEnd && (c = bytes[pos]) != '\r' && c != '\n')
	    {
	      pos++;
	    }
	  if (pos == dataEnd)
	    {
	      break;	/* need more data */
	    }
	  pos++;
	  if (c == '\r' && pos < dataEnd && bytes[pos] == '\n')
	    {
	      pos++;
	    }
	  if (pos == dataEnd)
	    {
	      break;	/* need more data */
	    }
	  /*
	   * Copy data up to end of line, and skip past end.
	   */
	  while (input < dataEnd && (c = bytes[input]) != '\r' && c != '\n')
	    {
	      bytes[lineEnd++] = bytes[input++];
	    }
	}

      /*
       * Eat a newline that is part of a cr-lf sequence.
       */
      input++;
      if (c == '\r' && input < dataEnd && bytes[input] == '\n')
	{
	  input++;
	}

      /*
       * See if we have a wrapped line.
       */
      if ((c = bytes[input]) == '\r' || c == '\n' || isspace(c) == 0)
	{
	  unwrappingComplete = YES;
	  bytes[lineEnd] = '\0';
	  /*
	   * If this is a zero-length line, we have reached the end of
	   * the headers.
	   */
	  if (lineEnd == lineStart)
	    {
	      unsigned		lengthRemaining;

	      /*
	       * Overwrite the header data with the body, ready to start
	       * parsing the body data.
	       */
	      lengthRemaining = dataEnd - input;
	      if (lengthRemaining > 0)
		{
		  memcpy(bytes, &bytes[input], lengthRemaining);
		}
	      dataEnd = lengthRemaining;
	      [data setLength: lengthRemaining];
	      bytes = (unsigned char*)[data mutableBytes];
	      sectionStart = 0;
	      lineStart = 0;
	      lineEnd = 0;
	      input = 0;
	      inBody = YES;
	    }
	}
    }
  NSDebugMLLog(@"GSMime", @"exit: inBody:%d unwrappingComplete: %d "
    @"input:%u dataEnd:%u lineStart:%u '%*.*s'", inBody, unwrappingComplete,
    input, dataEnd, lineStart, dataEnd - input, dataEnd - input, &bytes[input]);
  return unwrappingComplete;
}
@end



@implementation	GSMimeHeader

static NSCharacterSet	*nonToken = nil;
static NSCharacterSet	*tokenSet = nil;

+ (void) initialize
{
  if (nonToken == nil)
    {
      NSMutableCharacterSet	*ms;

      ms = [NSMutableCharacterSet new];
      [ms addCharactersInRange: NSMakeRange(33, 126-32)];
      [ms removeCharactersInString: @"()<>@,;:\\\"/[]?="];
      tokenSet = [ms copy];
      RELEASE(ms);
      nonToken = RETAIN([tokenSet invertedSet]);
    }
}

/**
 * Makes the value into a quoted string if necessary.
 */
+ (NSString*) makeQuoted: (NSString*)v
{
  NSRange	r;
  unsigned	pos = 0;
  unsigned	l = [v length];

  r = [v rangeOfCharacterFromSet: nonToken
			 options: NSLiteralSearch
			   range: NSMakeRange(pos, l - pos)];
  if (r.length > 0)
    {
      NSMutableString	*m = [NSMutableString new];

      [m appendString: @"\""];
      while (r.length > 0)
	{
	  unichar	c;

	  if (r.location > pos)
	    {
	      [m appendString:
		[v substringFromRange: NSMakeRange(pos, r.location - pos)]];
	    }
	  pos = r.location + 1;
	  c = [v characterAtIndex: r.location];
	  if (c < 128)
	    {
	      [m appendFormat: @"\\%c", c];
	    }
	  else
	    {
	      NSLog(@"NON ASCII characters not yet implemented");
	    }
	  r = [v rangeOfCharacterFromSet: nonToken
				 options: NSLiteralSearch
				   range: NSMakeRange(pos, l - pos)];
	}
      [m appendString: @"\""];
      v = AUTORELEASE(m);
    }
  return v;
}

/**
 * Convert the supplied string to a standardized token by making it
 * lowercase and removing all illegal characters.
 */
+ (NSString*) makeToken: (NSString*)t
{
  NSRange	r;

  t = [t lowercaseString];
  r = [t rangeOfCharacterFromSet: nonToken];
  if (r.length > 0)
    {
      NSMutableString	*m = [t mutableCopy];

      while (r.length > 0)
	{
	  [m deleteCharactersInRange: r];
	  r = [m rangeOfCharacterFromSet: nonToken];
	}
      t = AUTORELEASE(m);
    }
  return t;
}

- (id) copyWithZone: (NSZone*)z
{
  GSMimeHeader	*c = [GSMimeHeader allocWithZone: z];
  NSEnumerator	*e;
  NSString	*k;

  c = [c initWithName: [self name]
		value: [self value]
	   parameters: [self parameters]];
  e = [objects keyEnumerator];
  while ((k = [e nextObject]) != nil)
    {
      [c setObject: [self objectForKey: k] forKey: k];
    }
  return c;
}

- (void) dealloc
{
  RELEASE(name);
  RELEASE(value);
  RELEASE(objects);
  RELEASE(params);
  [super dealloc];
}

- (NSString*) description
{
  NSMutableString	*desc;

  desc = [NSMutableString stringWithFormat: @"GSMimeHeader <%0x> -\n", self];
  [desc appendFormat: @"  name: %@\n", [self name]];
  [desc appendFormat: @"  value: %@\n", [self value]];
  [desc appendFormat: @"  params: %@\n", [self parameters]];
  return desc;
}

- (id) init
{
  return [self initWithName: @"unknown" value: @"none" parameters: nil];
}

/**
 * <init />
 * Initialise a GSMimeHeader supplying a name, a value and a dictionary
 * of any parameters occurring after the value.
 */
- (id) initWithName: (NSString*)n
	      value: (NSString*)v
	 parameters: (NSDictionary*)p
{
  objects = [NSMutableDictionary new];
  params = [NSMutableDictionary new];
  [self setName: n];
  [self setValue: v];
  [self setParameters: p];
  return self;
}

/**
 * Returns the name of this header ... a lowercase string.
 */
- (NSString*) name
{
  return name;
}

/**
 * Return extra information specific to a particular header type.
 */
- (id) objectForKey: (NSString*)k
{
  return [objects objectForKey: k];
}

- (NSDictionary*) objects
{
  return AUTORELEASE([objects copy]);
}

/**
 * Return the named parameter value.
 */
- (NSString*) parameterForKey: (NSString*)k
{
  NSString	*p = [params objectForKey: k];

  if (p == nil)
    {
      k = [GSMimeHeader makeToken: k];
      p = [params objectForKey: k];
    }
  return p;	
}

/**
 * Returns the parameters of this header ... a dictionary whose keys
 * are all lowercase strings, and whosre value is a string which may
 * contain mixed case.
 */
- (NSDictionary*) parameters
{
  return AUTORELEASE([params copy]);
}

/**
 * Sets the name of this header ... converts to lowercase and removes
 * illegal characters.  If given a nil or empty string argument,
 * sets the name to 'unknown'.
 */
- (void) setName: (NSString*)s
{
  s = [GSMimeHeader makeToken: s];
  if ([s length] == 0)
    {
      s = @"unknown";
    }
  ASSIGN(name, s);
}

/**
 * Method to store specific information for particular types of
 * header.
 */
- (void) setObject: (id)o forKey: (NSString*)k
{
  [objects setObject: o forKey: k];
}

/**
 * Sets a parameter of this header ... converts name to lowercase and
 * removes illegal characters.<br />
 * If a nil parameter name is supplied, removes any parameter with the
 * specified key.
 */
- (void) setParameter: (NSString*)v forKey: (NSString*)k
{
  k = [GSMimeHeader makeToken: k];
  if (v == nil)
    {
      [params removeObjectForKey: k];
    }
  else
    {
      [params setObject: v forKey: k];
    }
}

/**
 * Sets all parameters of this header ... converts names to lowercase
 * and removes illegal characters from them.
 */
- (void) setParameters: (NSDictionary*)d
{
  NSMutableDictionary	*m = [NSMutableDictionary new];
  NSEnumerator		*e = [d keyEnumerator];
  NSString		*k;

  while ((k = [e nextObject]) != nil)
    {
      [m setObject: [d objectForKey: k] forKey: [GSMimeHeader makeToken: k]];
    }
  DESTROY(params);
  params = m;
}

/**
 * Sets the value of this header (without changing parameters)<br />
 * If given a nil argument, set an empty string value.
 */
- (void) setValue: (NSString*)s
{
  if (s == nil)
    {
      s = @"";
    }
  ASSIGN(value, s);
}

/**
 * Returns the full text of the header, built from its component parts,
 * and including a terminating CR-LF
 */
- (NSString*) text
{
  NSMutableString	*t = [NSMutableString new];
  NSEnumerator		*e = [params keyEnumerator];
  NSString		*k;
  unsigned		l;

  [t appendString: [[self name] capitalizedString]];
  [t appendString: @": "];
  [t appendString: value];
  l = [t length];
  while ((k = [e nextObject]) != nil)
    {
      NSString	*v = [GSMimeHeader makeQuoted: [params objectForKey: k]];
      unsigned	kl = [k length];
      unsigned	vl = [v length];

      if ((l + kl + vl + 3) > 72)
	{
	  [t appendString: @"\r\n\t"];
	  l = 8;
	}
      [t appendFormat: @"; %@=%@", k, v];
      l += kl + vl + 3;
    }
  [t appendString: @"\r\n"];

  return AUTORELEASE(t);
}

/**
 * Returns the value of this header (excluding any parameters)
 */
- (NSString*) value
{
  return value;
}
@end



/**
 * <p>
 *   This class is intended to provide a wrapper for MIME messages
 *   permitting easy access to the contents of a message and
 *   providing a basis for parsing an unparsing messages that
 *   have arrived via email or as a web document.
 * </p>
 * <p>
 *   The class keeps track of all the document headers, and provides
 *   methods for modifying and examining the headers that apply to a
 *   document.
 * </p>
 */
@implementation	GSMimeDocument

+ (void) initialize
{
  if (self == [GSMimeDocument class])
    {
      NSMutableCharacterSet	*m = [[NSMutableCharacterSet alloc] init];

      [m formUnionWithCharacterSet:
	[NSCharacterSet characterSetWithCharactersInString:
	@"()<>@,;:/[]?=\"\\"]];
      [m formUnionWithCharacterSet:
	[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      [m formUnionWithCharacterSet:
	[NSCharacterSet controlCharacterSet]];
      [m formUnionWithCharacterSet:
	[NSCharacterSet illegalCharacterSet]];
      specials = [m copy];
    }
}

/**
 * Adds a part to a multipart document
 */
- (BOOL) addContent: (GSMimeDocument*)newContent
{
  BOOL	result = YES;

  if (content == nil)
    {
      content = [NSMutableArray new];
    }
  if ([content isKindOfClass: [NSMutableArray class]] == YES)
    {
      [content addObject: newContent];
    }
  else
    {
      result = NO;
    }
  return result;
}

/**
 * <p>
 *   This method may be called to add a header to the document.
 *   The header must be a mutable dictionary object that contains
 *   at least the fields that are standard for all headers.
 * </p>
 */
- (BOOL) addHeader: (GSMimeHeader*)info
{
  NSString	*name = [info name];

  if (name == nil || [name isEqual: @"unknown"] == YES)
    {
      NSLog(@"setHeader: supplied with header without valid name");
      return NO;
    }
  [headers addObject: info];
  return YES;
}

/**
 * <p>
 *   This method returns an array containing GSMimeHeader objects
 *   representing the headers associated with the document.
 * </p>
 * <p>
 *   The order of the headers in the array is the order of the
 *   headers in the document.
 * </p>
 */
- (NSArray*) allHeaders
{
  return [NSArray arrayWithArray: headers];
}

/**
 * This returns the content data of the document in the
 * appropriate format for the type of data -
 * <deflist>
 *   <term>text</term>
 *   <desc>an NSString object</desc>
 *   <term>binary</term>
 *   <desc>an NSData object</desc>
 *   <term>multipart</term>
 *   <desc>an NSArray object containing GSMimeDocument objects</desc>
 * </deflist>
 */
- (id) content
{
  return content;
}

/**
 * Search the content of this document to locate a part whose content ID
 * matches the specified key.  Recursively descend into other documents.<br />
 * Return nil if no match is found, the matching GSMimeDocument otherwise.
 */ 
- (id) contentByID: (NSString*)key
{
  if ([content isKindOfClass: [NSArray class]] == YES)
    {
      NSEnumerator	*e = [content objectEnumerator];
      GSMimeDocument	*d;

      while ((d = [e nextObject]) != nil)
	{
	  if ([[d contentID] isEqualToString: key] == YES)
	    {
	      return d;
	    }
	  d = [d contentByID: key];
	  if (d != nil)
	    {
	      return d;
	    }
	}
    }
  return nil;
}

/**
 * Search the content of this document to locate a part whose content-type
 * name or content-disposition name matches the specified key.
 * Recursively descend into other documents.<br />
 * Return nil if no match is found, the matching GSMimeDocument otherwise.
 */ 
- (id) contentByName: (NSString*)key
{

  if ([content isKindOfClass: [NSArray class]] == YES)
    {
      NSEnumerator	*e = [content objectEnumerator];
      GSMimeDocument	*d;

      while ((d = [e nextObject]) != nil)
	{
	  GSMimeHeader	*hdr;

	  hdr = [d headerNamed: @"content-type"];
	  if ([[hdr parameterForKey: @"name"] isEqualToString: key] == YES)
	    {
	      return d;
	    }
	  hdr = [d headerNamed: @"content-disposition"];
	  if ([[hdr parameterForKey: @"name"] isEqualToString: key] == YES)
	    {
	      return d;
	    }
	  d = [d contentByName: key];
	  if (d != nil)
	    {
	      return d;
	    }
	}
    }
  return nil;
}

/**
 * Convenience method to fetch the content file name from the header.
 */
- (NSString*) contentFile
{
  GSMimeHeader	*hdr = [self headerNamed: @"content-disposition"];

  return [hdr parameterForKey: @"filename"];
}

/**
 * Convenience method to fetch the content ID from the header.
 */
- (NSString*) contentID
{
  GSMimeHeader	*hdr = [self headerNamed: @"content-id"];

  return [hdr value];
}

/**
 * Convenience method to fetch the content name from the header.
 */
- (NSString*) contentName
{
  GSMimeHeader	*hdr = [self headerNamed: @"content-type"];

  return [hdr parameterForKey: @"name"];
}

/**
 * Convenience method to fetch the content sub-type from the header.
 */
- (NSString*) contentSubType
{
  GSMimeHeader	*hdr = [self headerNamed: @"content-type"];

  return [hdr objectForKey: @"SubType"];
}

/**
 * Convenience method to fetch the content type from the header.
 */
- (NSString*) contentType
{
  GSMimeHeader	*hdr = [self headerNamed: @"content-type"];

  return [hdr objectForKey: @"Type"];
}

/**
 * Return the content as an NSData object (unless it is multipart)
 */
- (NSData*) convertToData
{
  NSData	*d = nil;

  if ([content isKindOfClass: [NSString class]] == YES)
    {
      NSStringEncoding	enc = NSUTF8StringEncoding;

      d = [content dataUsingEncoding: enc];
    }
  else if ([content isKindOfClass: [NSData class]] == YES)
    {
      d = content;
    }
  return d;
}

/**
 * Return the content as an NSString object (unless it is multipart)
 */
- (NSString*) convertToText
{
  NSString	*s = nil;

  if ([content isKindOfClass: [NSString class]] == YES)
    {
      s = content;
    }
  else if ([content isKindOfClass: [NSData class]] == YES)
    {
      NSStringEncoding	enc = NSUTF8StringEncoding;

      s = [[NSString alloc] initWithData: content encoding: enc];
      AUTORELEASE(s);
    }
  return s;
}

- (id) copyWithZone: (NSZone*)z
{
  return RETAIN(self);
}

- (void) dealloc
{
  RELEASE(headers);
  RELEASE(content);
  [super dealloc];
}

/**
 * This method removes all occurrances of header objects identical to
 * the one supplied as an argument.
 */
- (void) deleteHeader: (GSMimeHeader*)aHeader
{
  unsigned	count = [headers count];

  while (count-- > 0)
    {
      if ([aHeader isEqual: [headers objectAtIndex: count]] == YES)
	{
	  [headers removeObjectAtIndex: count];
	}
    }
}

/**
 * This method removes all occurrances of headers whose name
 * matches the supplied string.
 */
- (void) deleteHeaderNamed: (NSString*)name
{
  unsigned	count = [headers count];

  name = [name lowercaseString];
  while (count-- > 0)
    {
      GSMimeHeader	*info = [headers objectAtIndex: count];

      if ([name isEqualToString: [info name]] == YES)
	{
	  [headers removeObjectAtIndex: count];
	}
    }
}

- (NSString*) description
{
  NSMutableString	*desc;
  NSDictionary		*locale;

  desc = [NSMutableString stringWithFormat: @"GSMimeDocument <%0x> -\n", self];
  locale = [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
  [desc appendString: [headers descriptionWithLocale: locale]];
  [desc appendFormat: @"\nDocument content -\n%@", content];
  return desc;
}

/**
 * This method returns the first header whose name equals the supplied argument.
 */
- (GSMimeHeader*) headerNamed: (NSString*)name
{
  NSArray	*a = [self headersNamed: name];

  if ([a count] > 0)
    {
      return [a objectAtIndex: 0];
    }
  return nil;
}

/**
 * This method returns an array of GSMimeHeader objects for all headers
 * whose names equal the supplied argument.
 */
- (NSArray*) headersNamed: (NSString*)name
{
  unsigned		count = [headers count];
  unsigned		index;
  NSMutableArray	*array;

  name = [GSMimeHeader makeToken: name];
  array = [NSMutableArray array];
  for (index = 0; index < count; index++)
    {
      GSMimeHeader	*info = [headers objectAtIndex: index];

      if ([name isEqualToString: [info name]] == YES)
	{
	  [array addObject: info];
	}
    } 
  return array;
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      headers = [NSMutableArray new];
    }
  return self;
}

/**
 * Create new content ID header, set it as the content ID of the document
 * and return it.
 */
- (GSMimeHeader*) makeContentID
{
  NSString	*val;
  GSMimeHeader	*hdr;

  val = [NSString stringWithFormat: @"GSMime%08x%08x", self, _count++];
  hdr = [[GSMimeHeader alloc] initWithName: @"content-id"
				     value: val
				parameters: nil];
  [self setHeader: hdr];
  RELEASE(hdr);
  return hdr;
}

/**
 * Sets a new value for the content of the document.
 */
- (BOOL) setContent: (id)newContent
{
  BOOL	result = YES;

  if ([newContent isKindOfClass: [NSString class]] == YES)
    {
      ASSIGNCOPY(content, newContent);
    }
  else if ([newContent isKindOfClass: [NSData class]] == YES)
    {
      ASSIGNCOPY(content, newContent);
    }
  else if ([newContent isKindOfClass: [NSArray class]] == YES)
    {
      newContent = [newContent mutableCopy];
      ASSIGN(content, newContent);
      RELEASE(newContent);
    }
  else
    {
      result = NO;
    }
  return result;
}

/**
 * Convenience method to set the content of the document aslong with
 * creating a content-type header for it.
 */
- (BOOL) setContent: (id)newContent
	       type: (NSString*)type
	    subType: (NSString*)subType
	       name: (NSString*)name
{
  if ([type isEqualToString: @"multi-part"] == NO
    && [content isKindOfClass: [NSArray class]] == YES)
    {
      NSLog(@"Can't set non-'multi-part' content type for array of content");
      return NO;
    }

  if ([self setContent: newContent] == NO)
    {
      return NO;
    }
  else
    {
      GSMimeHeader	*hdr;
      NSString		*val;

      val = [NSString stringWithFormat: @"%@/%@", type, subType];
      hdr = [GSMimeHeader alloc];
      hdr = [hdr initWithName: @"content-type" value: val parameters: nil];
      if (name != nil)
	{
	  [hdr setParameter: name forKey: @"name"];
	}
      [self setHeader: hdr];
      RELEASE(hdr);
    }
  return YES;
}

/**
 * This method may be called to set a header in the document.
 * Any other headers with the same name will be removed from
 * the document.
 */
- (BOOL) setHeader: (GSMimeHeader*)info
{
  NSString	*name = [info name];

  if (name != nil)
    {
      unsigned	count = [headers count];

      /*
       * Remove any existing headers with this name.
       */
      while (count-- > 0)
	{
	  GSMimeHeader	*tmp = [headers objectAtIndex: count];

	  if ([name isEqualToString: [tmp name]] == YES)
	    {
	      [headers removeObjectAtIndex: count];
	    }
	}
    }
  return [self addHeader: info];
}

@end

