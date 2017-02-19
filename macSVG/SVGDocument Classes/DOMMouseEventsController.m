//
//  DOMMouseEventsController.m
//  macSVG
//
//  Created by Douglas Ward on 1/25/12.
//  Copyright © 2016 ArkPhone LLC. All rights reserved.
//

#import "DOMMouseEventsController.h"
#import <WebKit/WebKit.h>
#import "MacSVGDocument.h"
#import "MacSVGDocumentWindowController.h"
#import "SVGWebKitController.h"
#import "SVGWebView.h"
#import "SVGPathEditor.h"
#import "SVGPolylineEditor.h"
#import "SVGLineEditor.h"
#import "XMLOutlineController.h"
#import "NSOutlineView_Extensions.h"
#import "AnimationTimelineView.h"
#import "SVGXMLDOMSelectionManager.h"
#import "SelectedElementsManager.h"
#import "WebKitInterface.h"
#import "MacSVGAppDelegate.h"
#import "DOMSelectionControlsManager.h"
#import "EditorUIFrameController.h"
#import "ElementEditorPlugInController.h"
#import "MacSVGPlugin/MacSVGPlugin.h"

#import "DOMSelectionCacheRecord.h"

@implementation DOMMouseEventsController

//==================================================================================
//	dealloc
//==================================================================================

- (void)dealloc
{
    self.validElementsForTransformDictionary = NULL;
}

//==================================================================================
//	init
//==================================================================================

- (instancetype)init
{
    self = [super init];
    if (self) 
    {
        // Initialization code here.
        self.mouseMode = MOUSE_DISENGAGED;
        self.clickPoint = NSMakePoint(0, 0);
        self.currentMousePoint = self.clickPoint;
        self.previousMousePoint = self.clickPoint;
        self.clickTarget = NULL;
        mouseMoveCount = 0;
        selectionHandleClicked = NO;
        handle_orientation = NULL;

        self.validElementsForTransformDictionary = @{@"rect": @"rect",
                @"circle": @"circle",
                @"ellipse": @"ellipse",
                @"text": @"text",
                @"image": @"image",
                @"line": @"line",
                @"polyline": @"polyline",
                @"polygon": @"polygon",
                @"path": @"path",
                @"use": @"use",
                @"g": @"g",
                @"foreignObject": @"foreignObject"};
    }
    
    return self;
}

//==================================================================================
//	floatFromString:
//==================================================================================

-(float) floatFromString:(NSString *)valueString
{
    float floatValue = 0;
    
    NSMutableString * trimmedString = [[NSMutableString alloc] init];
    
    NSUInteger inputLength = valueString.length;
    for (int i = 0; i < inputLength; i++)
    {
        unichar aChar = [valueString characterAtIndex:i];
        
        BOOL validChar = YES;
        
        if (aChar < '0') validChar = NO;
        if (aChar > '9') validChar = NO;
        if (aChar == '.') validChar = YES;
        if (aChar == '-') validChar = YES;
        
        if (validChar == NO) 
        {
            break;
        }
        
        NSString * charString = [[NSString alloc] initWithFormat:@"%C", aChar];
        
        [trimmedString appendString:charString];
    }
    
    floatValue = trimmedString.floatValue;
    
    return floatValue;
}

//==================================================================================
//	allocFloatString:
//==================================================================================

- (NSMutableString *)allocFloatString:(float)aFloat
{
    NSMutableString * aString = [[NSMutableString alloc] initWithFormat:@"%f", aFloat];

    BOOL continueTrim = YES;
    while (continueTrim == YES)
    {
        NSUInteger stringLength = aString.length;
        
        if (stringLength <= 1)
        {
            continueTrim = NO;
        }
        else
        {
            unichar lastChar = [aString characterAtIndex:(stringLength - 1)];
            
            if (lastChar == '0')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
            }
            else if (lastChar == '.')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
                continueTrim = NO;
            }
            else
            {
                continueTrim = NO;
            }
        }
    }
    return aString;
}

//==================================================================================
//	allocPxString:
//==================================================================================

- (NSMutableString *)allocPxString:(float)aFloat
{
    NSMutableString * aString = [[NSMutableString alloc] initWithFormat:@"%f", aFloat];

    BOOL continueTrim = YES;
    while (continueTrim == YES)
    {
        NSUInteger stringLength = aString.length;
        
        if (stringLength <= 1)
        {
            continueTrim = NO;
        }
        else
        {
            unichar lastChar = [aString characterAtIndex:(stringLength - 1)];
            
            if (lastChar == '0')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
            }
            else if (lastChar == '.')
            {
                NSRange deleteRange = NSMakeRange(stringLength - 1, 1);
                [aString deleteCharactersInRange:deleteRange];
                continueTrim = NO;
            }
            else
            {
                continueTrim = NO;
            }
        }
    }
    
    [aString appendString:@"px"];
    
    return aString;
}


//==================================================================================
//	updatePathMode:
//==================================================================================

-(void) updatePathMode:(NSString *)newPathMode;
{
    if (self.mouseMode == MOUSE_HOVERING)
    {
        [self.svgPathEditor updatePathMode:newPathMode];
    }
}


//==================================================================================
//	setDefaultForElement:name:value
//==================================================================================

-(void) setDefaultForElement:(DOMElement *)aElement 
        name:(NSString *)attributeName value:(NSString *)defaultValue
{
    NSString * attribute = [aElement getAttributeNS:NULL localName:attributeName];

    BOOL setNewAttribute = NO;

    if (attribute == NULL)
    {
        setNewAttribute = YES;
    }
    else if ([attribute isEqualToString:@""] == YES)
    {
        setNewAttribute = YES;
    }

    if (setNewAttribute == YES)
    {
        [aElement setAttributeNS:NULL qualifiedName:attributeName value:defaultValue];
    }
}


//==================================================================================
//	translatePoint
//==================================================================================

-(NSPoint) translatePoint:(NSPoint)aMousePoint targetElement:(DOMElement *)targetElement
{
    NSPoint resultPoint = aMousePoint;

    DOMDocument * domDocument = svgWebView.mainFrame.DOMDocument;

    DOMNodeList * svgElementsList = [domDocument getElementsByTagNameNS:svgNamespace localName:@"svg"];
    if (svgElementsList.length > 0)
    {
        DOMNode * svgElementNode = [svgElementsList item:0];
        DOMElement * svgElement = (DOMElement *)svgElementNode;

        MacSVGAppDelegate * macSVGAppDelegate = (MacSVGAppDelegate *)NSApp.delegate;
        WebKitInterface * webKitInterface = [macSVGAppDelegate webKitInterface];

        resultPoint = [webKitInterface transformPoint:aMousePoint fromElement:svgElement toElement:targetElement];
    }
    
    return resultPoint;
}

//==================================================================================
//	syncSelectedElementsToXMLDocument:
//==================================================================================

-(void) syncSelectedElementsToXMLDocument
{
    [self.svgXMLDOMSelectionManager syncSelectedDOMElementsToXMLDocument];
}

//==================================================================================
//	extendPolyline
//==================================================================================

- (void)extendPolyline
{
    DOMElement * polylineElement = [self.svgXMLDOMSelectionManager activeDOMElement];
    
    NSString * pointsString = [polylineElement getAttribute:@"points"];
            
    NSCharacterSet * pointsCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    
    NSArray * pointsComponents = [pointsString componentsSeparatedByCharactersInSet:pointsCharacterSet];
    
    NSMutableArray * pointsArray = [[NSMutableArray alloc] init];
    
    for (NSString * aString in pointsComponents)
    {
        if ([aString isEqualToString:@""] == NO)
        {
            [pointsArray addObject:aString];
        }
    }
    
    NSUInteger pointsArrayCount = pointsArray.count;

    NSString * newXString = [self allocFloatString:self.currentMousePoint.x];
    NSString * newYString = [self allocFloatString:self.currentMousePoint.y];
    
    pointsArray[(pointsArrayCount - 2)] = newXString;
    pointsArray[(pointsArrayCount - 1)] = newYString;
    
    NSString * xString = @"0";
    NSString * yString = @"0";
    
    NSMutableString * newPointsString = [[NSMutableString alloc] init];
    
    for (int i = 0; i < pointsArrayCount; i+=2) 
    {
        xString = pointsArray[i];
        yString = pointsArray[(i + 1)];
        
        if (i > 0) 
        {
            [newPointsString appendString:@" "];
        }
        
        [newPointsString appendString:xString];
        [newPointsString appendString:@","];
        [newPointsString appendString:yString];
    }

    // add a new point by repeating the last coordinate
    [newPointsString appendString:@" "];
    [newPointsString appendString:xString];
    [newPointsString appendString:@","];
    [newPointsString appendString:yString];

    [polylineElement setAttribute:@"points" value:newPointsString];
}

//==================================================================================
//	offsetPolyline:deltaX:deltaY:
//==================================================================================

