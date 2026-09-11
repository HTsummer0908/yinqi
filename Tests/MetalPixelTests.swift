import AppKit
import MetalKit

/// Inspect GPU output pixels rather than mistaking successful command submission for visible bars.
@main struct MetalPixelTests {
    /// An active synthetic frame must produce nonzero premultiplied alpha in the actual production shader.
    static func main() throws {
        _ = NSApplication.shared
        let renderer = try SpectrumRenderer(frame: CGRect(x:0,y:0,width:320,height:96))
        var limited = Settings(); limited.frameRate = 10
        renderer.update(SpectrumFrame(bands: [], rmsDB: -160, timestamp: 0, sequence: 0, opacity: 0), settings: limited, editing: false, hidden: true)
        assert(renderer.view.preferredFramesPerSecond == 10, "must apply user frame limit")
        var stereoSettings = Settings(); stereoSettings.channelMode = "stereo"
        renderer.update(SpectrumFrame(bands: [Float](repeating: 1, count: 64), rmsDB: -10, timestamp: 1, sequence: 1, channelMode: "merged"), settings: stereoSettings, editing: false, hidden: false)
        assert(renderer.view.isPaused, "old channel layout must pause until compatible data arrives")
        let device = renderer.view.device!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:320,height:96,mipmapped:false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
        let texture = device.makeTexture(descriptor:descriptor)!
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        renderer.update(SpectrumFrame(bands:[Float](repeating:0.8,count:64),rmsDB:-10,timestamp:1,sequence:1),settings:Settings(),editing:false,hidden:false)
        let command = device.makeCommandQueue()!.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor:pass)!
        renderer.encodeBars(using:encoder,size:CGSize(width:320,height:96))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        assert(command.status == .completed, "GPU failure: \(String(describing:command.error))")
        var bytes = [UInt8](repeating:0,count:320*96*4)
        texture.getBytes(&bytes,bytesPerRow:320*4,from:MTLRegionMake2D(0,0,320,96),mipmapLevel:0)
        let count = stride(from:3,to:bytes.count,by:4).filter {bytes[$0]>0}.count
        print("nontransparent pixels: \(count)")
        assert(count>1000,"Active spectrum rendered transparent pixels")
        // 2026-09-11: The actual stereo shader must isolate left pixels and leave its divider transparent.
        var stereo = Settings(); stereo.channelMode = "stereo"; stereo.channelGap = 12
        for right in [false, true] {
            let bars = [Float](repeating: right ? 0 : 0.8, count:32) + [Float](repeating: right ? 0.8 : 0, count:32)
            renderer.update(SpectrumFrame(bands:bars,rmsDB:-10,timestamp:2,sequence:2),settings:stereo,editing:false,hidden:false)
            let buffer = device.makeCommandQueue()!.makeCommandBuffer()!
            let draw = buffer.makeRenderCommandEncoder(descriptor:pass)!
            renderer.encodeBars(using:draw,size:CGSize(width:320,height:96))
            draw.endEncoding(); buffer.commit(); buffer.waitUntilCompleted()
            texture.getBytes(&bytes,bytesPerRow:320*4,from:MTLRegionMake2D(0,0,320,96),mipmapLevel:0)
            var left = 0, rightPixels = 0, center = 0
            for y in 0..<96 { for x in 0..<320 where bytes[(y*320+x)*4+3] > 0 {
                if x < 154 { left += 1 } else if x >= 166 { rightPixels += 1 } else { center += 1 }
            }}
            assert(center == 0)
            assert(right ? (rightPixels > 1000 && left == 0) : (left > 1000 && rightPixels == 0))
        }
        var endpoints = [Float]()
        for rate in [10,30,60,144,240] {
            var animation = SpectrumAnimation()
            _ = animation.advance(target: [1], time: 0, release: 0.18)
            for i in 1...rate { _ = animation.advance(target: [1], time: Double(i)/Double(rate), release: 0.18) }
            for i in 1...rate { _ = animation.advance(target: [0], time: 1 + Double(i)/Double(rate), release: 0.18) }
            endpoints.append(animation.bands[0])
        }
        assert(endpoints.max()! - endpoints.min()! < 0.00001, "motion must depend on elapsed time")
        print("PASS: actual shader pixels, stereo isolation/divider, 10 FPS setting, time-based animation")
    }
}
