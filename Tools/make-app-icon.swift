// Writes SapientChat's app icon as an Icon Composer bundle (AppIcon.icon):
// icon.json plus two SVG layers. iOS renders it with Liquid Glass and
// derives the dark, tinted and clear looks from it. Open the result in
// Icon Composer (inside Xcode) to fine-tune glass, shadow and translucency.
//
//   swift Tools/make-app-icon.swift SapientChat/AppIcon.icon
//
// Concept: a speech bubble holding three stacked layers — chatting with a
// model that runs on the device — in the app's accent violet. Plain
// shapes, no SF Symbols (their licence doesn't allow them in app icons).
import Foundation

let canvas = 1024

/// The speech bubble: a rounded rectangle and a tail sweeping down-left.
let bubbleSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">
  <g fill="#FFFFFF">
    <rect x="196" y="220" width="632" height="500" rx="160" ry="160"/>
    <path d="M290 620 L300 690 C306 760 290 800 250 830 C350 820 430 770 470 700 L470 620 Z"/>
  </g>
</svg>
"""

/// Three stacked layers: a filled top diamond and two chevrons.
let layersSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">
  <g fill="none" stroke="#000000" stroke-width="30" stroke-linecap="round" stroke-linejoin="round">
    <polygon points="512,310 672,390 512,470 352,390" fill="#000000"/>
    <polyline points="352,474 512,554 672,474"/>
    <polyline points="352,558 512,638 672,558"/>
  </g>
</svg>
"""

/// "display-p3:r,g,b,a" from 0–255 components.
func p3(_ r: Int, _ g: Int, _ b: Int) -> String {
    String(format: "display-p3:%.5f,%.5f,%.5f,1.00000", Double(r) / 255, Double(g) / 255, Double(b) / 255)
}

let iconJSON: [String: Any] = [
    // Background: violet → indigo; deep near-black violet in dark mode.
    "fill": ["linear-gradient": [p3(0x8F, 0x72, 0xFF), p3(0x45, 0x27, 0xC9)]],
    "fill-specializations": [
        ["appearance": "dark", "value": ["linear-gradient": [p3(0x1E, 0x17, 0x36), p3(0x0C, 0x09, 0x16)]]],
    ],
    // Groups are listed front to back.
    "groups": [
        [
            "name": "Layers",
            "layers": [[
                "name": "Layers",
                "image-name": "Layers.svg",
                "glass": false,
                "fill": ["linear-gradient": [p3(0x7A, 0x5C, 0xF0), p3(0x4A, 0x2C, 0xCB)]],
                "fill-specializations": [
                    ["appearance": "dark", "value": ["linear-gradient": [p3(0xFF, 0xFF, 0xFF), p3(0xE9, 0xE3, 0xFF)]]],
                ],
            ]],
            "shadow": ["kind": "neutral", "opacity": 0.3],
            "translucency": ["enabled": false, "value": 0.2],
        ],
        [
            "name": "Bubble",
            "layers": [[
                "name": "Bubble",
                "image-name": "Bubble.svg",
                "glass": true,
                "fill": "automatic",
                "fill-specializations": [
                    ["appearance": "dark", "value": ["linear-gradient": [p3(0x9B, 0x82, 0xFF), p3(0x5B, 0x3D, 0xDB)]]],
                ],
            ]],
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": true, "value": 0.25],
        ],
    ],
    "supported-platforms": ["squares": "shared"],
]

let bundle = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try bubbleSVG.write(to: assets.appendingPathComponent("Bubble.svg"), atomically: true, encoding: .utf8)
try layersSVG.write(to: assets.appendingPathComponent("Layers.svg"), atomically: true, encoding: .utf8)
let json = try JSONSerialization.data(withJSONObject: iconJSON, options: [.prettyPrinted, .sortedKeys])
try json.write(to: bundle.appendingPathComponent("icon.json"))
print("wrote \(bundle.path)")
