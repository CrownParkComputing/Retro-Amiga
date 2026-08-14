package com.uae4arm2026;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.os.Bundle;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Visual controller mapping screen showing a CD32 pad graphic.
 * Users tap a CD32 button, then press a physical button to assign it.
 * Also allows mapping extra physical buttons to Amiga keyboard keys.
 */
public class ControllerMapActivity extends Activity {

	// CD32 target indices
	static final int CD32_RED = 0;
	static final int CD32_BLUE = 1;
	static final int CD32_GREEN = 2;
	static final int CD32_YELLOW = 3;
	static final int CD32_PLAY = 4;
	static final int CD32_RWD = 5;
	static final int CD32_FFW = 6;
	static final int NUM_CD32 = 7;

	// Amiga keycodes (from keyboard.h)
	static final int AK_SPC = 0x40;
	static final int AK_RET = 0x44;
	static final int AK_ESC = 0x45;
	static final int AK_F1 = 0x50;
	static final int AK_F2 = 0x51;
	static final int AK_F3 = 0x52;
	static final int AK_F4 = 0x53;
	static final int AK_F5 = 0x54;
	static final int AK_F6 = 0x55;
	static final int AK_F7 = 0x56;
	static final int AK_F8 = 0x57;
	static final int AK_F9 = 0x58;
	static final int AK_F10 = 0x59;
	static final int AK_HELP = 0x5F;
	static final int AK_P = 0x19;

	// Keyboard key choices for the picker
	static final int[] KEY_CODES = {
		-1, AK_SPC, AK_RET, AK_ESC, AK_P, AK_HELP,
		AK_F1, AK_F2, AK_F3, AK_F4, AK_F5,
		AK_F6, AK_F7, AK_F8, AK_F9, AK_F10
	};
	static final String[] KEY_NAMES = {
		"None", "Space", "Return", "Escape", "P", "Help",
		"F1", "F2", "F3", "F4", "F5",
		"F6", "F7", "F8", "F9", "F10"
	};

	// Extra physical buttons that can be mapped to keyboard keys
	static final int[] EXTRA_BUTTONS = {
		KeyEvent.KEYCODE_BUTTON_SELECT,
		KeyEvent.KEYCODE_BUTTON_L2,
		KeyEvent.KEYCODE_BUTTON_R2,
		KeyEvent.KEYCODE_BUTTON_THUMBL,
		KeyEvent.KEYCODE_BUTTON_THUMBR
	};
	static final String[] EXTRA_LABELS = {
		"Select", "L2", "R2", "L3 (Left Stick)", "R3 (Right Stick)"
	};

	// CD32 mapping: cd32Map[target] = Android keycode of assigned physical button
	private final int[] cd32Map = new int[NUM_CD32];

	// Keyboard mapping: keyMap[i] corresponds to EXTRA_BUTTONS[i], value = Amiga keycode or -1
	private final int[] keyMap = new int[EXTRA_BUTTONS.length];

	// Currently selected CD32 target waiting for physical button press (-1 = none)
	private int activeTarget = -1;

	// On-screen controller mode: 0 = none, 1 = joystick, 2 = cd32 pad
	private int onScreenMode = 0;
	private static final String[] ON_SCREEN_LABELS = { "None", "Joystick", "CD32 Pad" };

	private CD32PadView padView;
	private TextView statusText;
	private TextView onScreenLabel;
	private final TextView[] keyLabels = new TextView[EXTRA_BUTTONS.length];

