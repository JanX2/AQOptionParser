//
//  AQOption.m
//  AQOptionParser
//
//  Created by Jim Dovey on 2012-05-23.
//  Copyright (c) 2012 Jim Dovey. All rights reserved.
//

#import "AQOption.h"
#import "AQOption_Internal.h"
#import "AQOptionRequirementGroup_Internal.h"

NSString * const AQOptionUsageLocalizedValueName = @"AQOptionUsageLocalizedValueName";
NSString * const AQOptionUsageLocalizedDescription = @"AQOptionUsageLocalizedDescription";

@implementation AQOption
{
    NSString *                  _longName;
    NSString *                  _shortName;
    AQOptionParameterType       _parameterType;
    NSDictionary *              _usageInformation;
    NSString *                  _parameter;
    NSString *                  _localizedOptionExample;
    AQOptionRequirementGroup *  _requirementGroup __weak;
    
    void (^_matchHandler)(NSString *, NSString *);
    
    BOOL                        _matched;
    BOOL                        _optional;
}

@synthesize matched=_matched, optional=_optional, parameter=_parameter, localizedUsageInformation=_usageInformation, longName=_longName;

- (id) initWithLongName: (NSString *) longName shortName: (unichar) shortName requiresParameter: (AQOptionParameterType) parameterType optional: (BOOL) optional handler: (void (^)(NSString *, NSString *)) handler
{
    self = [super init];
    if ( self == nil )
        return ( nil );
    
    _longName = [longName copy];
    _shortName = [[NSString alloc] initWithCharacters: &shortName length: 1];
    _parameterType = parameterType;
    _optional = optional;
    _matchHandler = [handler copy];
    
    [self _generateOptionExample];
    
    return ( self );
}

- (id) initWithLongName: (NSString *) longName shortName: (unichar) shortName requiresParameter: (AQOptionParameterType) parameterType optional: (BOOL) optional
{
    return ( [self initWithLongName:longName shortName:shortName requiresParameter:parameterType optional:optional handler:nil] );
}

- (unichar) shortName
{
    return ( [_shortName characterAtIndex: 0] );
}

- (void) _generateOptionExample
{
    NSString * val = [_usageInformation objectForKey: AQOptionUsageLocalizedValueName];
    if ( val == nil )
        val = NSLocalizedString(@"value", @"default value name");
    
    switch ( _parameterType )
    {
        case AQOptionParameterTypeNone:
            _localizedOptionExample = [[NSString alloc] initWithFormat: @"--%@ | -%@:", _longName, _shortName];
            break;
            
        case AQOptionParameterTypeOptional:
        default:
            _localizedOptionExample = [[NSString alloc] initWithFormat: @"--%@[=%@] | -%@ [%@]:", _longName, val, _shortName, val];
            break;
            
        case AQOptionParameterTypeRequired:
            _localizedOptionExample = [[NSString alloc] initWithFormat: @"--%@=%@ | %@ %@:", _longName, val, _shortName, val];
            break;
    }
}

- (void) setLocalizedUsageInformation: (NSDictionary *) localizedUsageInformation
{
    [self willChangeValueForKey: @"localizedUsageInformation"];
    _usageInformation = [localizedUsageInformation copy];
    [self _generateOptionExample];
    [self didChangeValueForKey: @"localizedUsageInformation"];
}

