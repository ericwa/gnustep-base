#ifndef	_INCLUDED_AGSPARSER_H
#define	_INCLUDED_AGSPARSER_H
/**

   <title>AGSParser ...a class to get documention info from ObjC source</title>
   Copyright (C) 2001 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Created: October 2001

   This file is part of the GNUstep Project

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   You should have received a copy of the GNU General Public
   License along with this program; see the file COPYING.LIB.
   If not, write to the Free Software Foundation,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

   <abstract>
    This is the AGSParser class ... and some autogsdoc examples.
    The AGSParser class is designed to produce a property-list
    which can be handled by AGSOutput ... one class is not much
    use without the other.
   </abstract>

   */

#include <Foundation/Foundation.h>

@interface	AGSParser : NSObject
{
  /*
   * The following items are used for logging/debug purposes.
   */
  NSString	*fileName;	/** Not retained - file being parsed. */
  NSString	*unitName;	/** Not retained - unit being parsed. */
  NSString	*itemName;	/** Not retained - item being parsed. */
  NSArray	*lines;		/** Not retained - line number mapping. */

  /*
   * The next few ivars represent the data currently being parsed.
   */
  unichar	*buffer;
  unsigned	length;
  unsigned	pos;
  BOOL		inHeader;
  BOOL		commentsRead;
  BOOL		haveOutput;
  BOOL		haveSource;
  BOOL		inInstanceVariables;
  BOOL		inArgList;
  BOOL		documentInstanceVariables;
  BOOL		documentAllInstanceVariables;
  BOOL		verbose;
  BOOL		warn;
  BOOL		standards;
  NSDictionary		*wordMap;
  NSString		*declared;	/** Where classes were declared. */
  NSMutableArray	*ifStack;	/** Track preprocessor conditionals. */

  NSString		*comment;	/** Documentation accumulator. */
  NSMutableDictionary	*info;		/** All information parsed. */
  NSMutableArray	*source;	/** Names of source files. */
  NSCharacterSet	*identifier;	/** Legit char in identifier */
  NSCharacterSet	*identStart;	/** Legit initial char of identifier */
  NSCharacterSet	*spaces;	/** All blank characters */
  NSCharacterSet	*spacenl;	/** Blanks excluding newline */
}

- (NSMutableDictionary*) info;
- (id) init;	/** <init> Simple initialiser */
- (NSMutableArray*) outputs;
- (unsigned) parseComment;
- (NSMutableDictionary*) parseDeclaration;
- (NSMutableDictionary*) parseFile: (NSString*)name isSource: (BOOL)isSource;
- (NSString*) parseIdentifier;
- (NSMutableDictionary*) parseImplementation;
- (NSMutableDictionary*) parseInterface;
- (NSMutableDictionary*) parseInstanceVariables;
- (NSMutableDictionary*) parseMacro;
- (NSMutableDictionary*) parseMethodIsDeclaration: (BOOL)flag;
- (NSMutableDictionary*) parseMethodsAreDeclarations: (BOOL)flag;
- (NSString*) parseMethodType;
- (unsigned) parsePreprocessor;
- (NSMutableDictionary*) parseProtocol;
- (NSMutableArray*) parseProtocolList;
- (unsigned) parseSpace: (NSCharacterSet*)spaceSet;
- (unsigned) parseSpace;
- (NSString*) parseVersion;
- (void) reset;
- (void) setDeclared: (NSString*)name;
- (void) setDocumentInstanceVariables: (BOOL)flag;
- (void) setDocumentAllInstanceVariables: (BOOL)flag;
- (void) setGenerateStandards: (BOOL)flag;
- (void) setStandards: (NSMutableDictionary*)dict;
- (void) setWordMap: (NSDictionary*)map;
- (void) setupBuffer;
- (unsigned) skipArray;
- (unsigned) skipBlock;
- (unsigned) skipLiteral;
- (unsigned) skipRemainderOfLine;
- (unsigned) skipSpaces;
- (unsigned) skipStatement;
- (unsigned) skipStatementLine;
- (unsigned) skipToEndOfLine;
- (unsigned) skipUnit;
- (NSMutableArray*) sources;
@end

#endif