- (void)offsetPolyline:(DOMElement *)polylineElement deltaX:(float)deltaX deltaY:(float)deltaY
{
    NSString * pointsString = [polylineElement getAttribute:@"points"];
            
    NSCharacterSet * pointsCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
    
    NSArray * pointsComponents = [pointsString componentsSeparatedByCharactersInSet:pointsCharacterSet];
    
    NSMutableArray * pointsArray = [[NSMutableArray alloc] init];
    
    for (NSString * aString in pointsComponents)
    {
        if ([aString isEqualToString:@""] == NO)
        {
            [pointsArray addObject:aString];
        }
    }
    
    NSUInteger pointsArrayCount = pointsArray.count;

    NSMutableString * newPointsString = [[NSMutableString alloc] init];
    
    for (int i = 0; i < pointsArrayCount; i+=2) 
    {
        NSString * xString = pointsArray[i];
        NSString * yString = pointsArray[(i + 1)];
        
        float x = xString.floatValue;
        float y = yString.floatValue;
        
        float newX = x + deltaX;
        float newY = y + deltaY;
        
        NSString * newXString = [self allocFloatString:newX];
        NSString * newYString = [self allocFloatString:newY];

        pointsArray[i] = newXString;
        pointsArray[(i + 1)] = newYString;
        
        if (i > 0) 
        {
            [newPointsString appendString:@" "];
        }
        
        [newPointsString appendString:newXString];
        [newPointsString appendString:@","];
        [newPointsString appendString:newYString];
    }

    [polylineElement setAttribute:@"points" value:newPointsString];

    NSMutableArray * polylinePointsArray = [NSMutableArray array];
    for (NSInteger i = 0; i < pointsArray.count; i += 2)
    {
        NSString * xString = [pointsArray objectAtIndex:i];
        NSString * yString = [pointsArray objectAtIndex:i + 1];
        
        NSMutableDictionary * aPointDictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            xString, @"x",
            yString, @"y",
            NULL];
        
        [polylinePointsArray addObject:aPointDictionary];
    }

    [self.svgPolylineEditor updatePolylineInDOMForElement:polylineElement polylinePointsArray:polylinePointsArray];
}


//==================================================================================
//	endPolylineDrawing
//==================================================================================

- (void) endPolylineDrawing
{
    if (self.mouseMode == MOUSE_HOVERING)
    {
        if ((macSVGDocumentWindowController.currentToolMode == toolModePolyline) ||
                (macSVGDocumentWindowController.currentToolMode == toolModePolygon))
        {
            self.mouseMode = MOUSE_DISENGAGED;

            DOMElement * polylineElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            
            NSString * pointsString = [polylineElement getAttribute:@"points"];
                    
            NSCharacterSet * pointsCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@" ,"];
            
            NSArray * pointsComponents = [pointsString componentsSeparatedByCharactersInSet:pointsCharacterSet];
            
            NSMutableArray * pointsArray = [[NSMutableArray alloc] init];
            
            for (NSString * aString in pointsComponents)
            {
                if ([aString isEqualToString:@""] == NO)
                {
                    [pointsArray addObject:aString];
                }
            }
            
            NSUInteger pointsArrayCount = pointsArray.count;

            NSString * newXString = [self allocFloatString:self.currentMousePoint.x];
            NSString * newYString = [self allocFloatString:self.currentMousePoint.y];
            
            pointsArray[(pointsArrayCount - 2)] = newXString;
            pointsArray[(pointsArrayCount - 1)] = newYString;
            
            NSString * xString = @"0";
            NSString * yString = @"0";
            
            NSMutableString * newPointsString = [[NSMutableString alloc] init];
            
            NSInteger outputPointsArrayCount = pointsArrayCount - 2;
            
            for (int i = 0; i < outputPointsArrayCount; i+=2) 
            {
                xString = pointsArray[i];
                yString = pointsArray[(i + 1)];
                
                if (i > 0) 
                {
                    [newPointsString appendString:@" "];
                }
                
                [newPointsString appendString:xString];
                [newPointsString appendString:@","];
                [newPointsString appendString:yString];
            }

            [polylineElement setAttribute:@"points" value:newPointsString];
            
            [self syncSelectedElementsToXMLDocument];
            
            [macSVGDocumentWindowController reloadAttributesTableData];

            [self.svgXMLDOMSelectionManager selectXMLElement:self.svgXMLDOMSelectionManager.activeXMLElement];
            
            self.clickTarget = NULL;
            
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;

            [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
        }
    }

    [self.svgPolylineEditor removePolylineHandles];
}

//==================================================================================
//	endLineDrawing
//==================================================================================