- (void) _hyphenatingWrapString: (NSMutableString *) str withIndent: (NSUInteger) indent atColumn: (NSUInteger) column forLocale: (NSLocale *) locale
{
    NSMutableString * indentStr = [NSMutableString new];
    for ( NSUInteger i = 0; i < indent; i++ )
        [indentStr appendString: @" "];
    
    // indent first line
    [str insertString: indentStr atIndex: 0];
    if ( column == 0 )      // no wrapping required
        return;
    
    // replace all tabs with the indent string
    [str replaceOccurrencesOfString: @"\t" withString: indentStr options: 0 range: NSMakeRange(0, [str length])];
    
    // break point for current line-- will be updated as we wrap
    __block NSUInteger breakPoint = column;
    NSString * base = [str copy];
    [str setString: @""];
    
    NSCharacterSet * whitespace = [NSCharacterSet whitespaceCharacterSet];
    
    [base enumerateSubstringsInRange: NSMakeRange(0, [base length]) options: NSStringEnumerationByWords usingBlock: ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        // see if the description string contains a specific newline character already
        NSUInteger newlineIdx = [base rangeOfString: @"\n" options: 0 range: enclosingRange].location;
        if ( newlineIdx != NSNotFound && newlineIdx <= breakPoint )
        {
            // switch to a new line, resetting the break point as appropriate.
            breakPoint = newlineIdx+1 + (column-indent);
            [str appendString: [base substringWithRange: enclosingRange]];
            return;
        }
        
        // if we haven't met the break point, just append the enclosing range
        if ( NSLocationInRange(breakPoint, enclosingRange) == NO )
        {
            [str appendString: [base substringWithRange: enclosingRange]];
            return;
        }
        
        if ( breakPoint == enclosingRange.location )
        {
            // insert a newline before this word
            [str appendFormat: @"\n%@", indentStr];
            [str appendString: [base substringWithRange: enclosingRange]];
            breakPoint += (column-indent);       // update breakPoint for the new line
            return;
        }
        
        // even if there is a newline character, it occurs beyond the last column, so we need to break before it anyway
        // is the break point in the word, or the surrounding characters?
        if ( NSLocationInRange(breakPoint, substringRange) == NO )
        {
            // is there whitespace following the word itself? If so, break there if possible.
            NSRange ws = [base rangeOfCharacterFromSet: whitespace options: 0 range: enclosingRange];
            if ( ws.location != NSNotFound )
            {
                NSRange r = enclosingRange;
                r.length = ws.location - enclosingRange.location;
                [str appendString: [base substringWithRange: r]];
                [str appendFormat: @"\n%@", indentStr];
                
                breakPoint += (column-indent-(enclosingRange.length-r.length));
                
                if ( NSMaxRange(ws) < NSMaxRange(enclosingRange) )
                {
                    // some character followed the whitespace
                    r.location = NSMaxRange(ws);
                    r.length = NSMaxRange(enclosingRange) - r.location;
                    [str appendString: [base substringWithRange: r]];
                }
                
                return;
            }
        }
        
        // break within the word using hyphenation if possible
        UTF32Char hyphen = (UTF32Char)'-';
        NSUInteger breakAt = (NSUInteger)CFStringGetHyphenationLocationBeforeIndex((__bridge CFStringRef)base, breakPoint, CFRangeMake(substringRange.location, substringRange.length), 0, (__bridge CFLocaleRef)locale, &hyphen);
        if ( breakAt != kCFNotFound )
        {
            NSString * hyphenStr = CFBridgingRelease(CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, (UInt8 *)&hyphen, sizeof(UTF32Char), kCFStringEncodingUTF32LE, FALSE, kCFAllocatorNull));
            
            // we have our hyphenation point, gentlemen
            NSRange r = NSMakeRange(enclosingRange.location, breakAt-enclosingRange.location);
            [str appendString: [base substringWithRange: r]];
            [str appendFormat: @"%@\n%@", hyphenStr, indentStr];
            
            r.location += r.length;
            r.length = NSMaxRange(enclosingRange) - r.location;
            
            [str appendString: [base substringWithRange: r]];
            
            breakPoint += (column-indent-r.length);
            return;
        }
        
        // otherwise we couldn't hyphenate, so break before the entire word
        [str appendFormat: @"\n%@", indentStr];
        breakPoint += (column-indent-enclosingRange.length);
        [str appendString: [base substringWithRange: enclosingRange]];
    }];
}

