import Foundation
import SwiftUI

/// Decoded METAR from aviationweather.gov (JSON format).
/// The upstream feed mixes types (visibility can be `"10+"` or `6.0`,
/// wind direction can be `"VRB"` or `240`), so decoding is deliberately
/// lenient: every field is optional and mixed types decode via `Flexible`.
struct Metar: Codable, Identifiable {
    var icaoId: String?
    var rawOb: String?
    var name: String?
    var reportTime: String?
    var temp: Double?               // °C
    var dewp: Double?
    var wdir: FlexibleValue?        // degrees or "VRB"
    var wspd: Double?               // knots
    var wgst: Double?               // gust, knots
    var visib: FlexibleValue?       // statute miles or "10+"
    var altim: Double?              // hPa
    var wxString: String?           // "-RA BR"
    var fltCat: String?             // VFR / MVFR / IFR / LIFR
    var clouds: [CloudLayer]?

    var id: String { (icaoId ?? "?") + (reportTime ?? "") }

    struct CloudLayer: Codable {
        var cover: String?          // FEW/SCT/BKN/OVC/CLR
        var base: Double?           // feet AGL
    }

    // MARK: Presentation helpers

    var tempF: Int? { temp.map { Int(($0 * 9 / 5 + 32).rounded()) } }
    var tempC: Int? { temp.map { Int($0.rounded()) } }

    var windDescription: String {
        guard let spd = wspd, spd > 0 else { return "Calm" }
        let dir: String
        if let w = wdir {
            switch w {
            case .string: dir = "Variable"
            case .number(let d): dir = Self.compassPoint(degrees: d)
            }
        } else { dir = "" }
        var s = "\(dir) \(Int(spd)) kt".trimmingCharacters(in: .whitespaces)
        if let g = wgst, g > spd { s += ", gusting \(Int(g))" }
        return s
    }

    var visibilityDescription: String {
        guard let v = visib else { return "—" }
        switch v {
        case .string(let s): return s.hasSuffix("+") ? "\(s.dropLast())+ mi" : "\(s) mi"
        case .number(let n): return n >= 10 ? "10+ mi" : String(format: "%g mi", n)
        }
    }

    /// Lowest broken/overcast layer = ceiling.
    var ceilingDescription: String {
        let ceilings = (clouds ?? []).filter { ["BKN", "OVC"].contains(($0.cover ?? "").uppercased()) }
        if let lowest = ceilings.compactMap(\.base).min() {
            return "\(Int(lowest)) ft"
        }
        if let first = clouds?.first?.cover?.uppercased(), ["CLR", "SKC", "CAVOK"].contains(first) {
            return "Clear"
        }
        return "None"
    }

    var flightCategoryColor: Color {
        switch (fltCat ?? "").uppercased() {
        case "VFR": return Theme.green
        case "MVFR": return Theme.accent
        case "IFR": return Theme.red
        case "LIFR": return Theme.purple
        default: return Theme.textSecondary
        }
    }

    var conditionsSummary: String? {
        guard let wx = wxString, !wx.isEmpty else { return nil }
        let map: [String: String] = [
            "RA": "rain", "SN": "snow", "TS": "thunderstorms", "FG": "fog",
            "BR": "mist", "HZ": "haze", "DZ": "drizzle", "GR": "hail",
            "FZ": "freezing", "SH": "showers", "PL": "ice pellets", "SQ": "squalls",
        ]
        var parts: [String] = []
        for token in wx.split(separator: " ") {
            var t = String(token)
            var prefix = ""
            if t.hasPrefix("-") { prefix = "light "; t.removeFirst() }
            if t.hasPrefix("+") { prefix = "heavy "; t.removeFirst() }
            var words: [String] = []
            var idx = t.startIndex
            while idx < t.endIndex, let next = t.index(idx, offsetBy: 2, limitedBy: t.endIndex) {
                let code = String(t[idx..<next])
                if let w = map[code] { words.append(w) }
                idx = next
            }
            if !words.isEmpty { parts.append(prefix + words.joined(separator: " ")) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ").capitalized
    }

    static func compassPoint(degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let idx = Int((degrees / 22.5).rounded()) % 16
        return points[(idx + 16) % 16]
    }
}

/// Decodes JSON values that may be either a number or a string.
enum FlexibleValue: Codable, Hashable {
    case string(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self = .number(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.typeMismatch(
                FlexibleValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Not a number or string"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d): try container.encode(d)
        }
    }
}