- (void) endLineDrawing
{
    if (self.mouseMode == MOUSE_HOVERING)
    {
        if (macSVGDocumentWindowController.currentToolMode == toolModeLine)
        {
            self.mouseMode = MOUSE_DISENGAGED;

            [self syncSelectedElementsToXMLDocument];
            
            [macSVGDocumentWindowController reloadAttributesTableData];

            [self.svgXMLDOMSelectionManager selectXMLElement:self.svgXMLDOMSelectionManager.activeXMLElement];
            
            self.clickTarget = NULL;
            
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;

            [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
        }
    }

    [self.svgLineEditor removeLineHandles];
}

//==================================================================================
//	endPathDrawing
//==================================================================================

-(void) endPathDrawing
{
    if (self.mouseMode == MOUSE_HOVERING)
    {
        if (macSVGDocumentWindowController.currentToolMode == toolModePath)
        {
            self.mouseMode = MOUSE_DISENGAGED;

            [self.svgPathEditor deleteLastSegmentInPath];
                        
            [self.svgXMLDOMSelectionManager selectXMLElement:self.svgXMLDOMSelectionManager.activeXMLElement];

            self.clickPoint = self.currentMousePoint;
            self.clickTarget = NULL;
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;

            [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
        }
    }

    [self.svgPathEditor removePathHandles];
}

//==================================================================================
//	endTextEditing
//==================================================================================

-(void) endTextEditing
{
    DOMElement * aElement = [self.svgXMLDOMSelectionManager.selectedElementsManager
            firstDomElement];

    if (aElement != NULL)
    {
        NSString * tagName = aElement.tagName;
        if ([tagName isEqualToString:@"text"] == YES) 
        {
            NSString * innerText = aElement.innerText;
            NSString * macsvgid = [aElement  getAttribute:@"macsvgid"];
            [macSVGDocumentWindowController updateXMLTextContent:innerText macsvgid:macsvgid];
        }
    }

    [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
}

//==================================================================================
//	handleCrosshairToolSelection:targetXmlElement:handleDOMElement:
//==================================================================================

-(void) handleCrosshairToolSelectionWithTargetXMLElement:(NSXMLElement *)targetXMLElement
        handleDOMElement:(DOMElement *)handleDOMElement
{
    // test for click on handles for existing selection, or new selection (not necessarily originalTargetXmlElement)

    NSString * targetXmlElementName = targetXMLElement.name;
    
    if ([targetXmlElementName isEqualToString:@"path"] == YES)
    {
        NSInteger pathEditingMode = kPathEditingModeNotActive;

        if (self.svgPathEditor.selectedPathElement != NULL)
        {        
            pathEditingMode = [self.svgPathEditor didBeginPathEditingWithTargetXMLElement:targetXMLElement
                    handleDOMElement:handleDOMElement];
        }
        
        if (pathEditingMode != kPathEditingModeNotActive)
        {
            NSXMLElement * xmlPathElement = self.svgPathEditor.selectedPathElement;
        
            self.svgXMLDOMSelectionManager.activeXMLElement = xmlPathElement;

            DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            NSString * tagName = activeDOMElement.tagName;
            
            [self.svgXMLDOMSelectionManager.selectedElementsManager removeAllElements];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];

            [self.svgXMLDOMSelectionManager.selectedElementsManager
                    addElementDictionaryWithXMLElement:xmlPathElement
                    domElement:activeDOMElement];
            
            if ([tagName isEqualToString:@"path"] == YES)
            {
                NSInteger result = [self.svgPathEditor setActiveDOMHandle:handleDOMElement];
                #pragma unused(result)
                
                [self.svgPathEditor updateActivePathInDOM];
                
                [self.svgXMLDOMSelectionManager selectXMLElement:xmlPathElement];
                
                [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
            }
        }
        else
        {
            [macSVGDocumentWindowController.xmlAttributesTableController unsetXmlElementForAttributesTable];

            NSString * tagName = targetXMLElement.name;
            
            if ([tagName isEqualToString:@"path"] == YES)
            {
                // build path segments for new selection

                [self.svgPathEditor updateActivePathInDOM];

                [self.svgXMLDOMSelectionManager selectXMLElement:targetXMLElement];
                
                [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
            }
        }
    }
    else if ([targetXmlElementName isEqualToString:@"polyline"] == YES)
    {
        [self handleCrosshairToolSelectionForPolylineXMLElement:targetXMLElement
                handleDOMElement:handleDOMElement];
    }
    else if ([targetXmlElementName isEqualToString:@"polygon"] == YES)
    {
        [self handleCrosshairToolSelectionForPolylineXMLElement:targetXMLElement
                handleDOMElement:handleDOMElement];
    }
    else if ([targetXmlElementName isEqualToString:@"line"] == YES)
    {
        [self handleCrosshairToolSelectionForLineXMLElement:targetXMLElement
                handleDOMElement:handleDOMElement];
    }
}

//==================================================================================
//	handleCrosshairToolSelectionForPathXMLElement
//==================================================================================

-(void) handleCrosshairToolSelectionForPathXMLElement:(NSXMLElement *)pathXMLElement
        handleDOMElement:(DOMElement *)handleDOMElement
{
    // for path element selected in XMLOutlineView

    NSInteger pathEditingMode = kPathEditingModeNotActive;

    if (self.svgPathEditor.selectedPathElement != NULL)
    {        
        pathEditingMode = [self.svgPathEditor didBeginPathEditingWithTargetXMLElement:pathXMLElement
                handleDOMElement:handleDOMElement];
    }
    
    if (pathEditingMode != kPathEditingModeNotActive)
    {
        NSXMLElement * xmlPathElement = self.svgPathEditor.selectedPathElement;
    
        self.svgXMLDOMSelectionManager.activeXMLElement = xmlPathElement;

        DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
        NSString * tagName = activeDOMElement.tagName;
        
        [self.svgXMLDOMSelectionManager.selectedElementsManager removeAllElements];
        
        [domSelectionControlsManager removeDOMSelectionRectsAndHandles];

        [self.svgXMLDOMSelectionManager.selectedElementsManager
                addElementDictionaryWithXMLElement:xmlPathElement
                domElement:activeDOMElement];
        
        if ([tagName isEqualToString:@"path"] == YES)
        {
            // build path segments for new selection
            NSInteger result = [self.svgPathEditor setActiveDOMHandle:handleDOMElement];
            #pragma unused(result)

            [self.svgPathEditor updateActivePathInDOM];
            
            [self.svgXMLDOMSelectionManager selectXMLElement:xmlPathElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
        }
    }
    else
    {
        [self.svgPathEditor resetPathSegmentsArray];

        NSString * tagName = pathXMLElement.name;
        
        if ([tagName isEqualToString:@"path"] == YES)
        {
            // build path segments for new selection

            [self.svgPathEditor buildPathSegmentsArray:pathXMLElement];
            
            self.svgPathEditor.selectedPathElement = pathXMLElement;

            [self.svgPathEditor updateActivePathInDOM];

            [self.svgXMLDOMSelectionManager selectXMLElement:pathXMLElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
            
            [self.svgPathEditor makePathHandles];
        }
    }
}

//==================================================================================
//	handleCrosshairToolSelectionForPolylineXMLElement:handleDOMElement:
//==================================================================================

-(void) handleCrosshairToolSelectionForPolylineXMLElement:(NSXMLElement *)polylineXMLElement
        handleDOMElement:(DOMElement *)handleDOMElement
{
    // used for both polyline and polygon

    // for polyline element selected in XMLOutlineView

    NSInteger polylineEditingMode = kPolylineEditingModeNotActive;

    if (self.svgPolylineEditor.selectedPolylineElement != NULL)
    {        
        polylineEditingMode = [self.svgPolylineEditor didBeginPolylineEditingWithTargetXMLElement:polylineXMLElement
                handleDOMElement:handleDOMElement];
    }

    if (polylineEditingMode != kPolylineEditingModeNotActive)
    {
        NSXMLElement * xmlPolylineElement = self.svgPolylineEditor.selectedPolylineElement;
    
        self.svgXMLDOMSelectionManager.activeXMLElement = xmlPolylineElement;

        DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
        NSString * tagName = activeDOMElement.tagName;
        
        [self.svgXMLDOMSelectionManager.selectedElementsManager removeAllElements];
        
        [domSelectionControlsManager removeDOMSelectionRectsAndHandles];

        [self.svgXMLDOMSelectionManager.selectedElementsManager
                addElementDictionaryWithXMLElement:xmlPolylineElement
                domElement:activeDOMElement];

        BOOL validElementFound = NO;
        
        if ([tagName isEqualToString:@"polyline"] == YES)
        {
            validElementFound = YES;
        }
        else if ([tagName isEqualToString:@"polygon"] == YES)
        {
            validElementFound = YES;
        }
        
        if (validElementFound == YES)
        {
            // build polyline points array for new selection
            //BOOL result = [self.svgPolylineEditor findClickedPolylinePointHandle];

            NSInteger result = [self.svgPolylineEditor setActiveDOMHandle:handleDOMElement];
            #pragma unused(result)

            [self.svgPolylineEditor updateActivePolylineInDOM];
            
            [self.svgXMLDOMSelectionManager selectXMLElement:xmlPolylineElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
        }
    }
    else
    {
        [macSVGDocumentWindowController.xmlAttributesTableController unsetXmlElementForAttributesTable];

        NSString * tagName = polylineXMLElement.name;
        
        BOOL validElementFound = NO;
        
        if ([tagName isEqualToString:@"polyline"] == YES)
        {
            validElementFound = YES;
        }
        else if ([tagName isEqualToString:@"polygon"] == YES)
        {
            validElementFound = YES;
        }
        
        if (validElementFound == YES)
        {
            // build polyline points array for new selection

            [self.svgPolylineEditor buildPolylinePointsArray:polylineXMLElement];
            
            self.svgPolylineEditor.selectedPolylineElement = polylineXMLElement;

            [self.svgPolylineEditor updateActivePolylineInDOM];

            [self.svgXMLDOMSelectionManager selectXMLElement:polylineXMLElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
            
            [self.svgPolylineEditor makePolylineHandles];
        }
    }
}




//==================================================================================
//	handleCrosshairToolSelectionForLineXMLElement:handleDOMElement:
//==================================================================================

-(void) handleCrosshairToolSelectionForLineXMLElement:(NSXMLElement *)lineXMLElement
        handleDOMElement:(DOMElement *)handleDOMElement
{
    // for line element selected in XMLOutlineView

    NSInteger lineEditingMode = kLineEditingModeNotActive;

    if (self.svgLineEditor.selectedLineElement != NULL)
    {        
        lineEditingMode = [self.svgLineEditor didBeginLineEditingWithTargetXMLElement:lineXMLElement
                handleDOMElement:handleDOMElement];
    }

    if (lineEditingMode != kPolylineEditingModeNotActive)
    {
        NSXMLElement * xmlLineElement = self.svgLineEditor.selectedLineElement;
    
        self.svgXMLDOMSelectionManager.activeXMLElement = xmlLineElement;

        DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
        NSString * tagName = activeDOMElement.tagName;
        
        [self.svgXMLDOMSelectionManager.selectedElementsManager removeAllElements];
        
        [domSelectionControlsManager removeDOMSelectionRectsAndHandles];

        [self.svgXMLDOMSelectionManager.selectedElementsManager
                addElementDictionaryWithXMLElement:xmlLineElement
                domElement:activeDOMElement];

        BOOL validElementFound = NO;
        
        if ([tagName isEqualToString:@"line"] == YES)
        {
            validElementFound = YES;
        }
        
        if (validElementFound == YES)
        {
            NSInteger result = [self.svgPolylineEditor setActiveDOMHandle:handleDOMElement];
            #pragma unused(result)

            [self.svgLineEditor updateActiveLineInDOM];
            
            [self.svgXMLDOMSelectionManager selectXMLElement:xmlLineElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
        }
    }
    else
    {
        [macSVGDocumentWindowController.xmlAttributesTableController unsetXmlElementForAttributesTable];

        NSString * tagName = lineXMLElement.name;
        
        BOOL validElementFound = NO;
        
        if ([tagName isEqualToString:@"line"] == YES)
        {
            validElementFound = YES;
        }
        
        if (validElementFound == YES)
        {
            self.svgLineEditor.selectedLineElement = lineXMLElement;

            [self.svgPolylineEditor updateActivePolylineInDOM];

            [self.svgXMLDOMSelectionManager selectXMLElement:lineXMLElement];
            
            [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
            
            [self.svgLineEditor makeLineHandles];
        }
    }
}

//==================================================================================
//	handleMouseDownEvent:
//==================================================================================

-(void) handleMouseDownEvent:(DOMEvent *)event
{
    //NSLog(@"handleMouseDownEvent");

    // for selecting elements or to initiate dragging for element creation
    self.mouseMode = MOUSE_DRAGGING;

    MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;
    
    DOMNode * targetNode = event.target;    // either a document node, or an editing handle node
    
    if ([macSVGDocument.fileNameExtension isEqualToString:@"svg"] == YES)
    {
        if ([targetNode isKindOfClass:[DOMHTMLElement class]] == YES)
        {
            // user clicked on an HTML-class element, is it contained within a foreignObject element?
            id parentElement = targetNode;    // either a document element, or an editing handle element
            BOOL continueSearch = YES;
            while (continueSearch == YES)
            {
                if (parentElement == NULL)
                {
                    continueSearch = NO;
                }
                else
                {
                    NSString * parentElementName = [parentElement tagName];
                    if ([parentElementName isEqualToString:@"foreignObject"] == YES)
                    {
                        continueSearch = NO;
                        targetNode = parentElement;     // change selection to the parent SVG-class foreignObject element
                    }
                }
                
                if (continueSearch == YES)
                {
                    parentElement = [parentElement parentElement];
                }
            }
        }
    }

    DOMElement * targetElement = (DOMElement *)targetNode;  // the real target element

    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    
    CGFloat zoomFactor = svgWebView.zoomFactor;
    self.currentMousePoint = NSMakePoint((float)mouseEvent.pageX * (1.0f / zoomFactor), (float)mouseEvent.pageY * (1.0f / zoomFactor));
    
    NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;

    // 20160627 - added check for toolModeArrowCursor
    if (currentToolMode == toolModeArrowCursor)
    {
        CGEventRef event = CGEventCreate(NULL);
        CGEventFlags modifiers = CGEventGetFlags(event);
        CFRelease(event);
        CGEventFlags flags = (kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
        if ((modifiers & flags) == 0)
        {
            // shift key or command key are not pressed
            self.currentMousePoint = [self translatePoint:self.currentMousePoint targetElement:targetElement];
        }
    }
    else
    {
        CGEventRef event = CGEventCreate(NULL);
        CGEventFlags modifiers = CGEventGetFlags(event);
        CFRelease(event);
        CGEventFlags flags = (kCGEventFlagMaskShift | kCGEventFlagMaskCommand);
        if ((modifiers & flags) != 0)
        {
            // shift key or command key are pressed
            self.currentMousePoint = [self translatePoint:self.currentMousePoint targetElement:targetElement];
        }
    }

    self.clickPoint = self.currentMousePoint;
    
    self.previousMousePoint = self.currentMousePoint;
    
    [event preventDefault];
    [event stopPropagation];

    NSString * newElementTagName = NULL;
        
    NSXMLElement * targetXMLElement = NULL;
    
    if (self.svgXMLDOMSelectionManager.activeXMLElement != NULL)
    {
        targetXMLElement = self.svgXMLDOMSelectionManager.activeXMLElement;
    }
    else
    {
        NSString * newTargetElementMacsvgid = [targetElement getAttribute:@"_macsvg_master_Macsvgid"];
        if (newTargetElementMacsvgid.length != 0)
        {
            // user clicked in a control handle, change the target to the owner of the handle
            NSXMLElement * newTargetElement = [macSVGDocument xmlElementForMacsvgid:newTargetElementMacsvgid];
            if (newTargetElement != NULL)
            {
                self.svgXMLDOMSelectionManager.activeXMLElement = newTargetElement;
                targetXMLElement = newTargetElement;
            }
        }
        else
        {
            // targetXMLElement is a document element, not a handle
            NSString * macsvgid = [targetElement getAttribute:@"macsvgid"];
            targetXMLElement = [macSVGDocument xmlElementForMacsvgid:macsvgid];
            self.svgXMLDOMSelectionManager.activeXMLElement = targetXMLElement;
        }
    }

    // test for click in existing selection handle
    selectionHandleClicked = NO;
    handle_orientation = NULL;
    NSString * classAttribute = [targetElement getAttribute:@"class"];
    if ([classAttribute isEqualToString:@"_macsvg_selectionHandle"] == YES)
    {
        selectionHandleClicked = YES;
        handle_orientation = NULL;
        NSString * newHandleOrientation = [targetElement getAttribute:@"_macsvg_handle_orientation"];
        
        // assign a string value to handle_orientation
        if ([newHandleOrientation isEqualToString:@"top"] == YES)
        {
            handle_orientation = @"top";
        }
        else if ([newHandleOrientation isEqualToString:@"left"] == YES)
        {
            handle_orientation = @"left";
        }
        else if ([newHandleOrientation isEqualToString:@"bottom"] == YES)
        {
            handle_orientation = @"bottom";
        }
        else if ([newHandleOrientation isEqualToString:@"right"] == YES)
        {
            handle_orientation = @"right";
        }
        else if ([newHandleOrientation isEqualToString:@"topLeft"] == YES)
        {
            handle_orientation = @"topLeft";
        }
        else if ([newHandleOrientation isEqualToString:@"topRight"] == YES)
        {
            handle_orientation = @"topRight";
        }
        else if ([newHandleOrientation isEqualToString:@"bottomLeft"] == YES)
        {
            handle_orientation = @"bottomLeft";
        }
        else if ([newHandleOrientation isEqualToString:@"bottomRight"] == YES)
        {
            handle_orientation = @"bottomRight";
        }
        
        //NSLog(@"handleMouseDownEvent - handle_orientation=%@", handle_orientation);
    }
    
    mouseMoveCount = 0;

    if ((currentToolMode != toolModeCrosshairCursor) && (currentToolMode != toolModePath) && (currentToolMode != toolModePolyline)  && (currentToolMode != toolModePolygon)&& (currentToolMode != toolModeLine))
    {
        [self.svgPathEditor resetPathSegmentsArray];
        [self.svgPolylineEditor resetPolylinePointsArray];
        [self.svgLineEditor resetLinePoints];
        
        [macSVGDocumentWindowController.xmlAttributesTableController unsetXmlElementForAttributesTable];
    }

    switch (currentToolMode) 
    {
        case toolModeNone:
            break;
        case toolModeArrowCursor:
        {
            if (selectionHandleClicked == NO)
            {
                MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;
                NSXMLDocument * svgXmlDocument = macSVGDocument.svgXmlDocument;
                NSXMLElement * rootXMLElement = [svgXmlDocument rootElement];
                if (targetXMLElement == rootXMLElement)
                {
                    XMLOutlineController * xmlOutlineController = macSVGDocumentWindowController.xmlOutlineController;
                    NSOutlineView * xmlOutlineView = xmlOutlineController.xmlOutlineView;
                    [(id)xmlOutlineView selectNone:self];
                }
                else
                {
                    [self.svgXMLDOMSelectionManager selectXMLElement:targetXMLElement];
                }
            }
            break;
        }
        case toolModeCrosshairCursor:
        {
            if (selectionHandleClicked == NO)
            {
                [self handleCrosshairToolSelectionWithTargetXMLElement:targetXMLElement handleDOMElement:targetElement];
            }
            break;
        }
        case toolModeRect:
        {
            newElementTagName = @"rect";
            break;
        }
        case toolModeCircle:
        {
            newElementTagName = @"circle";
            break;
        }
        case toolModeEllipse:
        {
            newElementTagName = @"ellipse";
            break;
        }
        case toolModeText:
        {
            newElementTagName = @"text";
            break;
        }
        case toolModeImage:
        {
            newElementTagName = @"image";
            break;
        }
        case toolModeLine:
        {
            newElementTagName = @"line";
            break;
        }
        case toolModePolyline:
        {
            BOOL extendExistingPolyline = NO;
            
            DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            if (activeDOMElement != NULL)
            {
                NSString * tagName = activeDOMElement.tagName;
                if ([tagName isEqualToString:@"polyline"] == YES)
                {
                    extendExistingPolyline = YES;
                }
            }
            
            if (extendExistingPolyline == YES)
            {   
                [self extendPolyline];
            }
            else
            {
                newElementTagName = @"polyline";
                self.mouseMode = MOUSE_HOVERING;
            }
            break;
        }
        case toolModePolygon:
        {
            BOOL extendExistingPolyline = NO;
            
            DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            if (activeDOMElement != NULL)
            {
                NSString * tagName = activeDOMElement.tagName;
                if ([tagName isEqualToString:@"polygon"] == YES)
                {
                    extendExistingPolyline = YES;
                }
            }
            
            if (extendExistingPolyline == YES)
            {   
                [self extendPolyline];
            }
            else
            {
                newElementTagName = @"polygon";
                self.mouseMode = MOUSE_HOVERING;
            }
            break;
        }
        case toolModePath:
        {
            //NSLog(@"handleMouseDownEvent - toolModePath");
            BOOL editExistingPath = NO;
            
            DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            if (activeDOMElement != NULL)
            {
                NSString * tagName = activeDOMElement.tagName;
                if ([tagName isEqualToString:@"path"] == YES)
                {
                    editExistingPath = YES;
                    
                    [macSVGDocument pushUndoRedoDocumentChanges];
                }
            }
            
            if (editExistingPath == NO)
            {
                newElementTagName = @"path";
            }
            break;
        }
        default:
        break;
    }

    if (selectionHandleClicked == YES)
    {
        // user clicked on a selection handle
        newElementTagName = NULL;       // not creating a new element, just modifying an existing one
        
        NSString * handle_Macsvgid = [targetElement getAttribute:@"_macsvg_master_Macsvgid"];
        NSXMLElement * handleXMLElement = [macSVGDocument xmlElementForMacsvgid:handle_Macsvgid];
        
        self.svgXMLDOMSelectionManager.activeXMLElement = handleXMLElement;
    }

    // create the new element according to the tool selection
    if (newElementTagName != NULL)
    {
        macSVGDocumentWindowController.creatingNewElement = YES;

        [domSelectionControlsManager removeDOMSelectionRectsAndHandles];

        [macSVGDocument pushUndoRedoDocumentChanges];
        
        NSXMLElement * newXMLElement = [macSVGDocument createElement:newElementTagName atPoint:self.clickPoint];
       
        if (newXMLElement != NULL)
        {
            [self.svgXMLDOMSelectionManager selectXMLElement:newXMLElement];

            if (currentToolMode == toolModePath)
            {
                [self.svgPathEditor startPath];       // set the moveto path segment
            }
            else if (currentToolMode == toolModePolyline)
            {
                [self.svgPolylineEditor startPolyline];
            }
            else if (currentToolMode == toolModePolygon)
            {
                [self.svgPolylineEditor startPolyline];
            }
            
            self.svgXMLDOMSelectionManager.activeXMLElement = newXMLElement;
        }
        
        macSVGDocumentWindowController.creatingNewElement = NO;
        
        // this code allows multiple mouse click to place images without having to click the Image tool icon each time
        if ([newElementTagName isEqualToString:@"image"] == YES)
        {
            if (macSVGDocumentWindowController.currentToolMode != toolModeImage)
            {
                [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
            }
            else
            {
                (macSVGDocumentWindowController.svgWebKitController.domMouseEventsController).mouseMode = MOUSE_DISENGAGED;
            }
            [macSVGDocumentWindowController reloadAllViews];
        }
    }
}

//==================================================================================
//	dragHandleForDOMElement:
//==================================================================================

-(void) dragHandleForDOMElement:(DOMElement *)aDomElement
{
    //NSLog(@"dragHandleForDOMElement:%@", aDomElement);
    
    NSString * tagName = aDomElement.tagName;
    
    NSString * elementName = aDomElement.nodeName;
    if ((self.validElementsForTransformDictionary)[elementName] != NULL)
    {
        if (([tagName isEqualToString:@"rect"] == YES) ||
                ([tagName isEqualToString:@"image"] == YES) ||
                ([tagName isEqualToString:@"foreignObject"] == YES))
        
        {
            NSString * xString = [aDomElement getAttribute:@"x"];
            NSString * yString = [aDomElement getAttribute:@"y"];
            NSString * widthString = [aDomElement getAttribute:@"width"];
            NSString * heightString = [aDomElement getAttribute:@"height"];
            
            if ((xString != NULL) && (yString != NULL) &&
                    (widthString != NULL) && (heightString != NULL) &&
                    (handle_orientation != NULL))
            {
                float x = xString.floatValue;
                float y = yString.floatValue;
                float width = widthString.floatValue;
                float height = heightString.floatValue;

                float deltaX = self.currentMousePoint.x - x;
                float deltaY = self.currentMousePoint.y - y;

                
                if ([handle_orientation isEqualToString:@"left"] == YES)
                {
                    float newX = self.currentMousePoint.x;
                    
                    if (newX > (x + width))
                    {
                        newX = x + width;
                        width = 0;
                    }
                    
                    float newY = y;
                    float newWidth = width - deltaX;
                    float newHeight = height;
                    
                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                    
                    NSString * newXString = [self allocPxString:newX];
                    NSString * newYString = [self allocPxString:newY];
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];
                    
                    [aDomElement setAttribute:@"x" value:newXString];
                    [aDomElement setAttribute:@"y" value:newYString];
                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
                {
                    float newX = self.currentMousePoint.x;
                    float newY = self.currentMousePoint.y;

                    if (newX > (x + width))
                    {
                        newX = x + width;
                        width = 0;
                    }
                    if (newY > (y + height))
                    {
                        newY = y + height;
                        height = 0;
                    }
                    
                    float newWidth = width - deltaX;
                    float newHeight = height - deltaY;
                    
                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                    
                    NSString * newXString = [self allocPxString:newX];
                    NSString * newYString = [self allocPxString:newY];
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];
                    
                    [aDomElement setAttribute:@"x" value:newXString];
                    [aDomElement setAttribute:@"y" value:newYString];
                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"top"] == YES)
                {
                    float newX = x;
                    float newY = self.currentMousePoint.y;

                    if (newY > (y + height))
                    {
                        newY = y + height;
                        height = 0;
                    }
 
                    float newWidth = width;
                    float newHeight = height - deltaY;
                   
                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                    
                    NSString * newXString = [self allocPxString:newX];
                    NSString * newYString = [self allocPxString:newY];
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];
                    
                    [aDomElement setAttribute:@"x" value:newXString];
                    [aDomElement setAttribute:@"y" value:newYString];
                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"topRight"] == YES)
                {
                    float newY = self.currentMousePoint.y;
                    float newWidth = self.currentMousePoint.x - x;
                    float newHeight = height - deltaY;

                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                    
                    NSString * newYString = [self allocPxString:newY];
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];
                    
                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"y" value:newYString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"right"] == YES)
                {
                    float newWidth = self.currentMousePoint.x - x;

                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    
                    NSString * newWidthString = [self allocPxString:newWidth];
                    
                    [aDomElement setAttribute:@"width" value:newWidthString];
                }
                else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
                {
                    float newX = self.currentMousePoint.x;
                    float newWidth = width - deltaX;
                    float newHeight = self.currentMousePoint.y - y;

                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                
                    NSString * newXString = [self allocPxString:newX];
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];

                    [aDomElement setAttribute:@"x" value:newXString];
                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"bottom"] == YES)
                {
                    float newHeight = self.currentMousePoint.y - y;

                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                
                    NSString * newHeightString = [self allocPxString:newHeight];

                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
                else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
                {
                    float newWidth = self.currentMousePoint.x - x;
                    float newHeight = self.currentMousePoint.y - y;
                    
                    if (newWidth < 0)
                    {
                        newWidth = 0;
                    }
                    if (newHeight < 0)
                    {
                        newHeight = 0;
                    }
                
                    NSString * newWidthString = [self allocPxString:newWidth];
                    NSString * newHeightString = [self allocPxString:newHeight];

                    [aDomElement setAttribute:@"width" value:newWidthString];
                    [aDomElement setAttribute:@"height" value:newHeightString];
                }
            }
            
            [self syncSelectedElementsToXMLDocument];
            
            [macSVGDocumentWindowController reloadAttributesTableData];
        }
        
        if ([tagName isEqualToString:@"circle"] == YES)
        {
            NSString * cxString = [aDomElement getAttribute:@"cx"];
            NSString * cyString = [aDomElement getAttribute:@"cy"];
            NSString * radiusString = [aDomElement getAttribute:@"r"];
                       
            if ((cxString != NULL) && (cyString != NULL) &&
                    (radiusString != NULL) && (handle_orientation != NULL))
            {
                float cx = cxString.floatValue;
                float cy = cyString.floatValue;

                if ([handle_orientation isEqualToString:@"top"] == YES) 
                {
                    CGFloat radius = cy - self.currentMousePoint.y;
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"left"] == YES)
                {
                    CGFloat radius = cx - self.currentMousePoint.x;
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"bottom"] == YES)
                {
                    CGFloat radius = self.currentMousePoint.y - cy;
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"right"] == YES)
                {
                    CGFloat radius = self.currentMousePoint.x - cx;
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
                {
                    CGFloat xDelta = cx - self.currentMousePoint.x;
                    CGFloat yDelta = cy - self.currentMousePoint.y;
                    
                    CGFloat radius = xDelta;
                    if (fabs(yDelta) < fabs(xDelta))
                    {
                        radius = yDelta;
                    }
                    
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"topRight"] == YES)
                {
                    CGFloat xDelta = self.currentMousePoint.x - cx;
                    CGFloat yDelta = cy - self.currentMousePoint.y;
                    
                    CGFloat radius = xDelta;
                    if (fabs(yDelta) < fabs(xDelta))
                    {
                        radius = yDelta;
                    }
                    
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
                {
                    CGFloat xDelta = cx - self.currentMousePoint.x;
                    CGFloat yDelta = self.currentMousePoint.y - cy;
                    
                    CGFloat radius = xDelta;
                    if (fabs(yDelta) < fabs(xDelta))
                    {
                        radius = yDelta;
                    }
                    
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
                {
                    CGFloat xDelta = self.currentMousePoint.x - cx;
                    CGFloat yDelta = self.currentMousePoint.y - cy;
                    
                    CGFloat radius = xDelta;
                    if (fabs(yDelta) < fabs(xDelta))
                    {
                        radius = yDelta;
                    }
                    
                    if (radius < 0)
                    {
                        radius = 0;
                    }
                    
                    NSString * newRadiusString = [self allocPxString:radius];
                    
                    [aDomElement setAttribute:@"r" value:newRadiusString];
                }
            }
            
            [self syncSelectedElementsToXMLDocument];
            
            [macSVGDocumentWindowController reloadAttributesTableData];
        }
        
        if ([tagName isEqualToString:@"ellipse"] == YES)
        {
            NSString * cxString = [aDomElement getAttribute:@"cx"];
            NSString * cyString = [aDomElement getAttribute:@"cy"];
            NSString * rxString = [aDomElement getAttribute:@"rx"];
            NSString * ryString = [aDomElement getAttribute:@"ry"];
                       
            if ((cxString != NULL) && (cyString != NULL) &&
                    (rxString != NULL) && (ryString != NULL) && 
                    (handle_orientation != NULL))
            {
                float cx = cxString.floatValue;
                float cy = cyString.floatValue;

                if ([handle_orientation isEqualToString:@"left"] == YES) 
                {
                    NSString * newRadiusString = [self allocPxString:(cx - self.currentMousePoint.x)];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"top"] == YES)
                {
                    NSString * newRadiusString = [self allocPxString:(cy - self.currentMousePoint.y)];
                    
                    [aDomElement setAttribute:@"ry" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"right"] == YES)
                {
                    NSString * newRadiusString = [self allocPxString:(self.currentMousePoint.x - cx)];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"bottom"] == YES)
                {
                    NSString * newRadiusString = [self allocPxString:(self.currentMousePoint.y - cy)];
                    
                    [aDomElement setAttribute:@"ry" value:newRadiusString];
                }
                else if ([handle_orientation isEqualToString:@"topLeft"] == YES)
                {
                    CGFloat xDelta = cx - self.currentMousePoint.x;
                    CGFloat yDelta = cy - self.currentMousePoint.y;
                    
                    CGFloat radiusX = xDelta;
                    CGFloat radiusY = yDelta;
                    
                    if (radiusX < 0)
                    {
                        radiusX = 0;
                    }
                    if (radiusY < 0)
                    {
                        radiusY = 0;
                    }
                    
                    NSString * newRadiusXString = [self allocPxString:radiusX];
                    NSString * newRadiusYString = [self allocPxString:radiusY];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusXString];
                    [aDomElement setAttribute:@"ry" value:newRadiusYString];
                }
                else if ([handle_orientation isEqualToString:@"topRight"] == YES)
                {
                    CGFloat xDelta = self.currentMousePoint.x - cx;
                    CGFloat yDelta = cy - self.currentMousePoint.y;
                    
                    CGFloat radiusX = xDelta;
                    CGFloat radiusY = yDelta;
                    
                    if (radiusX < 0)
                    {
                        radiusX = 0;
                    }
                    if (radiusY < 0)
                    {
                        radiusY = 0;
                    }
                    
                    NSString * newRadiusXString = [self allocPxString:radiusX];
                    NSString * newRadiusYString = [self allocPxString:radiusY];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusXString];
                    [aDomElement setAttribute:@"ry" value:newRadiusYString];
                }
                else if ([handle_orientation isEqualToString:@"bottomLeft"] == YES)
                {
                    CGFloat xDelta = cx - self.currentMousePoint.x;
                    CGFloat yDelta = self.currentMousePoint.y - cy;
                    
                    CGFloat radiusX = xDelta;
                    CGFloat radiusY = yDelta;
                    
                    if (radiusX < 0)
                    {
                        radiusX = 0;
                    }
                    if (radiusY < 0)
                    {
                        radiusY = 0;
                    }
                    
                    NSString * newRadiusXString = [self allocPxString:radiusX];
                    NSString * newRadiusYString = [self allocPxString:radiusY];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusXString];
                    [aDomElement setAttribute:@"ry" value:newRadiusYString];
                }
                else if ([handle_orientation isEqualToString:@"bottomRight"] == YES)
                {
                    CGFloat xDelta = self.currentMousePoint.x - cx;
                    CGFloat yDelta = self.currentMousePoint.y - cy;
                    
                    CGFloat radiusX = xDelta;
                    CGFloat radiusY = yDelta;
                    
                    if (radiusX < 0)
                    {
                        radiusX = 0;
                    }
                    if (radiusY < 0)
                    {
                        radiusY = 0;
                    }
                    
                    NSString * newRadiusXString = [self allocPxString:radiusX];
                    NSString * newRadiusYString = [self allocPxString:radiusY];
                    
                    [aDomElement setAttribute:@"rx" value:newRadiusXString];
                    [aDomElement setAttribute:@"ry" value:newRadiusYString];
                }
            }
            
            [self syncSelectedElementsToXMLDocument];
            
            [macSVGDocumentWindowController reloadAttributesTableData];
        }
        
        if ([tagName isEqualToString:@"line"] == YES)
        {
        }
        
        if ([tagName isEqualToString:@"polyline"] == YES)
        {
        }
        
        if ([tagName isEqualToString:@"polygon"] == YES)
        {
        }
        
        if ([tagName isEqualToString:@"path"] == YES)
        {
        }
        
        // apply update selection rectangles
        // TEST 20130709
        NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;
        if (currentToolMode != toolModeCrosshairCursor)
        {
            [domSelectionControlsManager updateDOMSelectionRectsAndHandles];
        }
    }
}

