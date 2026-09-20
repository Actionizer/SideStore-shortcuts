//
//  Progessers.swift
//  AltStore
//
//  Created by Flaky le Flaker (Mineturtlee) on 20/9/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation

final class Progressss: NSObject, Sendable {

    // MARK: Public state

    @objc dynamic var totalUnitCount: Int64
    private var explicitCompletedUnitCount: Int64 = 0

    private(set) weak var parent: Progressss?
    private var pendingUnitCount: Int64 = 0 // set when THIS is added as a child

    @objc dynamic var isCancelled: Bool = false
    @objc dynamic var isFinished: Bool = false

    private var children: [(progress: Progressss, unitCount: Int64)] = []
    private var observations: [NSKeyValueObservation] = []

    // MARK: Init
    
    class func discreteProgress(totalUnitCount unitCount: Int64) -> Progressss {
        return Progressss(totalUnitCount: unitCount)
    }

    init(totalUnitCount: Int64 = 0) {
        self.totalUnitCount = totalUnitCount
        super.init()

        // Implicit-parent attach, mirrors Progress(totalUnitCount:) consuming becomeCurrent
        if let (implicitParent, pending) = CurrentProgressStack.pop() {
            implicitParent.addChild(self, withPendingUnitCount: pending)
        }
    }

    // MARK: Fraction / completed unit count

    @objc dynamic var completedUnitCount: Int64 {
        get {
            let childContribution = children.reduce(0.0) { sum, entry in
                sum + entry.progress.fractionCompleted * Double(entry.unitCount)
            }
            return explicitCompletedUnitCount + Int64(childContribution)
        }
        set {
            explicitCompletedUnitCount = newValue
            updateCompletedUnitCount()
        }
    }

    @objc dynamic var fractionCompleted: Double {
        if isCancelled || isFinished { return 1.0 }
        guard totalUnitCount > 0 else { return 0 }
        return min(1.0, Double(completedUnitCount) / Double(totalUnitCount))
    }

    // MARK: addChild

    func addChild(_ child: Progressss, withPendingUnitCount inUnitCount: Int64) {
        precondition(child.parent == nil, "Progressss already has a parent")

        child.parent = self
        child.pendingUnitCount = inUnitCount
        children.append((child, inUnitCount))

        let obs = child.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            self?.updateCompletedUnitCount()
        }
        observations.append(obs)

        updateCompletedUnitCount()
    }

    // MARK: Change propagation

    private func updateCompletedUnitCount() {
        willChangeValue(for: \.fractionCompleted)
        willChangeValue(for: \.completedUnitCount)

        if totalUnitCount > 0 && completedUnitCount >= totalUnitCount {
            isFinished = true
        }

        didChangeValue(for: \.completedUnitCount)
        didChangeValue(for: \.fractionCompleted)

        parent?.updateCompletedUnitCount()
    }

    // MARK: Cancellation

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        cancellationHandler?()
        for entry in children {
            entry.progress.cancel()
        }
        updateCompletedUnitCount()
    }

    // MARK: becomeCurrent / resignCurrent

    func becomeCurrent(withPendingUnitCount unitCount: Int64) {
        CurrentProgressStack.push((self, unitCount))
    }

    func resignCurrent() {
        // No-op if already consumed by a child init; safe to call defensively.
        _ = CurrentProgressStack.pop()
    }
    
    var cancellationHandler: (() -> Void)? {
        didSet {
            if isCancelled { cancellationHandler?() }
        }
    }
}

enum CurrentProgressStack {
    private static let key = "Progressss.currentStack"

    private static var storage: [(progress: Progressss, pendingUnitCount: Int64)] {
        get {
            (Thread.current.threadDictionary[key] as? [(Progressss, Int64)]) ?? []
        }
        set {
            Thread.current.threadDictionary[key] = newValue
        }
    }

    static func push(_ entry: (progress: Progressss, pendingUnitCount: Int64)) {
        storage.append(entry)
    }

    static func pop() -> (progress: Progressss, pendingUnitCount: Int64)? {
        guard !storage.isEmpty else { return nil }
        return storage.removeLast()
    }
}
