//
//  GlobeAnimationView.swift
//  ForeverAlonePoker
//
//  Created by Alberto Almeida on 24/10/26.
//

import SwiftUI

/// An earth with a counter: the globe steps through four faces, swapping
/// each with the Replace symbol transition, while an arc travels around its
/// circumference. The counter ticks once per face.
struct GlobeAnimationView: View {
    private let phases = [
        "globe.americas",
        "globe.europe.africa",
        "globe.central.south.asia",
        "globe.asia.australia"
    ]

    @State private var phaseIndex = 0
    @State private var isSpinning = true
    /// Bumped each time the clapping hands replace the globe, so they bounce
    /// as they appear but not when the globe comes back.
    @State private var clapBounces = 0

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: isSpinning ? phases[phaseIndex] : "hands.clap.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 140, height: 140)
                .foregroundStyle(.blue)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, options: .nonRepeating, value: clapBounces)
                .overlay {
                    OrbitingArc(isActive: isSpinning)
                }

            Button(isSpinning ? "Pause" : "Spin") {
                isSpinning.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onChange(of: isSpinning) { _, spinning in
            if !spinning { clapBounces += 1 }
        }
        // Replaces the Combine timer: restarts when spinning toggles and is
        // cancelled with the view.
         .task(id: isSpinning) {
            guard isSpinning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1000))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.4)) {
                    phaseIndex = (phaseIndex + 1) % phases.count
                }
            }
        }
    }
}

/// A bright arc that runs clockwise around the globe's outline for as long
/// as it is active, and fades away when paused. With Reduce Motion it stays
/// still as a faint ring.
private struct OrbitingArc: View {
    let isActive: Bool

    @State private var angle: Angle = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: 0, to: reduceMotion ? 1 : 0.28)
            .stroke(
                AngularGradient(
                    colors: [.cyan.opacity(0), .cyan],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(reduceMotion ? 360 : 100)
                ),
                style: StrokeStyle(lineWidth: 6, lineCap: .round)
            )
            .opacity(isActive ? (reduceMotion ? 0.4 : 1) : 0)
            .rotationEffect(angle)
            .padding(-4)
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .onChange(of: isActive, initial: true) { _, active in
                guard !reduceMotion else { return }
                if active {
                    angle = .zero
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        angle = .degrees(360)
                    }
                } else {
                    // A non-repeating change cancels the endless rotation.
                    withAnimation(.easeOut(duration: 0.3)) {
                        angle = .zero
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    GlobeAnimationView()
}