//==================================================================================
//	handleMouseMoveEventForSelection:
//==================================================================================

-(void) handleMouseMoveEventForSelection:(DOMEvent *)event
{
    //NSLog(@"handleMouseMoveEventForSelection");

    MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;

    if (mouseMoveCount == 1)
    {
        [macSVGDocument pushUndoRedoDocumentChanges];
    }
    
    SelectedElementsManager * selectedElementsManager =
            self.svgXMLDOMSelectionManager.selectedElementsManager;

    // update the rectangles around the selected elements

    float deltaX = self.currentMousePoint.x - self.previousMousePoint.x;
    float deltaY = self.currentMousePoint.y - self.previousMousePoint.y;

    // update the positions of the selected SVG elements
    NSUInteger selectedItemsCount = [selectedElementsManager selectedElementsCount];
    
    for (int i = 0; i < selectedItemsCount; i++)
    {
        // update the selected elements
        DOMElement * aSvgElement = [selectedElementsManager domElementAtIndex:i];

        NSString * tagName = aSvgElement.tagName;
        
        NSString * elementName = aSvgElement.nodeName;
        if ((self.validElementsForTransformDictionary)[elementName] != NULL)
        {
            DOMElement * locatableElement = (id)aSvgElement;
                        
            NSString * coordinateType = @"xy";

            if ([tagName isEqualToString:@"g"] == YES)
            {
                coordinateType = @"none";       // don't apply x,y attributes to groups
            }
            
            if ([tagName isEqualToString:@"circle"] == YES)
            {
                coordinateType = @"cxcy";
            }
            
            if ([tagName isEqualToString:@"ellipse"] == YES)
            {
                coordinateType = @"cxcy";
            }
            
            if ([tagName isEqualToString:@"line"] == YES)
            {
                coordinateType = @"xyxy";
            }
            
            if ([tagName isEqualToString:@"polyline"] == YES)
            {
                coordinateType = @"xyxyxy";     // not the best description, but it will do for now
            }
            
            if ([tagName isEqualToString:@"polygon"] == YES)
            {
                coordinateType = @"xyxyxy";
            }
            
            if ([tagName isEqualToString:@"path"] == YES)
            {
                coordinateType = @"d";
            }
            
            if ([coordinateType isEqualToString:@"xy"] == YES)
            {
                NSString * xString = [locatableElement getAttribute:@"x"];
                NSString * yString = [locatableElement getAttribute:@"y"];
                
                if ((xString != NULL) && (yString != NULL))
                {
                    float x = [self floatFromString:xString] + deltaX;
                    float y = [self floatFromString:yString] + deltaY;
                    
                    NSString * newXString = [self allocPxString:x];
                    NSString * newYString = [self allocPxString:y];
                    
                    [locatableElement setAttribute:@"x" value:newXString];
                    [locatableElement setAttribute:@"y" value:newYString];
                }
            }
            else if ([coordinateType isEqualToString:@"cxcy"] == YES)
            {
                NSString * xString = [locatableElement getAttribute:@"cx"];
                NSString * yString = [locatableElement getAttribute:@"cy"];

                if ((xString != NULL) && (yString != NULL))
                {
                    float cx = [self floatFromString:xString] + deltaX;
                    float cy = [self floatFromString:yString] + deltaY;
                    
                    NSString * newXString = [self allocPxString:cx];
                    NSString * newYString = [self allocPxString:cy];
                    
                    [locatableElement setAttribute:@"cx" value:newXString];
                    [locatableElement setAttribute:@"cy" value:newYString];
                }
            }
            else if ([coordinateType isEqualToString:@"xyxy"] == YES)
            {
                NSString * x1String = [locatableElement getAttribute:@"x1"];
                NSString * y1String = [locatableElement getAttribute:@"y1"];
                NSString * x2String = [locatableElement getAttribute:@"x2"];
                NSString * y2String = [locatableElement getAttribute:@"y2"];

                if ((x1String != NULL) && (y1String != NULL) && (x2String != NULL) && (y2String != NULL))
                {
                    float x1 = [self floatFromString:x1String] + deltaX;
                    float y1 = [self floatFromString:y1String] + deltaY;
                    float x2 = [self floatFromString:x2String] + deltaX;
                    float y2 = [self floatFromString:y2String] + deltaY;
                    
                    NSString * newX1String = [self allocPxString:x1];
                    NSString * newY1String = [self allocPxString:y1];
                    NSString * newX2String = [self allocPxString:x2];
                    NSString * newY2String = [self allocPxString:y2];
                    
                    [locatableElement setAttribute:@"x1" value:newX1String];
                    [locatableElement setAttribute:@"y1" value:newY1String];
                    [locatableElement setAttribute:@"x2" value:newX2String];
                    [locatableElement setAttribute:@"y2" value:newY2String];
                }
            }
            else if ([coordinateType isEqualToString:@"xyxyxy"] == YES)     // it is a polyline or polygon, see above
            {
                [self offsetPolyline:locatableElement deltaX:deltaX deltaY:deltaY];
            }
            else if ([coordinateType isEqualToString:@"d"] == YES)
            {
                [self.svgPathEditor offsetPath:locatableElement deltaX:deltaX deltaY:deltaY];
            }
            else if ([coordinateType isEqualToString:@"none"] == YES)
            {
            }
            else
            {
                NSLog(@"unknown coordinate type");
            }
        }
    }

    [self syncSelectedElementsToXMLDocument];
    [macSVGDocumentWindowController reloadAttributesTableData];

    // apply update selection rectangles
    // TEST 20130709
    NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;
    if (currentToolMode != toolModeCrosshairCursor)
    {
        [domSelectionControlsManager updateDOMSelectionRectsAndHandles];
    }
}    

