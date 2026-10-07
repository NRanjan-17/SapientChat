// Writes SapientChat's app icon as an Icon Composer bundle (AppIcon.icon):
// icon.json plus the SAPIENT mark as an SVG layer. iOS renders it with
// Liquid Glass and derives the tinted and clear looks. Open the result in
// Icon Composer (inside Xcode) to fine-tune glass, shadow and translucency.
//
//   swift Tools/make-app-icon.swift SapientChat/AppIcon.icon
//
// The mark is SAPIENT's logo (three angled bars), traced as vector shapes
// from the official app icon at sapient.openhorizon.so. Colours follow the
// site: SAPIENT blue #0562EF, and near-black #0A0A0A in dark mode.
import Foundation

let canvas = 1024

let markSVG = """
<svg xmlns="http://www.w3.org/2000/svg" width="\(canvas)" height="\(canvas)" viewBox="0 0 \(canvas) \(canvas)">
  <g fill="#FFFFFF">
    <polygon points="360.3,202.9 447.5,202.9 733.9,671.3 650.4,671.3"/>
    <polygon points="259.8,502.5 805.9,455.1 805.9,531.0 218.1,578.4"/>
    <polygon points="337.5,745.2 694.0,326.2 720.6,405.8 366.0,828.7"/>
  </g>
</svg>
"""

/// "display-p3:r,g,b,a" from 0–255 components.
func p3(_ r: Int, _ g: Int, _ b: Int) -> String {
    String(format: "display-p3:%.5f,%.5f,%.5f,1.00000", Double(r) / 255, Double(g) / 255, Double(b) / 255)
}

let iconJSON: [String: Any] = [
    // SAPIENT blue, barely graded so the glass has depth; near-black in dark mode.
    "fill": ["linear-gradient": [p3(0x0E, 0x6B, 0xF6), p3(0x05, 0x58, 0xDB)]],
    "fill-specializations": [
        ["appearance": "dark", "value": ["linear-gradient": [p3(0x12, 0x12, 0x12), p3(0x0A, 0x0A, 0x0A)]]],
    ],
    "groups": [
        [
            "name": "Mark",
            "layers": [[
                "name": "SAPIENT mark",
                "image-name": "Mark.svg",
                "glass": true,
                "fill": "automatic",
                // Dark mode: the mark itself turns SAPIENT blue.
                "fill-specializations": [
                    ["appearance": "dark", "value": ["linear-gradient": [p3(0x2A, 0x7D, 0xFF), p3(0x05, 0x62, 0xEF)]]],
                ],
            ]],
            "shadow": ["kind": "neutral", "opacity": 0.5],
            "translucency": ["enabled": false, "value": 0.2],
        ],
    ],
    "supported-platforms": ["squares": "shared"],
]

let bundle = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.icon")
let assets = bundle.appendingPathComponent("Assets")
try? FileManager.default.removeItem(at: assets)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try markSVG.write(to: assets.appendingPathComponent("Mark.svg"), atomically: true, encoding: .utf8)
let json = try JSONSerialization.data(withJSONObject: iconJSON, options: [.prettyPrinted, .sortedKeys])
try json.write(to: bundle.appendingPathComponent("icon.json"))
print("wrote \(bundle.path)")
