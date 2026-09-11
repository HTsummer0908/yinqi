import AppKit
import QuartzCore

/// 2026-09-11: Validate layer geometry, actual composited pixels, style changes and pause/resume independently of Metal.
@main struct LayerRendererTests {
    /// Read RGBA pixels from the same layer tree used in the running app.
    static func pixels(_ renderer: LayerSpectrumRenderer, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:width*height*4)
        bytes.withUnsafeMutableBytes { pointer in
            let context = CGContext(data:pointer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            // Match the bottom-origin coordinates used by spectrum geometry in the byte buffer.
            context.translateBy(x:0,y:CGFloat(height));context.scaleBy(x:1,y:-1)
            renderer.surfaceView.layer!.render(in:context)
        }
        return bytes
    }
    /// Cover four directions, zero gaps, gradient endpoints, LED gaps and hidden/stale-frame behavior.
    static func main() {
        _ = NSApplication.shared
        var s = Settings();s.barCount=16;s.gap=0;s.cornerRadius=0;s.barOpacity=1;s.primaryColor=[1,0,0]
        let renderer=LayerSpectrumRenderer()
        renderer.surfaceView.frame=NSRect(x:0,y:0,width:320,height:96)
        let frame=SpectrumFrame(bands:Array(repeating:0.5,count:16),rmsDB:-10,timestamp:0,sequence:1,opacity:1)
        for direction in ["up","down","left","right"] {
            s.growthDirection=direction
            renderer.update(frame,settings:s,editing:false,hidden:false)
            let bytes=pixels(renderer,width:320,height:96)
            let alpha=stride(from:3,to:bytes.count,by:4).filter {bytes[$0]>240}.count
            assert(alpha > 14500 && alpha < 16000,"incorrect half fill: \(direction) \(alpha)")
            let points=direction == "up" ? [(1,10),(319,10)] : direction == "down" ? [(1,80),(319,80)] : direction == "right" ? [(10,1),(10,95)] : [(300,1),(300,95)]
            for (x,y) in points { assert(bytes[(y*320+x)*4+3]>240) }
        }
        s.growthDirection="up";s.style="gradient";s.gradientColors=[[1,0,0],[0,0,1]]
        renderer.update(frame,settings:s,editing:false,hidden:false)
        var bytes=pixels(renderer,width:320,height:96)
        assert(bytes[(10*320+2)*4]>bytes[(10*320+2)*4+2])
        assert(bytes[(10*320+317)*4+2]>bytes[(10*320+317)*4])
        s.gradientDirection="vertical"
        renderer.update(frame,settings:s,editing:false,hidden:false)
        bytes=pixels(renderer,width:320,height:96)
        assert(bytes[(2*320+10)*4]>bytes[(40*320+10)*4])
        // 2026-09-11: Verify channel-local reversal and optional baseline rounding geometrically.
        var geometrySettings = s; geometrySettings.channelMode="stereo";geometrySettings.stereoOrder="lowInside"
        let values = (0..<16).map { Float($0+1)/16 }
        var paths=LayerSpectrumRenderer.paths(values:values,markers:[],settings:geometrySettings,size:CGSize(width:320,height:96))
        assert(paths.0.contains(CGPoint(x:10,y:40)))
        assert(!paths.0.contains(CGPoint(x:150,y:10)))
        geometrySettings.channelMode="merged";geometrySettings.cornerRadius=8
        paths=LayerSpectrumRenderer.paths(values:Array(repeating:0.5,count:16),markers:[],settings:geometrySettings,size:CGSize(width:320,height:96))
        assert(paths.0.contains(CGPoint(x:0.2,y:0.2)))
        geometrySettings.roundBase=true
        paths=LayerSpectrumRenderer.paths(values:Array(repeating:0.5,count:16),markers:[],settings:geometrySettings,size:CGSize(width:320,height:96))
        assert(!paths.0.contains(CGPoint(x:0.2,y:0.2)))
        s.style="led";renderer.update(frame,settings:s,editing:false,hidden:false)
        bytes=pixels(renderer,width:320,height:96)
        assert(bytes[(6*320+10)*4+3]<100 && bytes[(9*320+10)*4+3]>240)
        s.style="solid";s.peakEnabled=true;s.peakCustomColor=true;s.peakColor=[0,1,0];s.peakThickness=3
        renderer.update(frame,settings:s,editing:false,hidden:false)
        bytes=pixels(renderer,width:320,height:96)
        assert(bytes[(49*320+10)*4+1]>200)
        renderer.update(frame,settings:s,editing:false,hidden:true)
        assert(renderer.isPaused)
        assert(pixels(renderer,width:320,height:96).allSatisfy {$0==0})
        renderer.update(frame,settings:s,editing:false,hidden:false)
        assert(!renderer.isPaused)
        renderer.update(SpectrumFrame(bands:[],rmsDB:-160,timestamp:1,sequence:2,opacity:0),settings:s,editing:false,hidden:false)
        assert(renderer.isPaused)
        print("PASS: layer pixels, four directions, zero gaps, gradient, LED, peaks, hide and resume")
    }
}
