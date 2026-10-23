//
//  ButtonChips.swift
//  ForeverAlonePoker
//
//  Created by Alberto Almeida on 22/10/26.
//

import SwiftUI

struct ButtonChips: View {
    let systemImage: String
        let count: Int
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                        Image(systemName: systemImage)
                    }
                    // Badge goes on the button so the toolbar's glass/background
                    // isn't affected by it.
                    .overlay(alignment: .topTrailing) {
                        if count > 0 {
                            CounterBadge(count: count)
                                .fixedSize()
                                .offset(x: 10, y: -8)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityLabel(Text("\(systemImage), \(count) new"))
        }
}

struct CounterBadge: View {
    let count: Int


        var body: some View {
            Text(count.formatted())
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red, in: Capsule())
        }
}

#Preview("Normal") {
    ButtonChips(systemImage: "xmark", count: 33000) {
            print("tapped")
        }
        .padding(30)
}

#Preview("Toolbar") {
    NavigationStack {
            Text("Content")
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        ButtonChips(systemImage: "bell", count: 33333) { }
                    }
                }
        }
}
