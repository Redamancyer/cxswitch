import AppKit

let outputPath = CommandLine.arguments.dropFirst().first ?? "assets/AppIcon.png"
let canvasSize = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvasSize)

image.lockFocus()

let backgroundRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 210, yRadius: 210)
NSColor(calibratedRed: 0.76, green: 0.89, blue: 1.0, alpha: 1).setFill()
background.fill()

guard
    let symbol = NSImage(
        systemSymbolName: "person.2.circle",
        accessibilityDescription: "CXSwitch"
    )
else {
    fatalError("Unable to load person.2.circle SF Symbol")
}

let configuration = NSImage.SymbolConfiguration(pointSize: 610, weight: .regular)
    .applying(
        .init(
            paletteColors: [
                NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.62, alpha: 1)
            ]
        )
    )
let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
let symbolSize = configured.size
let symbolRect = NSRect(
    x: (canvasSize.width - symbolSize.width) / 2,
    y: (canvasSize.height - symbolSize.height) / 2,
    width: symbolSize.width,
    height: symbolSize.height
)
configured.draw(in: symbolRect)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to render app icon PNG")
}

try png.write(to: URL(filePath: outputPath), options: .atomic)
