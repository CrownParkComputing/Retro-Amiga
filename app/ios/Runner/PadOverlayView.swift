import UIKit

/// The on-screen pad on iOS - OUR pad, the one designed in Settings.
///
/// Android draws this with Flutter over the SDL surface; iOS cannot, so the
/// same layout is drawn here in UIKit. It reads the same pad_layout.json the
/// designer writes - stick and button positions as screen fractions, the
/// style, and any added key buttons - and feeds the same virtual-pad entry
/// points, so the core cannot tell this pad from Android's or from a
/// physical one. The core's own Amiberry-drawn overlay is not used anywhere.
final class PadOverlayView: UIView {

  /// (pad, button, pressed) - indices are the UAE4ARM_HOST_* values.
  var onButton: ((Int32, Int32, Bool) -> Void)?
  /// (pad, left, right, up, down)
  var onDirection: ((Int32, Bool, Bool, Bool, Bool) -> Void)?
  /// (amigaKeyCode, pressed) for added key buttons.
  var onKey: ((Int32, Bool) -> Void)?

  /// UAE4ARM_HOST_PAD_JOYSTICK or _CD32, decided by the layout's style.
  private(set) var pad: Int32 = 1

  private struct Layout {
    var stick = CGPoint(x: 0.13, y: 0.74)
    var buttons = CGPoint(x: 0.89, y: 0.72)
    var transport = CGPoint(x: 0.78, y: 0.12)
    var cd32 = false
    var custom: [(label: String, key: Int32?, direction: String?)] = []
  }