- (void) _plainWrapString: (NSMutableString *) str withIndent: (NSUInteger) indent atColumn: (NSUInteger) column
{
    NSMutableString * indentStr = [NSMutableString new];
    for ( NSUInteger i = 0; i < indent; i++ )
        [indentStr appendString: @" "];
    
    // indent first line
    [str insertString: indentStr atIndex: 0];
    if ( column == 0 )      // no wrapping required
        return;
    
    // replace all tabs with the indent string
    [str replaceOccurrencesOfString: @"\t" withString: indentStr options: 0 range: NSMakeRange(0, [str length])];
    
    // break point for current line-- will be updated as we wrap
    __block NSUInteger breakPoint = column;
    NSString * base = [str copy];
    [str setString: @""];
    
    NSCharacterSet * whitespace = [NSCharacterSet whitespaceCharacterSet];
    
    [base enumerateSubstringsInRange: NSMakeRange(0, [base length]) options: NSStringEnumerationByWords usingBlock: ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        // see if the description string contains a specific newline character already
        NSUInteger newlineIdx = [base rangeOfString: @"\n" options: 0 range: enclosingRange].location;
        if ( newlineIdx != NSNotFound && newlineIdx <= breakPoint )
        {
            // switch to a new line, resetting the break point as appropriate.
            breakPoint = newlineIdx+1 + (column-indent);
            [str appendString: [base substringWithRange: enclosingRange]];
            return;
        }
        
        // if we haven't met the break point, just append the enclosing range
        if ( NSLocationInRange(breakPoint, enclosingRange) == NO )
        {
            [str appendString: [base substringWithRange: enclosingRange]];
            return;
        }
        
        if ( breakPoint == enclosingRange.location )
        {
            // insert a newline before this word
            [str appendFormat: @"\n%@", indentStr];
            [str appendString: [base substringWithRange: enclosingRange]];
            breakPoint += (column-indent);       // update breakPoint for the new line
            return;
        }
        
        // even if there is a newline character, it occurs beyond the last column, so we need to break before it anyway
        // is the break point in the word, or the surrounding characters?
        if ( NSLocationInRange(breakPoint, substringRange) )
        {
            // have to wrap within the word, so break before it
            [str appendFormat: @"\n%@", indentStr];
            breakPoint += (column-indent-enclosingRange.length);
            [str appendString: [base substringWithRange: enclosingRange]];
            return;
        }
        
        // is there whitespace following the word itself? If so, break there if possible.
        NSRange ws = [base rangeOfCharacterFromSet: whitespace options: 0 range: enclosingRange];
        if ( ws.location != NSNotFound )
        {
            NSRange r = enclosingRange;
            r.length = ws.location - enclosingRange.location;
            [str appendString: [base substringWithRange: r]];
            [str appendFormat: @"\n%@", indentStr];
            
            breakPoint += (column-indent-(enclosingRange.length-r.length));
            
            if ( NSMaxRange(ws) < NSMaxRange(enclosingRange) )
            {
                // some character followed the whitespace
                r.location = NSMaxRange(ws);
                r.length = NSMaxRange(enclosingRange) - r.location;
                [str appendString: [base substringWithRange: r]];
            }
            
            return;
        }
        
        // break before the entire word
        [str appendFormat: @"\n%@", indentStr];
        breakPoint += (column-indent-enclosingRange.length);
        [str appendString: [base substringWithRange: enclosingRange]];
        return;
    }];
}

- (NSString *) localizedUsageForOutputLineWidth: (NSUInteger) lineWidth
{
    // generate the description string
    NSString * descBase = [_usageInformation objectForKey: AQOptionUsageLocalizedDescription];
    if ( descBase == nil )
        descBase = (_optional ? @"Optional." : @"Required.");
    else if ( [descBase hasSuffix: @"."] == NO )
        descBase = [descBase stringByAppendingString: @"."];
    
    NSMutableString * description = [descBase mutableCopy];
    NSLocale * locale = [NSLocale currentLocale];
    if ( CFStringIsHyphenationAvailableForLocale((__bridge CFLocaleRef)locale) )
    {
        [self _hyphenatingWrapString: description withIndent: 4 atColumn: lineWidth forLocale: locale];
    }
    else
    {
        [self _plainWrapString: description withIndent: 4 atColumn: lineWidth];
    }
    
    return ( [NSString stringWithFormat: @"%@\n%@", _localizedOptionExample, description] );
}

- (NSString *) description
{
    return ( [NSString stringWithFormat: @"%@: --%@ | -%@", [super description], _longName, _shortName] );
}

- (NSUInteger) hash
{
    return ( [_longName hash] );
}

