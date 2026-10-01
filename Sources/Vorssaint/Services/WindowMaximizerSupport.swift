// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum WindowMaximizerSupport {
    /// The green-button override shares Window Layout's screen-edge gap and
    /// its oversized-gap clamp, even when Window Layout itself is unavailable.
    static func maximizeTarget(visibleFrame: CGRect, screenGap: Int) -> CGRect {
        WindowLayoutGeometry.screenGapFrame(visibleFrame, screenGap: CGFloat(screenGap))
    }

    /// An app on the exception list keeps the green button's own behavior, so
    /// a game, an emulator or a player can still enter macOS full screen.
    static func excludes(bundleIdentifier: String?, excludedBundleIdentifiers: [String]) -> Bool {
        guard let bundleIdentifier else { return false }
        return Defaults.sanitizedBundleIdentifierList(excludedBundleIdentifiers).contains(bundleIdentifier)
    }

    /// Some apps keep a window edge out from under a Dock at the side of the
    /// screen and refuse a size that would put it there: a window dragged in
    /// from another display stays wider than the target, by a few points or by
    /// the whole Dock. Within the frame tolerance that still reads as done while
    /// the window sits under the Dock, so any excess counts, not only one past
    /// the tolerance; half a point absorbs rounding.
    static func overshoots(_ actual: CGSize, target: CGSize) -> Bool {
        actual.width > target.width + 0.5 || actual.height > target.height + 0.5
    }

    /// Taking the target size a tolerance up and to the left keeps the far
    /// edges clear of the Dock, so those apps accept it in full; the move back
    /// onto the target is not limited the same way and lands where native zoom
    /// does. Growing into the target instead stops a point short.
    static func approachOrigin(for target: CGPoint, tolerance: CGFloat) -> CGPoint {
        CGPoint(x: target.x - tolerance, y: target.y - tolerance)
    }
}

/// Restore bookkeeping kept separate from Accessibility so target changes,
/// manual moves and late animation completions can be tested deterministically.
struct WindowMaximizerFrameState<Frame> {
    struct Attempt {
        fileprivate enum Kind { case maximize, restore }
        fileprivate let id = UUID()
        fileprivate let kind: Kind
        fileprivate let previousOriginal: Frame?
        fileprivate let previousMaximized: Frame?
    }

    private(set) var original: Frame?
    private(set) var maximized: Frame?
    private var activeAttemptID: UUID?

    mutating func beginMaximize(current: Frame,
                                target: Frame,
                                isClose: (Frame, Frame) -> Bool) -> Attempt {
        let attempt = Attempt(kind: .maximize,
                              previousOriginal: original,
                              previousMaximized: maximized)
        let gapChangedWhileMaximized = maximized.map { isClose(current, $0) } ?? false
        if !gapChangedWhileMaximized { original = current }
        maximized = target
        activeAttemptID = attempt.id
        return attempt
    }

    mutating func beginRestore() -> Attempt {
        let attempt = Attempt(kind: .restore,
                              previousOriginal: original,
                              previousMaximized: maximized)
        activeAttemptID = attempt.id
        return attempt
    }

    /// Returns false for a completion superseded by another attempt or reset.
    @discardableResult
    mutating func complete(_ attempt: Attempt, success: Bool) -> Bool {
        guard activeAttemptID == attempt.id else { return false }
        activeAttemptID = nil
        if success {
            if case .restore = attempt.kind {
                original = nil
                maximized = nil
            }
        } else {
            original = attempt.previousOriginal
            maximized = attempt.previousMaximized
        }
        return true
    }

    mutating func reset() {
        activeAttemptID = nil
        original = nil
        maximized = nil
    }

    var isEmpty: Bool { original == nil && maximized == nil }
}
