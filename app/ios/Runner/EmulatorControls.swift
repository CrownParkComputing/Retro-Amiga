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

  /// Called when the player asks to leave the game.
  var onQuit: (() -> Void)?

  /// Called with the new state when the player pauses or resumes.
  var onPause: ((Bool) -> Void)?

  func show() {
    guard window == nil else { return }
    guard let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive })
      ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
    else { return }

    let window = PassthroughWindow(windowScene: scene)
    // Above everything SDL puts up, including its own alerts.
    window.windowLevel = .alert + 1
    window.backgroundColor = .clear
    window.isHidden = false

    let controller = UIViewController()
    controller.view.backgroundColor = .clear
    window.rootViewController = controller

    let pause = makeButton(systemName: "pause.fill") { [weak self] in
      self?.togglePause()
    }
    let quit = makeButton(systemName: "xmark") { [weak self] in
      self?.onQuit?()
    }
    pauseButton = pause

    let stack = UIStackView(arrangedSubviews: [pause, quit])
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
    paused = false
  }

  private func togglePause() {
    paused.toggle()
    pauseButton?.setImage(
      UIImage(systemName: paused ? "play.fill" : "pause.fill"), for: .normal)
    onPause?(paused)
  }

  private func makeButton(systemName: String, action: @escaping () -> Void) -> UIButton {
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
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
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
    return hit is UIButton ? hit : nil
  }
}