- (BOOL) isEqual: (id) object
{
    if ( object == nil )
        return ( NO );
    if ( [object isKindOfClass: [self class]] == NO )
        return ( NO );
    
    return ( [_longName isEqualToString: ((AQOption *)object)->_longName] );
}

@end

@implementation AQOption (Internal)

- (void) addedToRequirementGroup: (AQOptionRequirementGroup *) requirementGroup
{
    _requirementGroup = requirementGroup;
}

- (void) matchedWithParameter: (NSString *) parameter
{
    [self willChangeValueForKey: @"matched"];
    _matched = YES;
    [self didChangeValueForKey: @"matched"];
    
    [self willChangeValueForKey: @"parameter"];
    _parameter = [parameter copy];
    [self didChangeValueForKey: @"parameter"];
    
    [_requirementGroup optionWasMatched: self];
    
    if ( _matchHandler != nil )
        _matchHandler(_longName, _parameter);
}

- (void) setGetoptParameters: (struct option *) option
{
    option->name = [_longName UTF8String];
    option->flag = NULL;
    option->val = (int)[_shortName characterAtIndex: 0];
    
    switch ( _parameterType )
    {
        case AQOptionParameterTypeNone:
            option->has_arg = no_argument;
            break;
        default:
        case AQOptionParameterTypeOptional:
            option->has_arg = optional_argument;
            break;
        case AQOptionParameterTypeRequired:
            option->has_arg = required_argument;
            break;
    }
}

@end

enum
{
    LongNameIndex,
    ShortNameIndex,
    TypeIndex,
    OptionalIndex,
    HandlerIndex,
    DescIndex,
    ValueIndex
};

#define OBJECT_OR_NIL(obj) (obj == [NSNull null] ? nil : obj)

@implementation AQOption (AQOptionListCreationHelper)

+ (NSArray *) optionsWithArrayDefinitions: (NSArray *) arrayDefinitions
{
    if ( [arrayDefinitions count] == 0 )
        return ( nil );
    
    NSMutableArray * result = [[NSMutableArray alloc] initWithCapacity: [arrayDefinitions count]];
    
    for ( NSArray * definition in arrayDefinitions )
    {
        if ( [definition isKindOfClass: [NSArray class]] == NO || [definition count] < 7 )
            [NSException raise: NSInvalidArgumentException format: @"Array %@ does not match prescribed format", definition];
        
        // unpack it
        __block NSString * longName, * shortName, * desc, * value;
        __block AQOptionParameterType type;
        __block BOOL optional;
        __block void (^handler)(NSString *, NSString *);
        [definition enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop) {
            switch ( idx )
            {
                case LongNameIndex:
                    longName = OBJECT_OR_NIL(obj);
                    break;
                case ShortNameIndex:
                    shortName = OBJECT_OR_NIL(obj);
                    break;
                case TypeIndex:
                    type = [OBJECT_OR_NIL(obj) intValue];
                    break;
                case OptionalIndex:
                    optional = [OBJECT_OR_NIL(obj) boolValue];
                    break;
                case HandlerIndex:
                    handler = OBJECT_OR_NIL(obj);
                    break;
                case DescIndex:
                    desc = OBJECT_OR_NIL(obj);
                    break;
                case ValueIndex:
                    value = OBJECT_OR_NIL(obj);
                    break;
                default:
                    break;
            }
        }];
        
        if ( longName == nil || shortName == nil )
            [NSException raise: NSInvalidArgumentException format: @"Array %@ does not match prescribed format", definition];
        
        AQOption * option = [[AQOption alloc] initWithLongName: longName shortName: [shortName characterAtIndex: 0] requiresParameter: type optional: optional handler: handler];
        if ( desc != nil || value != nil )
        {
            NSMutableDictionary * dict = [NSMutableDictionary new];
            if ( desc != nil )
                [dict setObject: desc forKey: AQOptionUsageLocalizedDescription];
            if ( value != nil )
                [dict setObject: desc forKey: AQOptionUsageLocalizedValueName];
            option.localizedUsageInformation = dict;
        }
        
        [result addObject: option];
    }
    
    return ( [result copy] );
}

@end