//==================================================================================
//	handleMouseMoveEventForDrawingTool:
//==================================================================================

-(void) handleMouseMoveEventForDrawingTool:(DOMEvent *)event
{
    // handle drag events for drawing tools

    // find the element we are drawing
    NSString * tagName = NULL;

    DOMElement * updateDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];

    if (updateDOMElement != NULL)
    {
        // update the element, projected to current mouse position
        
        tagName = updateDOMElement.tagName;

        float objectOriginX = self.clickPoint.x;
        float objectOriginY = self.clickPoint.y;
        float objectWidth = self.currentMousePoint.x - self.clickPoint.x;
        float objectHeight = self.currentMousePoint.y - self.clickPoint.y;
        
        if (objectWidth < 0) 
        {
            objectOriginX = self.currentMousePoint.x;
            objectWidth = self.clickPoint.x - self.currentMousePoint.x;
        }
        
        if (objectHeight < 0) 
        {
            objectOriginY = self.currentMousePoint.y;
            objectHeight = self.clickPoint.y - self.currentMousePoint.y;
        }
        
        NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;

        switch (currentToolMode) 
        {
            case toolModeRect:
            {
                NSString * xString = [self allocPxString:objectOriginX];
                NSString * yString = [self allocPxString:objectOriginY];
                NSString * widthString = [self allocPxString:objectWidth];
                NSString * heightString = [self allocPxString:objectHeight];
                
                [updateDOMElement setAttribute:@"x" value:xString];
                [updateDOMElement setAttribute:@"y" value:yString];
                [updateDOMElement setAttribute:@"width" value:widthString];
                [updateDOMElement setAttribute:@"height" value:heightString];
                break;
            }
            case toolModeCircle:
            {
                float diffx = self.currentMousePoint.x - self.clickPoint.x;
                float diffy = self.currentMousePoint.y - self.clickPoint.y;
                
                float distance = diffx;
                if (diffy < diffx)
                {
                    distance = diffy;
                }
                
                float halfDistance = distance / 2.0f;
                
                float cx = self.clickPoint.x + halfDistance;
                float cy = self.clickPoint.y + halfDistance;
                
                NSString * cxString = [self allocPxString:cx];
                NSString * cyString = [self allocPxString:cy];
                NSString * rString = [self allocPxString:halfDistance];
                
                [updateDOMElement setAttribute:@"cx" value:cxString];
                [updateDOMElement setAttribute:@"cy" value:cyString];
                [updateDOMElement setAttribute:@"r" value:rString];
                
                objectWidth = distance;
                objectHeight = distance;
                break;
            }
            case toolModeEllipse:
            {
                float diffx = self.currentMousePoint.x - self.clickPoint.x;
                float diffy = self.currentMousePoint.y - self.clickPoint.y;
                
                float halfDistanceX = diffx / 2.0f;
                float halfDistanceY = diffy / 2.0f;
                
                float cx = self.clickPoint.x + halfDistanceX;
                float cy = self.clickPoint.y + halfDistanceY;
                
                NSString * cxString = [self allocPxString:cx];
                NSString * cyString = [self allocPxString:cy];
                NSString * rxString = [self allocPxString:halfDistanceX];
                NSString * ryString = [self allocPxString:halfDistanceY];
                
                [updateDOMElement setAttribute:@"cx" value:cxString];
                [updateDOMElement setAttribute:@"cy" value:cyString];
                [updateDOMElement setAttribute:@"rx" value:rxString];
                [updateDOMElement setAttribute:@"ry" value:ryString];
                
                objectWidth = diffx;
                objectHeight = diffy;
                break;
            }
            case toolModeText:
             {
                NSString * xString = [self allocPxString:self.currentMousePoint.x];
                NSString * yString = [self allocPxString:self.currentMousePoint.y];
                
                [updateDOMElement setAttribute:@"x" value:xString];
                [updateDOMElement setAttribute:@"y" value:yString];
                XMLOutlineController * xmlOutlineController = macSVGDocumentWindowController.xmlOutlineController;
                NSString * newStyleAttributeString = [xmlOutlineController addCSSStyleName:@"outline-style" styleValue:@"none" toDOMElement:updateDOMElement];
                [updateDOMElement setAttribute:@"style" value:newStyleAttributeString];
                break;
            }
           case toolModeImage:
            {
                break;
            }
            case toolModeLine:
            {
                float diffx = self.currentMousePoint.x - self.clickPoint.x;
                float diffy = self.currentMousePoint.y - self.clickPoint.y;

                NSString * x2String = [self allocPxString:self.currentMousePoint.x];
                NSString * y2String = [self allocPxString:self.currentMousePoint.y];
                
                [updateDOMElement setAttribute:@"x2" value:x2String];
                [updateDOMElement setAttribute:@"y2" value:y2String];
                
                objectWidth = diffx;
                objectHeight = diffy;
                break;
            }
            case toolModePolyline:
            case toolModePolygon:
            {
                float diffx = self.currentMousePoint.x - self.clickPoint.x;
                float diffy = self.currentMousePoint.y - self.clickPoint.y;
                
                objectWidth = diffx;
                objectHeight = diffy;
                break;
            }
            case toolModePath:
            {
                [self.svgPathEditor modifyPath];
                break;
            }
            default:
            {
                NSLog(@"handleMouseMoveEventForDrawingTool - undefined tool mode");
                break;
            }
        }
        
        // find the selection rectangles
        DOMElement * selectedRectElement = NULL;
        
        DOMElement * selectedRectsGroup = [domSelectionControlsManager
                getMacsvgTopGroupChildByID:@"_macsvg_selectedRectsGroup" createIfNew:NO];
        
        int selectedRectsCount = selectedRectsGroup.childElementCount;
        if (selectedRectsCount == 1)
        {
            DOMNode * selectedRectNode = [selectedRectsGroup.childNodes item:0];
            selectedRectElement = (id)selectedRectNode;

            MacSVGAppDelegate * macSVGAppDelegate = (MacSVGAppDelegate *)NSApp.delegate;
            WebKitInterface * webKitInterface = [macSVGAppDelegate webKitInterface];
            NSRect selectionRect = NSMakeRect(objectOriginX, objectOriginY, objectWidth, objectHeight);
            [webKitInterface setRect:selectionRect forElement:selectedRectElement];
        }
        
        [self syncSelectedElementsToXMLDocument];
        
        [macSVGDocumentWindowController reloadAttributesTableData];
    }

}

