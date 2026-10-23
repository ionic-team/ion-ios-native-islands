#if canImport(UIKit)
    import UIKit

    struct IslandPane {
        var color: UIColor
        var under: String?
    }

    extension NativeIslandsContainer {
        func applyPanes(_ panes: [String: IslandPane], scrollContainers: [IslandScrollContainer]) {
            let containers = Dictionary(scrollContainers.map { ($0.id, $0) }) { first, _ in first }
            paneContainers = containers.filter { panes[$0.key] != nil }
            paneUnder = panes.compactMapValues(\.under)
            for (id, view) in paneViews where paneContainers[id] == nil {
                view.removeFromSuperview()
                paneViews[id] = nil
            }
            for id in paneContainers.keys {
                let view = paneViews[id] ?? {
                    let view = UIView()
                    view.isUserInteractionEnabled = false
                    paneViews[id] = view
                    return view
                }()
                view.backgroundColor = panes[id]?.color
            }
            updatePaneGeometry()
        }

        func orderPanes() {
            for (id, view) in paneViews {
                let above = paneUnder[id].flatMap { order.firstIndex(of: $0) }.flatMap { start in
                    order[start...].lazy.compactMap { self.hosts[$0] }.first { $0.superview === self.documentLayer }
                }
                if let above {
                    documentLayer.insertSubview(view, belowSubview: above)
                } else {
                    documentLayer.addSubview(view)
                }
            }
        }

        func updatePaneGeometry() {
            for (id, view) in paneViews {
                guard let pane = paneContainers[id] else { continue }
                let screen = screenIslandRect(
                    IslandRegion(
                        rect: pane.rect,
                        scrollPath: pane.scrollPath,
                        coordinateSpace: pane.coordinateSpace,
                        sticky: nil,
                        motionPath: pane.motionPath
                    )
                )
                view.frame = documentLayer.convert(screen.cgRect, from: self)
                applyMotion(trackedMoves(pane.motionPath), scale: 1, to: view.layer)
            }
        }

        func removeAllPanes() {
            paneViews.values.forEach { $0.removeFromSuperview() }
            paneViews.removeAll()
            paneContainers.removeAll()
            paneUnder.removeAll()
        }
    }
#endif