	// Default CD32 button assignments
	private static final int[] CD32_DEFAULTS = {
		KeyEvent.KEYCODE_BUTTON_A,      // Red ← A
		KeyEvent.KEYCODE_BUTTON_B,      // Blue ← B
		KeyEvent.KEYCODE_BUTTON_X,      // Green ← X
		KeyEvent.KEYCODE_BUTTON_Y,      // Yellow ← Y
		KeyEvent.KEYCODE_BUTTON_START,  // Play ← Start
		KeyEvent.KEYCODE_BUTTON_L1,     // RWD ← L1
		KeyEvent.KEYCODE_BUTTON_R1      // FFW ← R1
	};

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
		loadMappings();
		buildUI();
	}

	private void loadMappings() {
		SharedPreferences prefs = getSharedPreferences("controller_map", MODE_PRIVATE);
		for (int i = 0; i < NUM_CD32; i++) {
			cd32Map[i] = prefs.getInt("cd32_" + i, CD32_DEFAULTS[i]);
		}
		for (int i = 0; i < EXTRA_BUTTONS.length; i++) {
			keyMap[i] = prefs.getInt("key_" + i, -1);
		}
		onScreenMode = prefs.getInt("onscreen_mode", 0);
	}

	private void saveMappings() {
		SharedPreferences.Editor ed = getSharedPreferences("controller_map", MODE_PRIVATE).edit();
		for (int i = 0; i < NUM_CD32; i++) {
			ed.putInt("cd32_" + i, cd32Map[i]);
		}
		for (int i = 0; i < EXTRA_BUTTONS.length; i++) {
			ed.putInt("key_" + i, keyMap[i]);
		}
		ed.putInt("onscreen_mode", onScreenMode);
		ed.apply();
	}

	// ── UI Construction ──────────────────────────────────────────────────

	private void buildUI() {
		float density = getResources().getDisplayMetrics().density;
		int pad = (int) (16 * density);

		LinearLayout content = new LinearLayout(this);
		content.setOrientation(LinearLayout.VERTICAL);
		content.setGravity(Gravity.CENTER_HORIZONTAL);
		content.setPadding(pad, pad, pad, pad);

		// Title
		TextView title = makeLabel("Controller Mapping", 20, true);
		content.addView(title, wrapParams(0, 0, 0, (int)(4 * density)));

		// Status / instructions
		statusText = makeLabel("Tap a CD32 button, then press a button on your controller", 13, false);
		statusText.setTextColor(0xCCCCCCCC);
		statusText.setGravity(Gravity.CENTER);
		content.addView(statusText, wrapParams(0, (int)(4 * density), 0, (int)(12 * density)));

		// CD32 Pad view
		padView = new CD32PadView(this);
		int padW = (int) (320 * density);
		int padH = (int) (260 * density);
		LinearLayout.LayoutParams padParams = new LinearLayout.LayoutParams(padW, padH);
		padParams.gravity = Gravity.CENTER_HORIZONTAL;
		padParams.bottomMargin = (int) (16 * density);
		content.addView(padView, padParams);

		// Separator
		View sep = new View(this);
		sep.setBackgroundColor(0x44FFFFFF);
		content.addView(sep, new LinearLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, (int)(1 * density)));

		// Keyboard section title
		TextView keyTitle = makeLabel("Extra Buttons → Keyboard Keys", 16, true);
		content.addView(keyTitle, wrapParams(0, (int)(14 * density), 0, (int)(8 * density)));

		// Keyboard mapping rows
		for (int i = 0; i < EXTRA_BUTTONS.length; i++) {
			LinearLayout row = new LinearLayout(this);
			row.setOrientation(LinearLayout.HORIZONTAL);
			row.setGravity(Gravity.CENTER_VERTICAL);
			row.setPadding((int)(8*density), (int)(10*density), (int)(8*density), (int)(10*density));
			row.setBackgroundColor(0x18FFFFFF);

			// Physical button name
			TextView physLabel = makeLabel(EXTRA_LABELS[i], 14, false);
			physLabel.setMinWidth((int)(120 * density));
			row.addView(physLabel);

			// Arrow
			TextView arrow = makeLabel("→", 14, false);
			arrow.setPadding((int)(8*density), 0, (int)(8*density), 0);
			row.addView(arrow);

			// Amiga key label (tappable)
			TextView akLabel = makeLabel(amigaKeyName(keyMap[i]), 14, true);
			akLabel.setTextColor(0xFF88CCFF);
			akLabel.setMinWidth((int)(80 * density));
			keyLabels[i] = akLabel;
			row.addView(akLabel);

			final int idx = i;
			row.setOnClickListener(v -> showKeyPicker(idx));

			LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
				ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
			rowParams.bottomMargin = (int)(2 * density);
			content.addView(row, rowParams);
		}

		// Separator before on-screen controller
		View sep2 = new View(this);
		sep2.setBackgroundColor(0x44FFFFFF);
		LinearLayout.LayoutParams sep2Params = new LinearLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, (int)(1 * density));
		sep2Params.topMargin = (int)(14 * density);
		content.addView(sep2, sep2Params);

		// On-screen controller section
		TextView oscTitle = makeLabel("On-Screen Controller", 16, true);
		content.addView(oscTitle, wrapParams(0, (int)(14 * density), 0, (int)(8 * density)));

		LinearLayout oscRow = new LinearLayout(this);
		oscRow.setOrientation(LinearLayout.HORIZONTAL);
		oscRow.setGravity(Gravity.CENTER_VERTICAL);
		oscRow.setPadding((int)(8*density), (int)(10*density), (int)(8*density), (int)(10*density));
		oscRow.setBackgroundColor(0x18FFFFFF);

		TextView oscDesc = makeLabel("Touch overlay", 14, false);
		oscDesc.setMinWidth((int)(120 * density));
		oscRow.addView(oscDesc);

		TextView oscArrow = makeLabel("→", 14, false);
		oscArrow.setPadding((int)(8*density), 0, (int)(8*density), 0);
		oscRow.addView(oscArrow);

		onScreenLabel = makeLabel(ON_SCREEN_LABELS[onScreenMode], 14, true);
		onScreenLabel.setTextColor(0xFF88CCFF);
		onScreenLabel.setMinWidth((int)(80 * density));
		oscRow.addView(onScreenLabel);

		oscRow.setOnClickListener(v -> {
			onScreenMode = (onScreenMode + 1) % ON_SCREEN_LABELS.length;
			onScreenLabel.setText(ON_SCREEN_LABELS[onScreenMode]);
		});

		LinearLayout.LayoutParams oscRowParams = new LinearLayout.LayoutParams(
			ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		oscRowParams.bottomMargin = (int)(2 * density);
		content.addView(oscRow, oscRowParams);

		// Save button
		TextView saveBtn = makeLabel("Save & Close", 16, true);
		saveBtn.setGravity(Gravity.CENTER);
		saveBtn.setTextColor(Color.WHITE);
		saveBtn.setPadding((int)(24*density), (int)(14*density), (int)(24*density), (int)(14*density));
		saveBtn.setBackgroundColor(0xFF3F51B5);
		saveBtn.setOnClickListener(v -> {
			saveMappings();
			setResult(RESULT_OK);
			finish();
		});
		content.addView(saveBtn, wrapParams(0, (int)(20*density), 0, (int)(16*density)));

		// Reset defaults button
		TextView resetBtn = makeLabel("Reset Defaults", 14, false);
		resetBtn.setGravity(Gravity.CENTER);
		resetBtn.setTextColor(0xFFFF8888);
		resetBtn.setOnClickListener(v -> {
			System.arraycopy(CD32_DEFAULTS, 0, cd32Map, 0, NUM_CD32);
			java.util.Arrays.fill(keyMap, -1);
			onScreenMode = 0;
			onScreenLabel.setText(ON_SCREEN_LABELS[0]);
			refreshAllLabels();
			padView.invalidate();
		});
		content.addView(resetBtn, wrapParams(0, 0, 0, (int)(16*density)));

		ScrollView scroll = new ScrollView(this);
		scroll.setBackgroundColor(0xFF1A1A2E);
		scroll.addView(content);
		setContentView(scroll);
	}

	private TextView makeLabel(String text, float sizeSp, boolean bold) {
		TextView tv = new TextView(this);
		tv.setText(text);
		tv.setTextColor(Color.WHITE);
		tv.setTextSize(sizeSp);
		if (bold) tv.setTypeface(null, Typeface.BOLD);
		return tv;
	}

	private LinearLayout.LayoutParams wrapParams(int l, int t, int r, int b) {
		LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(
			ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		p.setMargins(l, t, r, b);
		p.gravity = Gravity.CENTER_HORIZONTAL;
		return p;
	}

	private void refreshAllLabels() {
		for (int i = 0; i < EXTRA_BUTTONS.length; i++) {
			keyLabels[i].setText(amigaKeyName(keyMap[i]));
		}
	}

	// ── Key picker for keyboard section ──────────────────────────────────

	private void showKeyPicker(int extraIndex) {
		// If this physical button is currently assigned to a CD32 function, warn
		int physKeycode = EXTRA_BUTTONS[extraIndex];
		for (int c = 0; c < NUM_CD32; c++) {
			if (cd32Map[c] == physKeycode) {
				// Clear the CD32 assignment since we're repurposing this button
				cd32Map[c] = -1;
				padView.invalidate();
				break;
			}
		}

		new AlertDialog.Builder(this)
			.setTitle("Amiga Key for " + EXTRA_LABELS[extraIndex])
			.setItems(KEY_NAMES, (d, which) -> {
				keyMap[extraIndex] = KEY_CODES[which];
				keyLabels[extraIndex].setText(KEY_NAMES[which]);
			})
			.setNegativeButton(android.R.string.cancel, null)
			.show();
	}

	// ── Physical button capture ──────────────────────────────────────────

	@Override
	public boolean onKeyDown(int keyCode, KeyEvent event) {
		if (activeTarget >= 0 && isGamepadButton(keyCode)) {
			assignPhysicalToCD32(keyCode, activeTarget);
			activeTarget = -1;
			statusText.setText("Tap a CD32 button, then press a button on your controller");
			padView.invalidate();
			return true;
		}
		if (keyCode == KeyEvent.KEYCODE_BACK) {
			finish();
			return true;
		}
		return super.onKeyDown(keyCode, event);
	}

	@Override
	public boolean onKeyUp(int keyCode, KeyEvent event) {
		if (isGamepadButton(keyCode)) return true;
		return super.onKeyUp(keyCode, event);
	}

	private boolean isGamepadButton(int keyCode) {
		return (keyCode >= KeyEvent.KEYCODE_BUTTON_A && keyCode <= KeyEvent.KEYCODE_BUTTON_MODE)
			|| keyCode == KeyEvent.KEYCODE_DPAD_UP || keyCode == KeyEvent.KEYCODE_DPAD_DOWN
			|| keyCode == KeyEvent.KEYCODE_DPAD_LEFT || keyCode == KeyEvent.KEYCODE_DPAD_RIGHT;
	}

	private void assignPhysicalToCD32(int physKeycode, int target) {
		// If this physical button was assigned to another CD32 target, swap
		int oldTarget = -1;
		int oldPhys = cd32Map[target];
		for (int c = 0; c < NUM_CD32; c++) {
			if (cd32Map[c] == physKeycode && c != target) {
				oldTarget = c;
				break;
			}
		}
		cd32Map[target] = physKeycode;
		if (oldTarget >= 0 && oldPhys >= 0) {
			cd32Map[oldTarget] = oldPhys; // swap
		} else if (oldTarget >= 0) {
			cd32Map[oldTarget] = -1;
		}

		// Remove from keyboard map if it was there
		for (int i = 0; i < EXTRA_BUTTONS.length; i++) {
			if (EXTRA_BUTTONS[i] == physKeycode) {
				keyMap[i] = -1;
				keyLabels[i].setText(amigaKeyName(-1));
				break;
			}
		}
	}

	private void onCD32ButtonTapped(int target) {
		activeTarget = target;
		String[] names = {"Red", "Blue", "Green", "Yellow", "Play", "L", "R"};
		statusText.setText("Press a button on your controller for " + names[target]);
		statusText.setTextColor(0xFFFFCC00);
		padView.invalidate();
	}

	// ── Helpers ──────────────────────────────────────────────────────────

	static String physButtonName(int keyCode) {
		switch (keyCode) {
			case KeyEvent.KEYCODE_BUTTON_A: return "A";
			case KeyEvent.KEYCODE_BUTTON_B: return "B";
			case KeyEvent.KEYCODE_BUTTON_X: return "X";
			case KeyEvent.KEYCODE_BUTTON_Y: return "Y";
			case KeyEvent.KEYCODE_BUTTON_L1: return "L1";
			case KeyEvent.KEYCODE_BUTTON_R1: return "R1";
			case KeyEvent.KEYCODE_BUTTON_L2: return "L2";
			case KeyEvent.KEYCODE_BUTTON_R2: return "R2";
			case KeyEvent.KEYCODE_BUTTON_START: return "Start";
			case KeyEvent.KEYCODE_BUTTON_SELECT: return "Select";
			case KeyEvent.KEYCODE_BUTTON_THUMBL: return "L3";
			case KeyEvent.KEYCODE_BUTTON_THUMBR: return "R3";
			case KeyEvent.KEYCODE_DPAD_UP: return "D-Up";
			case KeyEvent.KEYCODE_DPAD_DOWN: return "D-Down";
			case KeyEvent.KEYCODE_DPAD_LEFT: return "D-Left";
			case KeyEvent.KEYCODE_DPAD_RIGHT: return "D-Right";
			default: return "Btn" + keyCode;
		}
	}

	static String amigaKeyName(int amigaKeycode) {
		for (int i = 0; i < KEY_CODES.length; i++) {
			if (KEY_CODES[i] == amigaKeycode) return KEY_NAMES[i];
		}
		return "None";
	}

	// Convert Android keycode to SDL3 gamepad button index
	static int androidToSdlButton(int keyCode) {
		switch (keyCode) {
			case KeyEvent.KEYCODE_BUTTON_A: return 0;   // SDL_GAMEPAD_BUTTON_SOUTH
			case KeyEvent.KEYCODE_BUTTON_B: return 1;   // SDL_GAMEPAD_BUTTON_EAST
			case KeyEvent.KEYCODE_BUTTON_X: return 2;   // SDL_GAMEPAD_BUTTON_WEST
			case KeyEvent.KEYCODE_BUTTON_Y: return 3;   // SDL_GAMEPAD_BUTTON_NORTH
			case KeyEvent.KEYCODE_BUTTON_SELECT: return 4; // SDL_GAMEPAD_BUTTON_BACK
			case KeyEvent.KEYCODE_BUTTON_START: return 6;  // SDL_GAMEPAD_BUTTON_START
			case KeyEvent.KEYCODE_BUTTON_THUMBL: return 7; // SDL_GAMEPAD_BUTTON_LEFT_STICK
			case KeyEvent.KEYCODE_BUTTON_THUMBR: return 8; // SDL_GAMEPAD_BUTTON_RIGHT_STICK
			case KeyEvent.KEYCODE_BUTTON_L1: return 9;  // SDL_GAMEPAD_BUTTON_LEFT_SHOULDER
			case KeyEvent.KEYCODE_BUTTON_R1: return 10; // SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER
			default: return -1;
		}
	}

	// ── CD32 Pad custom View ─────────────────────────────────────────────

	private class CD32PadView extends View {
		private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
		private final RectF rect = new RectF();

		// Button hit areas: [centerX_frac, centerY_frac, radius_frac]
		private final float[][] btnPos = {
			{0.66f, 0.68f, 0.085f},  // Red (bottom of diamond)
			{0.82f, 0.50f, 0.085f},  // Blue (right of diamond)
			{0.50f, 0.50f, 0.085f},  // Green (left of diamond)
			{0.66f, 0.32f, 0.085f},  // Yellow (top of diamond)
			{0.66f, 0.88f, 0.065f},  // Play
			{0.18f, 0.12f, 0.080f},  // L shoulder
			{0.82f, 0.12f, 0.080f},  // R shoulder
		};

		private final int[] btnColors = {
			0xFFCC0000, 0xFF0055DD, 0xFF00AA00, 0xFFCCAA00,
			0xFF555566, 0xFF444466, 0xFF444466
		};

		private final String[] btnLabels = {
			"Red", "Blue", "Green", "Yellow", "Play", "L", "R"
		};

		CD32PadView(ControllerMapActivity activity) {
			super(activity);
			setOnTouchListener((v, event) -> {
				if (event.getAction() == MotionEvent.ACTION_DOWN) {
					float xf = event.getX() / getWidth();
					float yf = event.getY() / getHeight();
					for (int i = 0; i < NUM_CD32; i++) {
						float dx = xf - btnPos[i][0];
						float dy = yf - btnPos[i][1];
						float r = btnPos[i][2] * 1.6f;
						if (dx * dx + dy * dy < r * r) {
							onCD32ButtonTapped(i);
							performClick();
							return true;
						}
					}
				}
				return false;
			});
		}

		@Override
		public boolean performClick() {
			return super.performClick();
		}

		@Override
		protected void onDraw(Canvas canvas) {
			int w = getWidth();
			int h = getHeight();
			float d = getResources().getDisplayMetrics().density;

			// Pad body
			paint.setColor(0xFF2A2A3E);
			rect.set(0, 0, w, h);
			canvas.drawRoundRect(rect, 20 * d, 20 * d, paint);

			// Pad outline
			paint.setStyle(Paint.Style.STROKE);
			paint.setStrokeWidth(1.5f * d);
			paint.setColor(0x44FFFFFF);
			canvas.drawRoundRect(rect, 20 * d, 20 * d, paint);
			paint.setStyle(Paint.Style.FILL);

			// D-pad
			float dCx = w * 0.22f, dCy = h * 0.55f;
			float arm = w * 0.085f, armW = w * 0.055f;
			paint.setColor(0xFF333350);
			rect.set(dCx - arm, dCy - armW / 2, dCx + arm, dCy + armW / 2);
			canvas.drawRoundRect(rect, 3 * d, 3 * d, paint);
			rect.set(dCx - armW / 2, dCy - arm, dCx + armW / 2, dCy + arm);
			canvas.drawRoundRect(rect, 3 * d, 3 * d, paint);
			paint.setColor(0xFF444466);
			canvas.drawCircle(dCx, dCy, armW * 0.3f, paint);

			// D-pad label
			paint.setColor(0x88FFFFFF);
			paint.setTextSize(9 * d);
			paint.setTextAlign(Paint.Align.CENTER);
			paint.setTypeface(Typeface.DEFAULT);
			canvas.drawText("D-Pad", dCx, dCy + arm + 14 * d, paint);

			// Draw CD32 buttons
			for (int i = 0; i < NUM_CD32; i++) {
				float cx = btnPos[i][0] * w;
				float cy = btnPos[i][1] * h;
				float r = btnPos[i][2] * w;

				// Active highlight ring
				if (i == activeTarget) {
					paint.setColor(0xFFFFCC00);
					if (i == CD32_RWD || i == CD32_FFW) {
						rect.set(cx - r * 2.0f, cy - r * 1.2f, cx + r * 2.0f, cy + r * 1.2f);
						canvas.drawRoundRect(rect, r, r, paint);
					} else {
						canvas.drawCircle(cx, cy, r + 3 * d, paint);
					}
				}

				// Button shape
				paint.setColor(btnColors[i]);
				if (i == CD32_RWD || i == CD32_FFW) {
					// Pill shape for shoulder buttons
					rect.set(cx - r * 1.8f, cy - r, cx + r * 1.8f, cy + r);
					canvas.drawRoundRect(rect, r, r, paint);
				} else {
					canvas.drawCircle(cx, cy, r, paint);
				}

				// Button label
				paint.setTextAlign(Paint.Align.CENTER);
				paint.setTypeface(Typeface.DEFAULT_BOLD);
				int labelColor = (i == CD32_YELLOW) ? Color.BLACK : Color.WHITE;
				paint.setColor(labelColor);
				paint.setTextSize(r * 0.55f);
				canvas.drawText(btnLabels[i], cx, cy - r * 0.05f, paint);

				// Mapping label (which physical button)
				paint.setTypeface(Typeface.DEFAULT);
				paint.setTextSize(r * 0.48f);
				paint.setColor((i == CD32_YELLOW) ? 0x99000000 : 0xBBFFFFFF);
				String mapLabel = (cd32Map[i] >= 0) ? "← " + physButtonName(cd32Map[i]) : "← ???";
				canvas.drawText(mapLabel, cx, cy + r * 0.5f, paint);
			}
		}
	}
}