//==================================================================================
//	handleMouseMoveEventForCrosshairCursor:
//==================================================================================

-(void) handleMouseMoveEventForCrosshairCursor:(DOMEvent *)event
{
    // handle drag events for crosshair cursor tool
    MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;

    if (mouseMoveCount == 1)
    {
        [macSVGDocument pushUndoRedoDocumentChanges];
    }

    // find the selection rectangle
    DOMElement * selectedRectElement = NULL;
    
    DOMElement * selectedRectsGroup = [domSelectionControlsManager
            getMacsvgTopGroupChildByID:@"_macsvg_selectedRectsGroup" createIfNew:NO];
    
    int selectedRectsCount = selectedRectsGroup.childElementCount;
    if (selectedRectsCount == 1)
    {
        DOMNode * selectedRectNode = [selectedRectsGroup.childNodes item:0];
        selectedRectElement = (id)selectedRectNode;
    }
    
    NSString * tagName = NULL;
    DOMElement * movingDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
    if (movingDOMElement != NULL)
    {
        // update the element, projected to current mouse position
        
        tagName = movingDOMElement.tagName;
        
        if ([tagName isEqualToString:@"path"]  == YES)
        {
            [self.svgPathEditor editPath];
        }
        else if ([tagName isEqualToString:@"polyline"]  == YES)
        {
            [self.svgPolylineEditor editPolyline];
        }
        else if ([tagName isEqualToString:@"polygon"]  == YES)
        {
            [self.svgPolylineEditor editPolyline];
        }
        else if ([tagName isEqualToString:@"line"]  == YES)
        {
            [self.svgLineEditor editLine];
        }
        
        [self.svgXMLDOMSelectionManager.selectedElementsManager removeAllElements];
        [domSelectionControlsManager removeDOMSelectionRectsAndHandles];
        
        NSXMLElement * movingXMLElement = (self.svgXMLDOMSelectionManager).activeXMLElement;

        [self.svgXMLDOMSelectionManager.selectedElementsManager
                addElementDictionaryWithXMLElement:movingXMLElement domElement:movingDOMElement];
        
        [self syncSelectedElementsToXMLDocument];
        
        [macSVGDocumentWindowController reloadAttributesTableData];
    }
}
      
