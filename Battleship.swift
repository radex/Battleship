import Cocoa

/// Protocol for region types

protocol RegionType {
    /// Tells you if `point` is inside the region
    func match(point: CGPoint) -> Bool
    
    /// Renders the region with Core Graphics
    func draw(bounds: CGRect)
}

extension RegionType {
    // Renders the region using pixel sampling
    // Swift can't handle dynamic dispatch with protocol default implementations
    // so instances have to at least override draw and call sample
    func sample(bounds: CGRect) {
        NSColor.blackColor().set()
        
        for x in Int(bounds.origin.x)..<Int(bounds.origin.x + bounds.size.width) {
            for y in Int(bounds.origin.y)..<Int(bounds.origin.y + bounds.size.height) {
                if match(CGPoint(x: x, y: y)) {
                    NSRectFill(NSRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }
}

/// Generic region that can take whatever matcher function you give it

struct Region: RegionType {
    let matcher: CGPoint -> Bool
    
    func match(point: CGPoint) -> Bool {
        return matcher(point)
    }
    
    func draw(bounds: CGRect) {
        sample(bounds)
    }
}

// MARK: - Transformation regions

/// Region representing an offset transformation of another region

struct OffsetRegion: RegionType {
    let originalRegion: RegionType
    let dx: CGFloat
    let dy: CGFloat
    
    func match(point: CGPoint) -> Bool {
        return originalRegion.match(CGPoint(x: point.x - dx, y: point.y - dy))
    }
    
    func draw(bounds: CGRect) {
        let ctx = NSGraphicsContext.currentContext()!
        ctx.saveGraphicsState()
        
        let cg = unsafeBitCast(ctx.graphicsPort, CGContextRef.self)
        CGContextTranslateCTM(cg, dx, dy)
        
        let x = bounds.origin.x - dx
        let y = bounds.origin.y - dy
        let w = bounds.size.width
        let h = bounds.size.height
        let rect = CGRect(x: x, y: y, width: w, height: h)
        originalRegion.draw(rect)
        
        ctx.restoreGraphicsState()
    }
}

extension RegionType {
    func offset(x: CGFloat, _ y: CGFloat) -> OffsetRegion {
        return OffsetRegion(originalRegion: self, dx: x, dy: y)
    }
}

/// Region representing an union of two regions

struct UnionRegion: RegionType {
    let originalRegion: RegionType
    let otherRegion: RegionType
    
    func match(point: CGPoint) -> Bool {
        return originalRegion.match(point) || otherRegion.match(point)
    }
    
    func draw(bounds: CGRect) {
        NSColor.blackColor().set()
        
        originalRegion.draw(bounds)
        otherRegion.draw(bounds)
    }
}

extension RegionType {
    func plus(other: RegionType) -> UnionRegion {
        return UnionRegion(originalRegion: self, otherRegion: other)
    }
}

/// Region representing an intersection of two regions

struct IntersectionRegion: RegionType {
    let originalRegion: RegionType
    let otherRegion: RegionType
    
    func match(point: CGPoint) -> Bool {
        return originalRegion.match(point) && otherRegion.match(point)
    }
    
    func draw(bounds: CGRect) {
        let ctx = NSGraphicsContext.currentContext()!
        ctx.saveGraphicsState()
        
        let cg = unsafeBitCast(ctx.graphicsPort, CGContextRef.self)
        
        NSColor.blackColor().set()
        
        let image = NSImage(size: bounds.size, flipped: false) { _ in
            self.otherRegion.draw(bounds)
            return true
        }
        
        var imageRect = CGRectMake(0, 0, image.size.width, image.size.height)
        let imageRef = image.CGImageForProposedRect(&imageRect, context: nil, hints: nil)?.takeUnretainedValue()
        
        CGContextClipToMask(cg, bounds, imageRef)
        
        originalRegion.draw(bounds)
        
        ctx.restoreGraphicsState()
    }
}

extension RegionType {
    func intersection(other: RegionType) -> IntersectionRegion {
        return IntersectionRegion(originalRegion: self, otherRegion: other)
    }
}

/// Region representing a difference between two regions

struct DifferenceRegion: RegionType {
    let originalRegion: RegionType
    let otherRegion: RegionType
    
    func match(point: CGPoint) -> Bool {
        return originalRegion.match(point) && !otherRegion.match(point)
    }
    
    func draw(bounds: CGRect) {
        // there's probably a more reasonable way to do it but i'm a n00b at Core Graphics
        let ctx = NSGraphicsContext.currentContext()!
        ctx.saveGraphicsState()
        
        let cg = unsafeBitCast(ctx.graphicsPort, CGContextRef.self)
        
        NSColor.blackColor().set()
        
        let image = NSImage(size: bounds.size, flipped: false) { _ in
            self.otherRegion.draw(bounds)
            return true
        }
        
        let mask = NSImage(size: bounds.size, flipped: false) { imageBounds in
            NSRectFill(imageBounds)
            image.drawInRect(imageBounds, fromRect: .zeroRect, operation: .CompositeDestinationOut, fraction: 1.0)
            return true
        }
        
        var maskRect = CGRectMake(0, 0, mask.size.width, mask.size.height)
        let maskRef = mask.CGImageForProposedRect(&maskRect, context: nil, hints: nil)?.takeUnretainedValue()
        
        CGContextClipToMask(cg, bounds, maskRef)
        
        originalRegion.draw(bounds)
        
        ctx.restoreGraphicsState()
    }
}

extension RegionType {
    func minus(other: RegionType) -> DifferenceRegion {
        return DifferenceRegion(originalRegion: self, otherRegion: other)
    }
}

/// Region representing a circle

struct Circle: RegionType {
    let radius: CGFloat
    
    init(_ radius: CGFloat) {
        self.radius = radius
    }
    
    func match(point: CGPoint) -> Bool {
        return sqrt(point.x * point.x + point.y * point.y) <= radius
    }
    
    func draw(bounds: CGRect) {
        NSColor.blackColor().set()
        
        NSBezierPath(ovalInRect: NSRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).fill()
    }
}

// MARK: -

/// View that can render regions

class VisualizerView: NSView {
    var region: RegionType? = nil {
        didSet {
            needsDisplay = true
        }
    }
    
    var sample = false {
        didSet {
            needsDisplay = true
        }
    }
    
    override func drawRect(dirtyRect: NSRect) {
        NSColor.whiteColor().set()
        NSRectFill(bounds)
        
        if sample {
            region?.sample(bounds)
        } else {
            region?.draw(bounds)
        }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!
    lazy var visualizer: VisualizerView = { self.window.contentView as! VisualizerView }()

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        let circle1 = Circle(100).offset(200, 150)
        let circle2 = Circle(80).offset(100, 200)
        let enclosing = Circle(120).offset(160, 170)
        let circle4 = Circle(50).offset(200, 150)
        visualizer.region = circle1.plus(circle2).intersection(enclosing).minus(circle4)
    }
    
    /// Switches rendering mode between pixel sampling and smart drawing
    
    @IBAction func changeMode(sender: NSSegmentedControl) {
        visualizer.sample = (sender.selectedSegment == 0)
    }
}

