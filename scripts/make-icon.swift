import AppKit
let destination = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 64,y: 64,width: 896,height: 896), xRadius: 200,yRadius: 200)
NSGradient(starting: NSColor(calibratedRed: 0.12,green: 0.23,blue: 0.36,alpha: 1), ending: NSColor(calibratedRed: 0.04,green: 0.09,blue: 0.16,alpha: 1))!.draw(in: background, angle: -90)
for (index, point) in [NSPoint(x: 220,y: 542),NSPoint(x: 542,y: 542),NSPoint(x: 220,y: 220),NSPoint(x: 542,y: 220)].enumerated() {
    let colors: [NSColor] = [.init(calibratedRed: 0.34,green: 0.83,blue: 0.74,alpha: 1), .init(calibratedRed: 0.9,green: 0.73,blue: 0.36,alpha: 1), .init(calibratedRed: 0.54,green: 0.69,blue: 0.88,alpha: 1), .init(calibratedRed: 0.86,green: 0.91,blue: 0.95,alpha: 1)]
    colors[index].setFill(); NSBezierPath(roundedRect: NSRect(origin: point,size: NSSize(width: 262,height: 262)),xRadius: 64,yRadius: 64).fill()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