//==================================================================================
//	handleMouseMoveEvent:
//==================================================================================

-(void) handleMouseMoveEvent:(DOMEvent *)event
{
    // handle dragging events
    MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;

    DOMElement * targetElement = [self.svgXMLDOMSelectionManager activeDOMElement];
    
    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    self.previousMousePoint = self.currentMousePoint;
    CGFloat zoomFactor = svgWebView.zoomFactor;
    self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

    self.currentMousePoint = [self translatePoint:self.currentMousePoint targetElement:targetElement];

    [event preventDefault];
    [event stopPropagation];

    mouseMoveCount++;

    NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;
    
    NSString * idAttribute = [targetElement getAttribute:@"id"];
    #pragma unused(idAttribute)

    if (selectionHandleClicked == YES)
    {
        if (mouseMoveCount == 1)
        {
            [macSVGDocument pushUndoRedoDocumentChanges];
        }
        
        [self dragHandleForDOMElement:targetElement];
    }
    else
    {
        NSXMLElement * targetXMLElement = NULL;
        
        if (self.svgXMLDOMSelectionManager.activeXMLElement != NULL)
        {
            targetXMLElement = self.svgXMLDOMSelectionManager.activeXMLElement;
        }
        else
        {
            NSString * macsvgid = [targetElement getAttribute:@"macsvgid"];
            targetXMLElement = [macSVGDocument xmlElementForMacsvgid:macsvgid];
            self.svgXMLDOMSelectionManager.activeXMLElement = targetXMLElement;
        }

        switch (currentToolMode) 
        {
            case toolModeNone:
                break;
            case toolModeArrowCursor:
            {
                [self handleMouseMoveEventForSelection:event];
                break;
            }
            case toolModeCrosshairCursor:
            {
                [self handleMouseMoveEventForCrosshairCursor:event];
                break;
            }
            case toolModeRect:
            case toolModeCircle:
            case toolModeEllipse:
            case toolModeText:
            case toolModeImage:
            case toolModeLine:
            case toolModePolyline:
            case toolModePolygon:
            case toolModePath:
            {
                [self handleMouseMoveEventForDrawingTool:event];
                break;
            }
            default:
            break;
        }
    }
}



//==================================================================================
//	buildPolylinePointsArrayWithPointsString:
//==================================================================================

#define kSeparatorMode 0
#define kXValueMode 1
#define kYValueMode 1

