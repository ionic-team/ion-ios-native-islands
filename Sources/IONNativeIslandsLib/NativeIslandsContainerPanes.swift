#if canImport(UIKit)
    import UIKit

    struct IslandPane {
        var color: UIColor
        var under: String?
    }

    extension NativeIslandsContainer {
        /// A scroll container's solid background, painted natively under the WebView below the
        /// island named by `under` (or above every island when nil).
        struct Pane {
            let view: UIView
            var container: IslandScrollContainer
            var under: String?
        }

        func applyPanes(_ incoming: [String: IslandPane], scrollContainers: [IslandScrollContainer]) {
            let containers = Dictionary(scrollContainers.map { ($0.id, $0) }) { first, _ in first }
            for (id, pane) in panes where incoming[id] == nil || containers[id] == nil {
                pane.view.removeFromSuperview()
                panes[id] = nil
            }
            for (id, pane) in incoming {
                guard let container = containers[id] else { continue }
                let view = panes[id]?.view ?? {
                    let view = UIView()
                    view.isUserInteractionEnabled = false
                    return view
                }()
                view.backgroundColor = pane.color
                panes[id] = Pane(view: view, container: container, under: pane.under)
            }
        }

        func orderPanes() {
            for pane in panes.values {
                let above = pane.under.flatMap { order.firstIndex(of: $0) }.flatMap { start in
                    order[start...].lazy.compactMap { self.hosts[$0]?.view }.first { $0.superview === self.underlayPlane }
                }
                if let above {
                    underlayPlane.insertSubview(pane.view, belowSubview: above)
                } else {
                    underlayPlane.addSubview(pane.view)
                }
            }
        }

        func placePanes(in frame: NIMotionFrame) {
            for pane in panes.values {
                let screen = screenIslandRect(pane.container.scrollport, in: frame)
                pane.view.frame = underlayPlane.convert(screen.cgRect, from: self)
                motions.applyMoves(pane.container.motionPath, scale: 1, to: pane.view.layer, in: frame)
            }
        }

        func removeAllPanes() {
            panes.values.forEach { $0.view.removeFromSuperview() }
            panes.removeAll()
        }
    }
#endif
