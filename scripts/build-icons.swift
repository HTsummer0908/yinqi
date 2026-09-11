import AppKit
import Foundation

/// 2026-09-11: Export the approved v2 geometry into transparent macOS icon sizes; keep the SVG layers as editable masters.
func drawIcon() {
    let background = NSBezierPath(roundedRect: NSRect(x:32,y:32,width:960,height:960), xRadius:214,yRadius:214)
    NSGradient(starting:NSColor(srgbRed:34/255,green:54/255,blue:79/255,alpha:1),ending:NSColor(srgbRed:13/255,green:23/255,blue:41/255,alpha:1))!.draw(in:background,angle:-45)
    let bars=NSBezierPath()
    for (i,top) in [464.0,292,408,344,492,376].enumerated() {
        let x=224.0+Double(i)*98, y=1024-top, bottom=334.0
        bars.move(to:NSPoint(x:x,y:bottom)); bars.line(to:NSPoint(x:x,y:y-12))
        bars.curve(to:NSPoint(x:x+12,y:y),controlPoint1:NSPoint(x:x,y:y),controlPoint2:NSPoint(x:x,y:y))
        bars.line(to:NSPoint(x:x+74,y:y))
        bars.curve(to:NSPoint(x:x+86,y:y-12),controlPoint1:NSPoint(x:x+86,y:y),controlPoint2:NSPoint(x:x+86,y:y))
        bars.line(to:NSPoint(x:x+86,y:bottom)); bars.close()
    }
    NSGraphicsContext.saveGraphicsState(); bars.addClip()
    let colors=[NSColor(srgbRed:66/255,green:123/255,blue:1,alpha:1),NSColor(srgbRed:53/255,green:188/255,blue:236/255,alpha:1),NSColor(srgbRed:105/255,green:228/255,blue:202/255,alpha:1)]
    NSGradient(colors:colors)!.draw(from:NSPoint(x:224,y:374),to:NSPoint(x:800,y:714),options:[.drawsBeforeStartingLocation,.drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
    let base=NSBezierPath(roundedRect:NSRect(x:208,y:288,width:608,height:24),xRadius:12,yRadius:12)
    NSGradient(colors:[NSColor(srgbRed:81/255,green:124/255,blue:174/255,alpha:1),NSColor(srgbRed:162/255,green:216/255,blue:235/255,alpha:1),NSColor(srgbRed:81/255,green:124/255,blue:174/255,alpha:1)])!.draw(in:base,angle:0)
}
/// 2026-09-11: Generate each iconset density directly from vector paths to avoid resizing a flattened preview.
func exportIcon(size:Int, path:String) throws {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSGraphicsContext.current!.cgContext.scaleBy(x:Double(size)/1024,y:Double(size)/1024)
    drawIcon(); NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
}
let folder="build/Yinqi.iconset"
try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    try exportIcon(size:size,path:"\(folder)/icon_\(size)x\(size).png")
    try exportIcon(size:size*2,path:"\(folder)/icon_\(size)x\(size)@2x.png")
}