- (NSMutableArray *)buildPolylinePointsArrayWithPointsString:(NSString *)aPointsString
{
    NSMutableArray * newPolylinePointsArray = [NSMutableArray array];

    NSCharacterSet * whitespaceSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    NSString * pointsString = [aPointsString stringByTrimmingCharactersInSet:whitespaceSet];
    pointsString = [pointsString stringByReplacingOccurrencesOfString:@"," withString:@" "];
    pointsString = [pointsString stringByReplacingOccurrencesOfString:@";" withString:@" "];
    
    while ([pointsString rangeOfString:@"  "].location != NSNotFound)
    {
        pointsString = [pointsString stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    
    NSCharacterSet * whitespaceCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    
    NSArray * valuesArray = [pointsString componentsSeparatedByCharactersInSet:whitespaceCharacterSet];
    
    NSInteger valuesArrayCount = valuesArray.count;
    
    if (valuesArrayCount %2 == 0)
    {
        for (NSInteger i = 0; i < valuesArrayCount; i += 2)
        {
            NSString * xString = valuesArray[i];
            NSString * yString = valuesArray[i + 1];
            
            NSMutableDictionary * polylinePointDictionary = [NSMutableDictionary dictionary];
            polylinePointDictionary[@"x"] = xString;
            polylinePointDictionary[@"y"] = yString;
            
            [newPolylinePointsArray addObject:polylinePointDictionary];
        }
    }
    
    return newPolylinePointsArray;
}


//==================================================================================
//	handleMouseHoverEvent:
//==================================================================================

-(void) handleMouseHoverEvent:(DOMEvent *)event
{
    // handle dragging events
    DOMElement * targetElement = [self.svgXMLDOMSelectionManager activeDOMElement];
    if (targetElement != NULL)
    {
        DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
        self.previousMousePoint = self.currentMousePoint;
        CGFloat zoomFactor = svgWebView.zoomFactor;
        self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

        self.currentMousePoint = [self translatePoint:self.currentMousePoint targetElement:targetElement];

        [event preventDefault];
        [event stopPropagation];

        NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;

        switch (currentToolMode) 
        {
            case toolModeNone:
            case toolModeArrowCursor:
            case toolModeCrosshairCursor:
            case toolModeRect:
            case toolModeCircle:
            case toolModeEllipse:
            case toolModeText:
            case toolModeImage:
            case toolModeLine:
            {
                break;
            }
            case toolModePolyline:
            case toolModePolygon:
            {
                [self.svgPolylineEditor handleMouseHoverEventForPolyline:event];
                break;
            }
            case toolModePath:
            {
                [self.svgPathEditor handleMouseHoverEventForPath:event];
                break;
            }
            default:
            break;
        }
    }
    else
    {
        NSLog(@"DOMMouseEventsController handleMouseHoverEvent - activeDOMElement is NULL");
    }
}

//==================================================================================
//	handleMouseIdleEvent:
//==================================================================================

-(void) handleMouseIdleEvent:(DOMEvent *)event
{
    // handle dragging events
    //NSString * eventType = event.type;

    DOMNode * targetNode = event.target;
    DOMElement * targetElement = (DOMElement *)targetNode;

    DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
    self.previousMousePoint = self.currentMousePoint;
    CGFloat zoomFactor = svgWebView.zoomFactor;
    self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));

    self.currentMousePoint = [self translatePoint:self.currentMousePoint targetElement:targetElement];

    [event preventDefault];
    [event stopPropagation];

    NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;

    switch (currentToolMode) 
    {
        case toolModeNone:
        case toolModeArrowCursor:
        case toolModeCrosshairCursor:
        case toolModeRect:
        case toolModeCircle:
        case toolModeEllipse:
        case toolModeText:
        case toolModeImage:
        case toolModeLine:
        case toolModePolyline:
        case toolModePolygon:
        case toolModePath:
        {
            break;
        }
        default:
        break;
    }
}

//==================================================================================
//	handleMouseMoveOrHoverEvent:
//==================================================================================

-(void) handleMouseMoveOrHoverEvent:(DOMEvent *)event
{
    if (self.mouseMode == MOUSE_DRAGGING)
    {
        [self handleMouseMoveEvent:event];
    }
    else if (self.mouseMode == MOUSE_HOVERING)
    {
        [self handleMouseHoverEvent:event];
    }
    else
    {
        [self handleMouseIdleEvent:event];
    }
}
        
//==================================================================================
//	handleMouseDoubleClickEvent:
//==================================================================================

-(void) handleMouseDoubleClickEvent:(DOMEvent *)event
{
    [self endPathDrawing];
    [self endPolylineDrawing];
    
    self.mouseMode = MOUSE_DISENGAGED;
    [event preventDefault];
    [event stopPropagation];

    self.clickPoint = self.currentMousePoint;
    self.clickTarget = NULL;
    self.svgXMLDOMSelectionManager.activeXMLElement = NULL;
}



//==================================================================================
//	handleMouseUpEvent:
//==================================================================================

-(void) handleMouseUpEvent:(DOMEvent *)event
{
    NSUInteger currentToolMode = macSVGDocumentWindowController.currentToolMode;

    switch (currentToolMode) 
    {
        case toolModeArrowCursor:
        {
            if (self.mouseMode == MOUSE_DRAGGING)
            {
                self.mouseMode = MOUSE_DISENGAGED;
            }

            DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
            CGFloat zoomFactor = svgWebView.zoomFactor;
            self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));
            self.previousMousePoint = self.currentMousePoint;

            [event preventDefault];
            [event stopPropagation];

            MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;
            NSXMLDocument * svgXmlDocument = macSVGDocument.svgXmlDocument;
            NSXMLElement * rootXMLElement = [svgXmlDocument rootElement];
            if (self.svgXMLDOMSelectionManager.activeXMLElement == rootXMLElement)
            {
                // clicked in an empty area within webview, deselect all
                XMLOutlineController * xmlOutlineController = macSVGDocumentWindowController.xmlOutlineController;
                NSOutlineView * xmlOutlineView = xmlOutlineController.xmlOutlineView;
                [(id)xmlOutlineView selectNone:self];
            }
            else
            {
                [self.svgXMLDOMSelectionManager selectXMLElementAndChildNodes:self.svgXMLDOMSelectionManager.activeXMLElement];
            }
            
            
            self.clickPoint = self.currentMousePoint;
            self.clickTarget = NULL;
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;
            break;
        }
        case toolModeCrosshairCursor:
        {
            if (self.mouseMode == MOUSE_DRAGGING)
            {
                self.mouseMode = MOUSE_DISENGAGED;
            }

            DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
            CGFloat zoomFactor = svgWebView.zoomFactor;
            self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));
            self.previousMousePoint = self.currentMousePoint;

            [event preventDefault];
            [event stopPropagation];

            self.clickPoint = self.currentMousePoint;
            self.clickTarget = NULL;
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;
            break;
        }
        case toolModePolyline:
        case toolModePolygon:
        {
            self.mouseMode = MOUSE_HOVERING;
            [event preventDefault];
            [event stopPropagation];
            
            break;
        }
        case toolModePath:
        {
            self.mouseMode = MOUSE_HOVERING;
            [event preventDefault];
            [event stopPropagation];

            //NSLog(@"handleMouseEvent - toolModePath mouseup");
            
            DOMElement * activeDOMElement = [self.svgXMLDOMSelectionManager activeDOMElement];
            if (activeDOMElement != NULL)
            {
                NSString * tagName = activeDOMElement.tagName;
                if ([tagName isEqualToString:@"path"] == YES)
                {
                    [self.svgPathEditor extendPath];
                }
            }

            break;
        }
        default:
        {
            if (self.mouseMode == MOUSE_DRAGGING)
            {
                self.mouseMode = MOUSE_DISENGAGED;
            }

            DOMMouseEvent * mouseEvent = (DOMMouseEvent *)event;
            CGFloat zoomFactor = svgWebView.zoomFactor;
            self.currentMousePoint = NSMakePoint(mouseEvent.pageX * (1.0f / zoomFactor), mouseEvent.pageY * (1.0f / zoomFactor));
            self.previousMousePoint = self.currentMousePoint;

            [event preventDefault];
            [event stopPropagation];

            MacSVGDocument * macSVGDocument = macSVGDocumentWindowController.document;
            NSXMLDocument * svgXmlDocument = macSVGDocument.svgXmlDocument;
            NSXMLElement * rootXMLElement = [svgXmlDocument rootElement];
            if (self.svgXMLDOMSelectionManager.activeXMLElement == rootXMLElement)
            {
                // clicked in an empty area within webview, deselect all
                XMLOutlineController * xmlOutlineController = macSVGDocumentWindowController.xmlOutlineController;
                NSOutlineView * xmlOutlineView = xmlOutlineController.xmlOutlineView;
                [(id)xmlOutlineView selectNone:self];
            }
            else
            {
                [self.svgXMLDOMSelectionManager selectXMLElementAndChildNodes:self.svgXMLDOMSelectionManager.activeXMLElement];
            }
            
            self.clickPoint = self.currentMousePoint;
            self.clickTarget = NULL;
            self.svgXMLDOMSelectionManager.activeXMLElement = NULL;
            
            BOOL resetToolMode = YES;
            
            if (macSVGDocumentWindowController.currentToolMode == toolModeText)
            {
                resetToolMode = NO;
            }

            if (macSVGDocumentWindowController.currentToolMode == toolModeImage)
            {
                resetToolMode = NO;
            }

            if (resetToolMode == YES)
            {
                [macSVGDocumentWindowController setToolMode:toolModeArrowCursor];
            }
            
            break;
        }
    }

    if (currentToolMode != toolModeCrosshairCursor)
    {
        [domSelectionControlsManager updateDOMSelectionRectsAndHandles];
    }
    
    selectionHandleClicked = NO;
    handle_orientation = NULL;
}





@end
