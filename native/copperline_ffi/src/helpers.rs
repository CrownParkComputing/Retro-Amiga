// Ported verbatim from crates/copperline-web/src/lib.rs (same GPL project
// family): the W3C-code keymap and the small input helpers, so the Flutter
// side can send the exact key codes a browser would.

pub fn w3c_code_to_amiga_rawkey(code: &str) -> Option<u8> {
    Some(match code {
        // Letters (row-by-row, Amiga's funny layout)
        "KeyA" => 0x20,
        "KeyB" => 0x35,
        "KeyC" => 0x33,
        "KeyD" => 0x22,
        "KeyE" => 0x12,
        "KeyF" => 0x23,
        "KeyG" => 0x24,
        "KeyH" => 0x25,
        "KeyI" => 0x17,
        "KeyJ" => 0x26,
        "KeyK" => 0x27,
        "KeyL" => 0x28,
        "KeyM" => 0x37,
        "KeyN" => 0x36,
        "KeyO" => 0x18,
        "KeyP" => 0x19,
        "KeyQ" => 0x10,
        "KeyR" => 0x13,
        "KeyS" => 0x21,
        "KeyT" => 0x14,
        "KeyU" => 0x16,
        "KeyV" => 0x34,
        "KeyW" => 0x11,
        "KeyX" => 0x32,
        "KeyY" => 0x15,
        "KeyZ" => 0x31,
        // Top-row digits
        "Digit1" => 0x01,
        "Digit2" => 0x02,
        "Digit3" => 0x03,
        "Digit4" => 0x04,
        "Digit5" => 0x05,
        "Digit6" => 0x06,
        "Digit7" => 0x07,
        "Digit8" => 0x08,
        "Digit9" => 0x09,
        "Digit0" => 0x0A,
        // Punctuation
        "Backquote" => 0x00,
        "Minus" => 0x0B,
        "Equal" => 0x0C,
        "Backslash" => 0x0D,
        "BracketLeft" => 0x1A,
        "BracketRight" => 0x1B,
        "Semicolon" => 0x29,
        "Quote" => 0x2A,
        "Comma" => 0x38,
        "Period" => 0x39,
        "Slash" => 0x3A,
        // International keys: the ISO 102nd key between left Shift and Z is
        // Amiga rawkey $30; the Japanese Ro key sits in the same matrix
        // position on layouts that have it.
        "IntlBackslash" | "IntlRo" => 0x30,
        // Control
        "Space" => 0x40,
        "Enter" => 0x44,
        "Backspace" => 0x41,
        "Tab" => 0x42,
        "Escape" => 0x45,
        "Delete" => 0x46,
        // Amiga Help: F11 host-side (no dedicated host key exists).
        "F11" => 0x5F,
        "ShiftLeft" => 0x60,
        "ShiftRight" => 0x61,
        "CapsLock" => 0x62,
        // Single Ctrl key on the Amiga; right Ctrl doubles as Right Amiga
        // alongside the right Super/Meta key (see host_input.rs).
        "ControlLeft" => 0x63,
        "AltLeft" => 0x64,
        "AltRight" => 0x65,
        "MetaLeft" | "OSLeft" => 0x66,
        "MetaRight" | "OSRight" | "ControlRight" => 0x67,
        // Arrows
        "ArrowUp" => 0x4C,
        "ArrowDown" => 0x4D,
        "ArrowRight" => 0x4E,
        "ArrowLeft" => 0x4F,
        // Function keys
        "F1" => 0x50,
        "F2" => 0x51,
        "F3" => 0x52,
        "F4" => 0x53,
        "F5" => 0x54,
        "F6" => 0x55,
        "F7" => 0x56,
        "F8" => 0x57,
        "F9" => 0x58,
        "F10" => 0x59,
        // Numpad
        "Numpad0" => 0x0F,
        "Numpad1" => 0x1D,
        "Numpad2" => 0x1E,
        "Numpad3" => 0x1F,
        "Numpad4" => 0x2D,
        "Numpad5" => 0x2E,
        "Numpad6" => 0x2F,
        "Numpad7" => 0x3D,
        "Numpad8" => 0x3E,
        "Numpad9" => 0x3F,
        "NumpadDecimal" => 0x3C,
        "NumpadEnter" => 0x43,
        "NumpadSubtract" => 0x4A,
        "NumpadAdd" => 0x5E,
        "NumpadMultiply" => 0x5D,
        "NumpadDivide" => 0x5C,
        "NumpadParenLeft" => 0x5A,
        "NumpadParenRight" => 0x5B,
        _ => return None,
    })
}

/// Map a page-facing port number to the core's port index: `1` selects the
/// mouse/port-1 socket (index 0) and any other value port 2 (index 1).
pub fn port_index(port: u8) -> usize {
    usize::from(port != 1)
}

/// Mirrors the desktop frontend's fractional mouse-delta accumulator
/// (`take_integral_mouse_delta` in window/present.rs): whole pixels go to the
/// emulated mouse, the fraction carries to the next event.
pub fn take_integral_delta(value: &mut f64) -> i32 {
    let whole = value.trunc();
    if whole > i32::MAX as f64 {
        *value = 0.0;
        i32::MAX
    } else if whole < i32::MIN as f64 {
        *value = 0.0;
        i32::MIN
    } else {
        *value -= whole;
        whole as i32
    }
}
