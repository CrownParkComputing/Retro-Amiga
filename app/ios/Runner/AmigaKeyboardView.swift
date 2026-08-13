import UIKit

/// The on-screen Amiga keyboard for iOS.
///
/// Android draws its keyboard with Flutter, stacked over SDL's SurfaceView.
/// iOS cannot put Flutter above SDL - the core owns the main thread while a
/// game runs - so the keyboard is UIKit, in the same pass-through window as
/// the pause and quit buttons. Full width, like the C64 one.
///
/// Keys send raw Amiga key codes - the AK_ values from the core's
/// keyboard.h, the numbering the hardware itself used - through
/// uae4arm_host_send_key. Press on touch down, release on touch up, so held
/// keys repeat exactly as a real Amiga would see them.
final class AmigaKeyboardView: UIView {

  /// Called with (amigaKeyCode, pressed).
  var onKey: ((Int32, Bool) -> Void)?

  private struct Key {
    let label: String
    let code: Int32
    /// Layout weight: SPACE is wider than Q.
    var width: CGFloat = 1
  }

  /// The Amiga keyboard, one row per array. Codes are AK_ constants.
  private let rows: [[Key]] = [
    [
      Key(label: "ESC", code: 0x45), Key(label: "F1", code: 0x50),
      Key(label: "F2", code: 0x51), Key(label: "F3", code: 0x52),
      Key(label: "F4", code: 0x53), Key(label: "F5", code: 0x54),
      Key(label: "F6", code: 0x55), Key(label: "F7", code: 0x56),
      Key(label: "F8", code: 0x57), Key(label: "F9", code: 0x58),
      Key(label: "F10", code: 0x59), Key(label: "HELP", code: 0x5F),
    ],
    [
      Key(label: "1", code: 0x01), Key(label: "2", code: 0x02),
      Key(label: "3", code: 0x03), Key(label: "4", code: 0x04),
      Key(label: "5", code: 0x05), Key(label: "6", code: 0x06),
      Key(label: "7", code: 0x07), Key(label: "8", code: 0x08),
      Key(label: "9", code: 0x09), Key(label: "0", code: 0x0A),
      Key(label: "DEL", code: 0x46, width: 1.5),
    ],
    [
      Key(label: "Q", code: 0x10), Key(label: "W", code: 0x11),
      Key(label: "E", code: 0x12), Key(label: "R", code: 0x13),
      Key(label: "T", code: 0x14), Key(label: "Y", code: 0x15),
      Key(label: "U", code: 0x16), Key(label: "I", code: 0x17),
      Key(label: "O", code: 0x18), Key(label: "P", code: 0x19),
      Key(label: "RET", code: 0x44, width: 1.5),
    ],
    [
      Key(label: "A", code: 0x20), Key(label: "S", code: 0x21),
      Key(label: "D", code: 0x22), Key(label: "F", code: 0x23),
      Key(label: "G", code: 0x24), Key(label: "H", code: 0x25),
      Key(label: "J", code: 0x26), Key(label: "K", code: 0x27),
      Key(label: "L", code: 0x28), Key(label: "UP", code: 0x4C),
      Key(label: "TAB", code: 0x42, width: 1.5),
    ],
    [
      Key(label: "Z", code: 0x31), Key(label: "X", code: 0x32),
      Key(label: "C", code: 0x33), Key(label: "V", code: 0x34),
      Key(label: "B", code: 0x35), Key(label: "N", code: 0x36),
      Key(label: "M", code: 0x37), Key(label: "LEFT", code: 0x4F),
      Key(label: "DOWN", code: 0x4D), Key(label: "RIGHT", code: 0x4E),
      Key(label: "CTRL", code: 0x63, width: 1.5),
    ],
    [
      Key(label: "SHIFT", code: 0x60, width: 2),
      Key(label: "ALT", code: 0x64, width: 1.5),
      Key(label: "SPACE", code: 0x40, width: 6),
      Key(label: "AMIGA", code: 0x66, width: 1.5),
      Key(label: "SHIFT", code: 0x61, width: 2),
    ],
  ]

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.black.withAlphaComponent(0.72)
    layer.cornerRadius = 10
    buildRows()
  }

  required init?(coder: NSCoder) { fatalError("not from a storyboard") }

  private func buildRows() {
    let column = UIStackView()
    column.axis = .vertical
    column.spacing = 5
    column.distribution = .fillEqually
    column.translatesAutoresizingMaskIntoConstraints = false
    addSubview(column)
    NSLayoutConstraint.activate([
      column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
      column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      column.topAnchor.constraint(equalTo: topAnchor, constant: 6),
      column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
    ])

    for row in rows {
      let line = UIStackView()
      line.axis = .horizontal
      line.spacing = 5
      line.distribution = .fillProportionally
      column.addArrangedSubview(line)

      var reference: (UIView, CGFloat)?
      for key in row {
        let button = keyButton(for: key)
        line.addArrangedSubview(button)
        // fillProportionally follows intrinsic size, which for a button is
        // its label. The widths must follow the weights instead, so every
        // key is constrained relative to the row's first.
        if let (view, weight) = reference {
          button.widthAnchor.constraint(
            equalTo: view.widthAnchor, multiplier: key.width / weight
          ).isActive = true
        } else {
          reference = (button, key.width)
        }
      }
    }
  }

  private func keyButton(for key: Key) -> UIButton {
    let button = KeyButton(type: .custom)
    button.setTitle(key.label, for: .normal)
    button.setTitleColor(.white, for: .normal)
    button.titleLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
    button.titleLabel?.adjustsFontSizeToFitWidth = true
    button.titleLabel?.minimumScaleFactor = 0.5
    button.backgroundColor = UIColor.white.withAlphaComponent(0.14)
    button.layer.cornerRadius = 6
    // Down/up rather than tap: games read the keyboard matrix, and a held
    // key must stay held.
    button.onDown = { [weak self] in self?.onKey?(key.code, true) }
    button.onUp = { [weak self] in self?.onKey?(key.code, false) }
    return button
  }

  /// A button that reports touch down and up separately.
  private final class KeyButton: UIButton {
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesBegan(touches, with: event)
      backgroundColor = UIColor.white.withAlphaComponent(0.35)
      onDown?()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      backgroundColor = UIColor.white.withAlphaComponent(0.14)
      onUp?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      backgroundColor = UIColor.white.withAlphaComponent(0.14)
      onUp?()
    }
  }
}
