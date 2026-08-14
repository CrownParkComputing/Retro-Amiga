import UIKit

/// The whole screen as a trackpad, for Workbench and mouse-driven games.
///
/// Relative, like a laptop trackpad, not absolute like a stylus: the Amiga
/// moves its own pointer, so what the finger supplies is deltas. A tap is a
/// left click, a two-finger tap a right click, and a drag with a resting
/// second finger is a held-button drag.
///
/// A UIControl so the pass-through window lets its touches land; while this
/// is up it owns the screen apart from the corner strip, which is the point -
/// mouse mode is a mode.
final class TouchMouseView: UIControl {

  /// (dx, dy) in Amiga-pointer deltas.
  var onMove: ((Int32, Int32) -> Void)?
  /// (button, pressed): 0 left, 1 right.
  var onButton: ((Int32, Bool) -> Void)?

  private var last: CGPoint?
  private var movedFar = false
  private var began: Date?

  /// How much faster the pointer moves than the finger. Less than 1 would be
  /// precise and tiring; iPad screens are big enough that 1.4 lands well.
  private let gain: CGFloat = 1.4

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { fatalError("not from a storyboard") }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    if event?.allTouches?.count == 2 {
      // Two fingers down: right click, pressed for as long as they rest.
      onButton?(1, true)
      return
    }
    last = touches.first?.location(in: self)
    movedFar = false
    began = Date()
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first, let previous = last else { return }
    let at = touch.location(in: self)
    let dx = (at.x - previous.x) * gain
    let dy = (at.y - previous.y) * gain
    if abs(dx) >= 1 || abs(dy) >= 1 {
      last = at
      movedFar = movedFar || abs(dx) > 6 || abs(dy) > 6
      onMove?(Int32(dx), Int32(dy))
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    if event?.allTouches?.contains(where: { $0.phase == .began }) == true {
      return
    }
    onButton?(1, false)
    // A short touch that went nowhere is a click. Press and release are sent
    // a beat apart because a same-frame down-up can be missed by software
    // polling the button state once per frame.
    if let began = began, Date().timeIntervalSince(began) < 0.25, !movedFar {
      onButton?(0, true)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
        self?.onButton?(0, false)
      }
    }
    last = nil
    began = nil
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    onButton?(0, false)
    onButton?(1, false)
    last = nil
    began = nil
  }
}
