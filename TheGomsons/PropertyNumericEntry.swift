//
//  PropertyNumericEntry.swift
//  TheGomsons
//
//  Int/Double fields stored as 0 when unknown, shown empty while editing so users don’t fight a leading “0”.
//

import SwiftUI

/// Digits-only integer entry; `0` is stored but displayed as empty.
struct IntZeroAsEmptyField: View {
    var placeholder: String = "—"
    @Binding var value: Int
    /// Limits input length (e.g. 4 for year).
    var maxDigits: Int?

    @State private var text: String = ""
    @State private var lastSyncedValue: Int?

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .onAppear {
                lastSyncedValue = value
                text = displayString(for: value)
            }
            .onChange(of: value) { _, new in
                guard new != lastSyncedValue else { return }
                lastSyncedValue = new
                let t = displayString(for: new)
                if text != t { text = t }
            }
            .onChange(of: text) { _, new in
                applyIntDigits(new)
            }
    }

    private func displayString(for v: Int) -> String {
        v == 0 ? "" : String(v)
    }

    private func applyIntDigits(_ raw: String) {
        var digits = raw.filter(\.isNumber)
        if let maxDigits {
            digits = String(digits.prefix(maxDigits))
        }
        if digits.isEmpty {
            value = 0
            lastSyncedValue = 0
            if text != "" { text = "" }
            return
        }
        guard let n = Int(digits) else {
            value = 0
            lastSyncedValue = 0
            text = ""
            return
        }
        value = n
        lastSyncedValue = n
        let normalized = displayString(for: n)
        if text != normalized { text = normalized }
    }
}

/// Decimal entry for values like bathroom count; `0` stored, empty while editing.
struct DoubleZeroAsEmptyField: View {
    var placeholder: String = "—"
    @Binding var value: Double

    @State private var text: String = ""
    @State private var lastSyncedValue: Double?

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .onAppear {
                lastSyncedValue = value
                text = displayString(for: value)
            }
            .onChange(of: value) { _, new in
                if let last = lastSyncedValue, abs(last - new) < 1e-9 { return }
                lastSyncedValue = new
                let t = displayString(for: new)
                if text != t { text = t }
            }
            .onChange(of: text) { _, new in
                applyDecimalText(new)
            }
    }

    private func displayString(for v: Double) -> String {
        if abs(v) < 1e-12 { return "" }
        let frac = abs(v.truncatingRemainder(dividingBy: 1))
        if frac < 1e-9 || frac > 1 - 1e-9 {
            return String(Int(v.rounded(.towardZero)))
        }
        return String(format: "%g", v)
    }

    private func applyDecimalText(_ raw: String) {
        let t = raw.replacingOccurrences(of: ",", with: ".")
        var out = ""
        var sawDot = false
        for ch in t {
            if ch.isNumber {
                out.append(ch)
                continue
            }
            if ch == "." && !sawDot {
                sawDot = true
                out.append(".")
            }
        }
        if out.isEmpty || out == "." {
            value = 0
            lastSyncedValue = 0
            if text != "" { text = "" }
            return
        }
        guard let d = Double(out) else {
            value = 0
            lastSyncedValue = 0
            text = ""
            return
        }
        value = d
        lastSyncedValue = d
        let normalized = displayString(for: d)
        if text != normalized { text = normalized }
    }
}
