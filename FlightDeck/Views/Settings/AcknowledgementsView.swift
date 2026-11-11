import SwiftUI

/// Data sources, the MIT notice for the bundled airport list, and build notes.
struct AcknowledgementsView: View {
    private static let mitLicense = """
    The MIT License (MIT)

    Copyright (c) 2014 mwgg

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """

    var body: some View {
        List {
            Section("Data sources") {
                source("FAA National Airspace System Status", "nasstatus.faa.gov")
                source("NOAA Aviation Weather Center", "aviationweather.gov")
                source("adsb.lol community ADS-B network", "adsb.lol")
                source("adsbdb.com (callsign routes)", "adsbdb.com")
                source("AeroDataBox (optional, with your key)", "via RapidAPI")
                source("Apple Maps", "MapKit")
            }

            Section("Airport data") {
                Text("World airport list from mwgg/Airports, MIT License")
                    .scaledFont(14, weight: .semibold)
                Text(Self.mitLicense)
                    .scaledFont(11, weight: .regular, design: .monospaced)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
            }

            Section("Built with") {
                Text("SwiftUI, MapKit, SF Symbols. No third-party code.")
                    .scaledFont(14, weight: .medium)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func source(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .scaledFont(14, weight: .semibold)
            Text(detail)
                .scaledFont(12, weight: .medium)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}
