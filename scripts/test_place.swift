import Foundation

func firstCoordMatch(_ pattern: String, in text: String) -> (Double, Double)? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          match.numberOfRanges >= 3,
          let r1 = Range(match.range(at: 1), in: text),
          let r2 = Range(match.range(at: 2), in: text),
          let lat = Double(text[r1]),
          let lon = Double(text[r2]) else { return nil }
    return (lat, lon)
}

func coordinates(in text: String) -> (Double, Double)? {
    let decoded = text.removingPercentEncoding ?? text
    let at = firstCoordMatch(#"@(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})"#, in: decoded)
    if let at { return at }
    let query = firstCoordMatch(#"[?&](?:ll|q|query)=(-?\d{1,2}\.\d{3,}),\s*(-?\d{1,3}\.\d{3,})"#, in: decoded)
    if let query { return query }
    return firstCoordMatch(#"!3d(-?\d{1,2}\.\d{3,})!4d(-?\d{1,3}\.\d{3,})"#, in: decoded)
}

func formattedMiles(_ miles: Double) -> String {
    if miles < 0.05 { return "nearby" }
    if miles < 10 { return String(format: "%.1f mi", miles) }
    return "\(Int(miles.rounded())) mi"
}

func line(locality: String?, miles: Double?) -> String? {
    let city = locality?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !city.isEmpty, let miles { return "\(city) · \(formattedMiles(miles))" }
    if !city.isEmpty { return city }
    if let miles { return formattedMiles(miles) }
    return nil
}

var failed = 0
func expect(_ condition: Bool, _ name: String) {
    if condition { print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") }
}

let maps = "https://www.google.com/maps/place/Le+Colonial/@26.4612,-80.0725,17z"
expect(abs((coordinates(in: maps)?.0 ?? 0) - 26.4612) < 0.0001, "Reads Google Maps @lat,lng")
expect(abs((coordinates(in: maps)?.1 ?? 0) + 80.0725) < 0.0001, "Reads Google Maps longitude")

let apple = "https://maps.apple.com/?ll=26.3586,-80.0831&q=Boca+Raton"
expect(abs((coordinates(in: apple)?.0 ?? 0) - 26.3586) < 0.0001, "Reads Apple Maps ll=")

let data = "https://www.google.com/maps/dir/?api=1&destination=!3d27.9475!4d-82.4584"
expect(abs((coordinates(in: data)?.0 ?? 0) - 27.9475) < 0.0001, "Reads Google !3d!4d")

expect(line(locality: "Dade City", miles: 18.2) == "Dade City · 18 mi", "City plus whole miles")
expect(line(locality: "Boca Raton", miles: nil) == "Boca Raton", "City without home base")
expect(line(locality: nil, miles: 0.4) == "0.4 mi", "Miles only")
expect(formattedMiles(0.02) == "nearby", "Very close is nearby")

if failed == 0 {
    print("All tests passed")
} else {
    print("\(failed) tests failed")
    exit(1)
}
