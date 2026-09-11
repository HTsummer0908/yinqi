import AppKit
import MetalKit

/// Pixel regressions exercise the production shader, including nonintegral widths and both orientations.
@main struct AppearanceTests {
    /// Render controlled bar heights and inspect coverage/color rather than relying on submission counts.
    static func main() throws {
        _ = NSApplication.shared
        // 2026-09-11: Cached coefficients must preserve attack/release values across rates and changing targets.
        for fps in [10, 30, 60, 120, 240] {
            var animation = SpectrumAnimation()
            var reference: [Float] = [0, 0]
            _ = animation.advance(target: reference, time: 0, release: 0.289)
            for tick in 1...fps {
                let target: [Float] = tick < fps/2 ? [1, 0.4] : [0.2, 0.9]
                for i in target.indices {
                    reference[i] = smooth(reference[i], target: target[i], dt: 1/Double(fps), tau: target[i] > reference[i] ? 0.03 : 0.289)
                }
                let actual = animation.advance(target: target, time: Double(tick)/Double(fps), release: 0.289)
                assert(zip(actual, reference).allSatisfy { abs($0-$1) < 0.00001 })
            }
        }
        // 2026-09-11: Equal elapsed time must produce equal peak decay, independent of refresh rate.
        for fps in [10,30,60,144,240] {
            var peak = PeakAnimation()
            _ = peak.advance(bars:[1,0.2],time:0,speed:0.3)
            for tick in 1...fps { _ = peak.advance(bars:[0.1,0.2],time:Double(tick)/Double(fps),speed:0.3) }
            assert(abs(peak.values[0]-0.7)<0.0001 && peak.values[1] == 0.2)
            assert(peak.advance(bars:[0.9,0.2],time:1.1,speed:0.3)[0] == 0.9)
            assert(peak.advance(bars:[0.4],time:2,speed:0.3) == [0.4])
        }
        // 2026-09-11: A red peak must appear beyond a blue half-height bar in every growth direction.
        for direction in ["up","down","left","right"] {
            for style in ["line","brick","rounded"] {
                var cap = Settings(); cap.barCount=16; cap.barOpacity=1; cap.primaryColor=[0,0,1]
                cap.peakEnabled=true; cap.peakCustomColor=true; cap.peakColor=[1,0,0]
                cap.peakStyle=style; cap.peakThickness=4; cap.growthDirection=direction
                let vertical = direction == "left" || direction == "right"
                let w=vertical ? 96:320, h=vertical ? 320:96
                let bytes=try render(cap,bands:[Float](repeating:0.5,count:16),width:w,height:h)
                assert(stride(from:0,to:bytes.count,by:4).contains { bytes[$0+2]>150 && bytes[$0]<80 }, "missing red cap: \(direction) \(style)")
                cap.peakEnabled=false
                let off=try render(cap,bands:[Float](repeating:0.5,count:16),width:w,height:h)
                assert(!stride(from:0,to:off.count,by:4).contains { off[$0+2]>150 }, "disabled cap rendered")
            }
        }
        var settings = Settings(); settings.gap = 0; settings.cornerRadius = 0; settings.barOpacity = 1
        for mode in ["merged", "stereo"] {
            settings.channelMode = mode
            for count in [16,64,128] {
                settings.barCount = count
                for width in [319,320,641] {
                    let bytes = try render(settings, bands: [Float](repeating: 0.8, count:count), width:width)
                    for x in 1..<(width-1) { assert(bytes[(70*width+x)*4+3] == 255, "zero gap has a seam at x=\(x), width=\(width)") }
                }
            }
        }
        settings.barCount = 16; settings.channelMode = "stereo"
        settings.channelGap = 40
        let divided = try render(settings, bands:[Float](repeating:0.8,count:16), width:240)
        assert(divided[(70*240+105)*4+3] == 0 && divided[(70*240+135)*4+3] == 0, "40 pt interval must not silently become 24 pt")
        settings.channelGap = 0
        var tones = [Float](repeating: 0, count:16); tones[0]=1; tones[8]=1
        for (order, active) in [("ascending", [10,170]), ("lowOutside", [10,310]), ("lowInside", [150,170])] {
            settings.stereoOrder = order
            let pixels = try render(settings, bands:tones)
            for x in [10,150,170,310] { assert((pixels[(50*320+x)*4+3] > 0) == active.contains(x), "channel order \(order) at \(x)") }
        }
        settings.channelMode = "merged"; settings.style = "gradient"
        settings.gradientColors = [[1,0,0],[0,0,1]]
        for direction in ["horizontal", "vertical"] {
            settings.gradientDirection = direction
            let pixels = try render(settings, bands:[Float](repeating:1,count:16))
            let redPoint = direction == "horizontal" ? (20,48) : (160,80)
            let bluePoint = direction == "horizontal" ? (300,48) : (160,16)
            let r = (redPoint.1*320+redPoint.0)*4, b = (bluePoint.1*320+bluePoint.0)*4
            assert(pixels[r+2] > pixels[r] && pixels[b] > pixels[b+2], "gradient direction")
        }
        settings.style = "solid"; settings.gap=4; settings.cornerRadius=6
        for rounded in [false,true] {
            settings.roundBase=rounded
            let pixels = try render(settings, bands:[Float](repeating:0.8,count:16))
            assert(rounded ? pixels[(95*320+1)*4+3] < 100 : pixels[(95*320+1)*4+3] == 255, "base corner toggle")
        }
        settings.cornerRadius=0; settings.gap=0; settings.roundBase=false
        settings.growthDirection="right"
        var vertical = try render(settings, bands:tones, width:96,height:320)
        assert(vertical[(10*96+20)*4+3] == 255 && vertical[(50*96+20)*4+3] == 0)
        settings.growthDirection="left"
        vertical = try render(settings, bands:tones.map { $0*0.5 }, width:96,height:320)
        assert(vertical[(10*96+80)*4+3] == 255 && vertical[(10*96+20)*4+3] == 0)
        print("PASS: zero seams at 3 widths/3 counts, stereo ordering, two gradients, base corners, side growth")
    }

    /// The returned BGRA pixels use Metal texture row order (top to bottom).
    static func render(_ settings: Settings, bands: [Float], width: Int = 320, height: Int = 96) throws -> [UInt8] {
        let renderer = try SpectrumRenderer(frame: CGRect(x:0,y:0,width:width,height:height))
        let device = renderer.view.device!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:width,height:height,mipmapped:false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget]
        let texture = device.makeTexture(descriptor:descriptor)!
        let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        renderer.update(SpectrumFrame(bands:bands,rmsDB:-10,timestamp:1,sequence:1),settings:settings,editing:false,hidden:false)
        let command = device.makeCommandQueue()!.makeCommandBuffer()!
        let encoder = command.makeRenderCommandEncoder(descriptor:pass)!
        renderer.encodeBars(using:encoder,size:CGSize(width:width,height:height))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        assert(command.status == .completed)
        var bytes = [UInt8](repeating:0,count:width*height*4)
        texture.getBytes(&bytes,bytesPerRow:width*4,from:MTLRegionMake2D(0,0,width,height),mipmapLevel:0)
        return bytes
    }
}