  private var layout = Layout()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
  }

  required init?(coder: NSCoder) { fatalError("not from a storyboard") }

  /// The fraction positions become points at whatever size this view ends up,
  /// so the controls are placed once real bounds exist and again on rotation.
  private var builtAt = CGSize.zero

  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != builtAt && bounds.size != .zero {
      builtAt = bounds.size
      rebuild()
    }
  }

  /// Reads the designed layout, with the style forced by the toggle rather
  /// than taken from the file: the in-game button cycles off, joystick, CD32,
  /// and the file's positions and added buttons apply to whichever is up.
  /// forcedStyle: 1 joystick, 2 CD32.
  func loadLayout(forcedStyle: Int32) {
    loadLayout()
    layout.cd32 = forcedStyle == 2
    pad = forcedStyle
    rebuild()
  }

  /// Reads the designed layout. The file lives in Application Support, where
  /// the launcher's pad designer saves it; both run in this same container.
  func loadLayout() {
    layout = Layout()
    if let dir = NSSearchPathForDirectoriesInDomains(
         .applicationSupportDirectory, .userDomainMask, true).first,
       let data = FileManager.default.contents(atPath: dir + "/pad_layout.json"),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      func point(_ key: String) -> CGPoint? {
        guard let pair = json[key] as? [Any], pair.count == 2,
              let x = (pair[0] as? NSNumber)?.doubleValue,
              let y = (pair[1] as? NSNumber)?.doubleValue else { return nil }
        return CGPoint(x: x, y: y)
      }
      if let p = point("stick") { layout.stick = p }
      if let p = point("buttons") { layout.buttons = p }
      if let p = point("transport") { layout.transport = p }
      layout.cd32 = (json["style"] as? String) == "cd32"
      for entry in (json["custom"] as? [[String: Any]]) ?? [] {
        let label = entry["label"] as? String
        if let code = (entry["key"] as? NSNumber)?.int32Value {
          layout.custom.append((label ?? "?", code, nil))
        } else if let direction = entry["direction"] as? String {
          layout.custom.append((label ?? direction.uppercased(), nil, direction))
        }
      }
    }
    pad = layout.cd32 ? 2 : 1
    rebuild()
  }

  // MARK: - Building

  private func rebuild() {
    subviews.forEach { $0.removeFromSuperview() }

    let stick = StickView()
    stick.onDirection = { [weak self] l, r, u, d in
      guard let self = self else { return }
      self.onDirection?(self.pad, l, r, u, d)
    }
    place(stick, size: CGSize(width: 170, height: 170), at: layout.stick)

    // The button cluster: custom keys stack above the fire buttons or the
    // CD32 diamond, exactly as the designer shows them.
    let cluster = UIStackView()
    cluster.axis = .vertical
    cluster.alignment = .trailing
    cluster.spacing = 8
    for custom in layout.custom {
      let button = roundButton(
        label: custom.label, colour: UIColor(white: 0.25, alpha: 0.9), size: 52)
      let key = custom.key
      let direction = custom.direction
      button.onPress = { [weak self] pressed in
        guard let self = self else { return }
        if let key = key {
          self.onKey?(key, pressed)
        } else if let direction = direction {
          self.onDirection?(
            self.pad,
            pressed && direction == "left", pressed && direction == "right",
            pressed && direction == "up", pressed && direction == "down")
        }
      }
      cluster.addArrangedSubview(button)
    }
    if layout.cd32 {
      cluster.addArrangedSubview(cd32Diamond())
    } else {
      // Blue 2 above red 1, as the Flutter pad draws them.
      cluster.addArrangedSubview(fireButton(label: "2", colour: UIColor(
        red: 0x30 / 255, green: 0x50 / 255, blue: 0xDC / 255, alpha: 1), index: 1))
      cluster.addArrangedSubview(fireButton(label: "1", colour: UIColor(
        red: 0xDC / 255, green: 0x32 / 255, blue: 0x32 / 255, alpha: 1), index: 0))
    }
    cluster.translatesAutoresizingMaskIntoConstraints = false
    addSubview(cluster)
    NSLayoutConstraint.activate([
      cluster.centerXAnchor.constraint(
        equalTo: leadingAnchor, constant: bounds.width * layout.buttons.x),
      cluster.centerYAnchor.constraint(
        equalTo: topAnchor, constant: bounds.height * layout.buttons.y),
    ])

    if layout.cd32 {
      let transport = UIStackView()
      transport.axis = .horizontal
      transport.spacing = 10
      for (symbol, index) in [("backward.fill", Int32(5)), ("play.fill", 4), ("forward.fill", 6)] {
        let button = roundButton(
          label: nil, colour: UIColor(white: 0.2, alpha: 0.85), size: 36)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.onPress = { [weak self] pressed in
          guard let self = self else { return }
          self.onButton?(self.pad, index, pressed)
        }
        transport.addArrangedSubview(button)
      }
      place(transport, size: CGSize(width: 128, height: 36), at: layout.transport)
    }
  }

  private func place(_ view: UIView, size: CGSize, at fraction: CGPoint) {
    view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(view)
    NSLayoutConstraint.activate([
      view.widthAnchor.constraint(equalToConstant: size.width),
      view.heightAnchor.constraint(equalToConstant: size.height),
      view.centerXAnchor.constraint(
        equalTo: leadingAnchor, constant: bounds.width * fraction.x),
      view.centerYAnchor.constraint(
        equalTo: topAnchor, constant: bounds.height * fraction.y),
    ])
  }

  private func fireButton(label: String, colour: UIColor, index: Int32) -> PressButton {
    let button = roundButton(label: label, colour: colour, size: 64)
    button.onPress = { [weak self] pressed in
      guard let self = self else { return }
      self.onButton?(self.pad, index, pressed)
    }
    return button
  }

  /// Red bottom, blue left, green right, yellow top - the diamond as it sits
  /// on a real CD32 pad, colours matching the Flutter widget's.
  private func cd32Diamond() -> UIView {
    let holder = UIView()
    holder.translatesAutoresizingMaskIntoConstraints = false
    holder.widthAnchor.constraint(equalToConstant: 170).isActive = true
    holder.heightAnchor.constraint(equalToConstant: 170).isActive = true

    let spots: [(String, UIColor, Int32, CGPoint)] = [
      ("Y", UIColor(red: 0xD8 / 255, green: 0xC4 / 255, blue: 0x3C / 255, alpha: 1), 3, CGPoint(x: 0.5, y: 0.19)),
      ("B", UIColor(red: 0x30 / 255, green: 0x50 / 255, blue: 0xDC / 255, alpha: 1), 1, CGPoint(x: 0.19, y: 0.5)),
      ("G", UIColor(red: 0x2E / 255, green: 0x9E / 255, blue: 0x44 / 255, alpha: 1), 2, CGPoint(x: 0.81, y: 0.5)),
      ("R", UIColor(red: 0xDC / 255, green: 0x32 / 255, blue: 0x32 / 255, alpha: 1), 0, CGPoint(x: 0.5, y: 0.81)),
    ]
    for (label, colour, index, spot) in spots {
      let button = roundButton(label: label, colour: colour, size: 64)
      button.onPress = { [weak self] pressed in
        guard let self = self else { return }
        self.onButton?(self.pad, index, pressed)
      }
      button.translatesAutoresizingMaskIntoConstraints = false
      holder.addSubview(button)
      NSLayoutConstraint.activate([
        button.centerXAnchor.constraint(
          equalTo: holder.leadingAnchor, constant: 170 * spot.x),
        button.centerYAnchor.constraint(
          equalTo: holder.topAnchor, constant: 170 * spot.y),
      ])
    }
    return holder
  }

  private func roundButton(label: String?, colour: UIColor, size: CGFloat) -> PressButton {
    let button = PressButton(type: .custom)
    if let label = label {
      button.setTitle(label, for: .normal)
      button.setTitleColor(.white, for: .normal)
      button.titleLabel?.font = .boldSystemFont(ofSize: size * 0.34)
    }
    button.backgroundColor = colour.withAlphaComponent(0.75)
    button.layer.cornerRadius = size / 2
    button.layer.borderWidth = 2
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: size).isActive = true
    button.heightAnchor.constraint(equalToConstant: size).isActive = true
    return button
  }

  /// A button that reports press and release, because a held fire button
  /// must stay down.
  final class PressButton: UIButton {
    var onPress: ((Bool) -> Void)?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesBegan(touches, with: event)
      alpha = 1.0
      onPress?(true)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesEnded(touches, with: event)
      alpha = 0.9
      onPress?(false)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      super.touchesCancelled(touches, with: event)
      alpha = 0.9
      onPress?(false)
    }
  }

  /// The stick: a base that reads the finger's angle as eight-way direction.
  /// UIControl rather than UIView so the pass-through window lets its touches
  /// land.
  private final class StickView: UIControl {
    var onDirection: ((Bool, Bool, Bool, Bool) -> Void)?
    private let knob = UIView()

    override init(frame: CGRect) {
      super.init(frame: frame)
      backgroundColor = UIColor(white: 0.15, alpha: 0.55)
      layer.borderWidth = 2
      layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
      knob.backgroundColor = UIColor(white: 0.85, alpha: 0.85)
      addSubview(knob)
    }

    required init?(coder: NSCoder) { fatalError("not from a storyboard") }

    override func layoutSubviews() {
      super.layoutSubviews()
      layer.cornerRadius = bounds.width / 2
      let size = bounds.width * 0.42
      if knob.transform == .identity {
        knob.frame = CGRect(
          x: (bounds.width - size) / 2, y: (bounds.height - size) / 2,
          width: size, height: size)
      }
      knob.layer.cornerRadius = size / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      track(touches)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      track(touches)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      release()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      release()
    }

    private func track(_ touches: Set<UITouch>) {
      guard let touch = touches.first else { return }
      let centre = CGPoint(x: bounds.midX, y: bounds.midY)
      let at = touch.location(in: self)
      let dx = at.x - centre.x
      let dy = at.y - centre.y
      // A dead zone around the centre, so resting a thumb is not a twitch.
      let dead = bounds.width * 0.12
      let left = dx < -dead, right = dx > dead
      let up = dy < -dead, down = dy > dead
      let reach = bounds.width * 0.22
      knob.transform = CGAffineTransform(
        translationX: max(-reach, min(reach, dx)),
        y: max(-reach, min(reach, dy)))
      onDirection?(left, right, up, down)
    }

    private func release() {
      knob.transform = .identity
      onDirection?(false, false, false, false)
    }
  }
}
