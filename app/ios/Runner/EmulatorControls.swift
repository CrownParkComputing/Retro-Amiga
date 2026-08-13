import UIKit

/// The in-game controls on iOS.
///
/// Android draws these with a second Flutter engine stacked over SDL's
/// SurfaceView. iOS cannot: the core runs on the main thread inside this same
/// process and SDL owns a UIWindow that covers Flutter's, so anything Flutter
/// draws is behind the game and cannot be touched. Without these there is no
/// pause and, worse, no way out of a game at all - the app has to be killed.
///
/// So this is UIKit, in a window of its own above SDL's. The window passes
/// every touch through except the ones that land on a button, which is what
/// lets the game keep the rest of the screen.
final class EmulatorControls {

  private var window: PassthroughWindow?
  private var paused = false
  private var pauseButton: UIButton?
  private var keyboard: AmigaKeyboardView?

  /// Called when the player asks to leave the game.
  var onQuit: (() -> Void)?

  /// Called with the new state when the player pauses or resumes.
  var onPause: ((Bool) -> Void)?

  /// Called with (amigaKeyCode, pressed) from the on-screen keyboard.
  var onKey: ((Int32, Bool) -> Void)?

  /// Called when the player toggles the on-screen pad.
  var onPadToggle: (() -> Void)?

  /// The window the launcher was using, so it can be given back when
  /// emulation ends. SDL makes its own window key while a game runs, and
  /// without this the app is left showing nothing anybody can touch.
  private weak var previousKeyWindow: UIWindow?

  func show() {
    guard window == nil else { return }
    target.controls = self
    previousKeyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive })
      ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else { return }

    let window = PassthroughWindow(windowScene: scene)
    // Above everything SDL puts up, including its own alerts. Spelled through
    // rawValue because UIWindow.Level has no arithmetic of its own.
    window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue + 1)
    window.backgroundColor = .clear
    window.isHidden = false

    let controller = UIViewController()
    controller.view.backgroundColor = .clear
    window.rootViewController = controller

    let pause = makeButton(systemName: "pause.fill", action: #selector(Target.pause))
    let keys = makeButton(systemName: "keyboard", action: #selector(Target.keyboard))
    let pad = makeButton(systemName: "gamecontroller", action: #selector(Target.pad))
    let quit = makeButton(systemName: "xmark", action: #selector(Target.quit))
    pauseButton = pause

    let stack = UIStackView(arrangedSubviews: [pause, keys, pad, quit])
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.trailingAnchor.constraint(
        equalTo: controller.view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
      stack.topAnchor.constraint(
        equalTo: controller.view.safeAreaLayoutGuide.topAnchor, constant: 14),
    ])

    self.window = window
  }

  func hide() {
    window?.isHidden = true
    window = nil
    pauseButton = nil
    keyboard = nil
    paused = false
    // Hand the screen back to the launcher.
    previousKeyWindow?.makeKeyAndVisible()
    previousKeyWindow = nil
  }

  fileprivate func togglePause() {
    paused.toggle()
    pauseButton?.setImage(
      UIImage(systemName: paused ? "play.fill" : "pause.fill"), for: .normal)
    onPause?(paused)
  }

  /// Shows or hides the on-screen Amiga keyboard, full width along the
  /// bottom, like the C64 one.
  fileprivate func toggleKeyboard() {
    guard let controller = window?.rootViewController else { return }
    if let keyboard = keyboard {
      keyboard.removeFromSuperview()
      self.keyboard = nil
      return
    }
    let view = AmigaKeyboardView(frame: .zero)
    view.onKey = { [weak self] code, pressed in self?.onKey?(code, pressed) }
    view.translatesAutoresizingMaskIntoConstraints = false
    controller.view.addSubview(view)
    let guide = controller.view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 4),
      view.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -4),
      view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -4),
      view.heightAnchor.constraint(
        equalTo: controller.view.heightAnchor, multiplier: 0.42),
    ])
    keyboard = view
  }

  /// The button targets.
  ///
  /// Target-action rather than UIAction: this app deploys to iOS 13 and
  /// UIButton.addAction arrived in 14, which fails the build rather than
  /// degrading.
  private final class Target: NSObject {
    weak var controls: EmulatorControls?

    @objc func pause() { controls?.togglePause() }
    @objc func keyboard() { controls?.toggleKeyboard() }
    @objc func pad() { controls?.onPadToggle?() }
    @objc func quit() { controls?.onQuit?() }
  }

  private let target = Target()

  private func makeButton(systemName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: systemName), for: .normal)
    button.tintColor = .white
    // Dark and semi-transparent, so it reads over both a bright game and a
    // black border without a box around it.
    button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    button.layer.cornerRadius = 22
    button.layer.borderWidth = 1
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
    button.translatesAutoresizingMaskIntoConstraints = false
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    button.addTarget(target, action: action, for: .touchUpInside)
    return button
  }
}

/// A window that is invisible to touches except where it has a control.
///
/// Without this the game would receive nothing: a full-screen window at this
/// level swallows every touch, and the joystick, the mouse and the Amiga's own
/// requesters would all stop working.
private final class PassthroughWindow: UIWindow {
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hit = super.hitTest(point, with: event) else { return nil }
    // Walk up rather than asking whether the hit view IS a button. A tap on
    // the icon lands on the button's image view, not the button, so the
    // stricter test passed those touches through to the game - which made the
    // controls work only when a finger caught the ring around the icon.
    var view: UIView? = hit
    while let current = view {
      if current is UIControl { return hit }
      view = current.superview
    }
    return nil
  }
}
