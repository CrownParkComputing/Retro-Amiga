package com.uae4arm2026;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageButton;
import android.widget.LinearLayout;

public class Uae4ArmVirtualKeyboard extends FrameLayout {
	private static final int AK_ESC = 0x45;
	private static final int AK_F1 = 0x50, AK_F2 = 0x51, AK_F3 = 0x52, AK_F4 = 0x53, AK_F5 = 0x54;
	private static final int AK_F6 = 0x55, AK_F7 = 0x56, AK_F8 = 0x57, AK_F9 = 0x58, AK_F10 = 0x59;
	private static final int AK_BACKQUOTE = 0x00;
	private static final int AK_1 = 0x01, AK_2 = 0x02, AK_3 = 0x03, AK_4 = 0x04, AK_5 = 0x05;
	private static final int AK_6 = 0x06, AK_7 = 0x07, AK_8 = 0x08, AK_9 = 0x09, AK_0 = 0x0A;
	private static final int AK_MINUS = 0x0B, AK_EQUAL = 0x0C, AK_BACKSLASH = 0x0D, AK_BS = 0x41;
	private static final int AK_TAB = 0x42;
	private static final int AK_Q = 0x10, AK_W = 0x11, AK_E = 0x12, AK_R = 0x13, AK_T = 0x14;
	private static final int AK_Y = 0x15, AK_U = 0x16, AK_I = 0x17, AK_O = 0x18, AK_P = 0x19;
	private static final int AK_LBRACKET = 0x1A, AK_RBRACKET = 0x1B;
	private static final int AK_CTRL = 0x63, AK_CAPSLOCK = 0x62;
	private static final int AK_A = 0x20, AK_S = 0x21, AK_D = 0x22, AK_F = 0x23, AK_G = 0x24;
	private static final int AK_H = 0x25, AK_J = 0x26, AK_K = 0x27, AK_L = 0x28;
	private static final int AK_SEMICOLON = 0x29, AK_QUOTE = 0x2A, AK_NUMBERSIGN = 0x2B, AK_RET = 0x44;
	private static final int AK_LSH = 0x60, AK_LTGT = 0x30;
	private static final int AK_Z = 0x31, AK_X = 0x32, AK_C = 0x33, AK_V = 0x34, AK_B = 0x35;
	private static final int AK_N = 0x36, AK_M = 0x37, AK_COMMA = 0x38, AK_PERIOD = 0x39, AK_SLASH = 0x3A;
	private static final int AK_RSH = 0x61;
	private static final int AK_LALT = 0x64, AK_LAMI = 0x66, AK_SPC = 0x40, AK_RAMI = 0x67, AK_RALT = 0x65;
	private static final int AK_UP = 0x4C, AK_DN = 0x4D, AK_LF = 0x4F, AK_RT = 0x4E;
	private static final int AK_DEL = 0x46, AK_HELP = 0x5F;

	private static final Object[][][] ROWS = {
		{{"Esc", AK_ESC, 1.0f}, {"F1", AK_F1, 1.0f}, {"F2", AK_F2, 1.0f}, {"F3", AK_F3, 1.0f},
			{"F4", AK_F4, 1.0f}, {"F5", AK_F5, 1.0f}, {"F6", AK_F6, 1.0f}, {"F7", AK_F7, 1.0f},
			{"F8", AK_F8, 1.0f}, {"F9", AK_F9, 1.0f}, {"F10", AK_F10, 1.0f}, {"Help", AK_HELP, 1.0f}, {"Del", AK_DEL, 1.0f}},
		{{"`", AK_BACKQUOTE, 1.0f}, {"1", AK_1, 1.0f}, {"2", AK_2, 1.0f}, {"3", AK_3, 1.0f},
			{"4", AK_4, 1.0f}, {"5", AK_5, 1.0f}, {"6", AK_6, 1.0f}, {"7", AK_7, 1.0f},
			{"8", AK_8, 1.0f}, {"9", AK_9, 1.0f}, {"0", AK_0, 1.0f}, {"-", AK_MINUS, 1.0f},
			{"=", AK_EQUAL, 1.0f}, {"\\", AK_BACKSLASH, 1.0f}, {"\u232B", AK_BS, 1.2f}},
		{{"Tab", AK_TAB, 1.4f}, {"Q", AK_Q, 1.0f}, {"W", AK_W, 1.0f}, {"E", AK_E, 1.0f},
			{"R", AK_R, 1.0f}, {"T", AK_T, 1.0f}, {"Y", AK_Y, 1.0f}, {"U", AK_U, 1.0f},
			{"I", AK_I, 1.0f}, {"O", AK_O, 1.0f}, {"P", AK_P, 1.0f}, {"[", AK_LBRACKET, 1.0f},
			{"]", AK_RBRACKET, 1.0f}},
		{{"Ctrl", AK_CTRL, 1.3f}, {"Caps", AK_CAPSLOCK, 1.2f}, {"A", AK_A, 1.0f}, {"S", AK_S, 1.0f},
			{"D", AK_D, 1.0f}, {"F", AK_F, 1.0f}, {"G", AK_G, 1.0f}, {"H", AK_H, 1.0f},
			{"J", AK_J, 1.0f}, {"K", AK_K, 1.0f}, {"L", AK_L, 1.0f}, {";", AK_SEMICOLON, 1.0f},
			{"'", AK_QUOTE, 1.0f}, {"Ret", AK_RET, 1.5f}},
		{{"Shft", AK_LSH, 1.5f}, {"<>", AK_LTGT, 1.0f}, {"Z", AK_Z, 1.0f}, {"X", AK_X, 1.0f},
			{"C", AK_C, 1.0f}, {"V", AK_V, 1.0f}, {"B", AK_B, 1.0f}, {"N", AK_N, 1.0f},
			{"M", AK_M, 1.0f}, {",", AK_COMMA, 1.0f}, {".", AK_PERIOD, 1.0f}, {"/", AK_SLASH, 1.0f},
			{"Shft", AK_RSH, 1.3f}, {"\u25B2", AK_UP, 1.0f}},
		{{"Alt", AK_LALT, 1.3f}, {"A\u25C0", AK_LAMI, 1.2f}, {" ", AK_SPC, 5.0f},
			{"A\u25B6", AK_RAMI, 1.2f}, {"Alt", AK_RALT, 1.3f},
			{"\u25C0", AK_LF, 1.0f}, {"\u25BC", AK_DN, 1.0f}, {"\u25B6", AK_RT, 1.0f}},
	};

	private boolean shiftActive = false;
	private boolean ctrlActive = false;
	private boolean altActive = false;
	private boolean visible = false;

	public Uae4ArmVirtualKeyboard(Context context) {
		super(context);
		setVisibility(View.GONE);
		buildKeyboard(context);
	}

	private void buildKeyboard(Context context) {
		float density = context.getResources().getDisplayMetrics().density;

		LinearLayout container = new LinearLayout(context);
		container.setOrientation(LinearLayout.VERTICAL);
		container.setGravity(Gravity.CENTER_HORIZONTAL);

		GradientDrawable background = new GradientDrawable();
		background.setColor(0xDD1A1A1A);
		background.setCornerRadii(new float[]{12 * density, 12 * density, 12 * density, 12 * density, 0, 0, 0, 0});
		container.setBackground(background);
		container.setPadding((int) (4 * density), (int) (6 * density), (int) (4 * density), (int) (4 * density));

		LinearLayout header = new LinearLayout(context);
		header.setOrientation(LinearLayout.HORIZONTAL);
		header.setGravity(Gravity.END | Gravity.CENTER_VERTICAL);

		ImageButton closeButton = new ImageButton(context);
		closeButton.setImageResource(android.R.drawable.ic_menu_close_clear_cancel);
		closeButton.setBackgroundColor(0x00000000);
		closeButton.setColorFilter(0xFFEEEEEE);
		closeButton.setContentDescription("Close keyboard");
		closeButton.setOnClickListener(v -> hide());

		LinearLayout.LayoutParams closeParams = new LinearLayout.LayoutParams((int) (36 * density), (int) (36 * density));
		header.addView(closeButton, closeParams);
		container.addView(header, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

		HorizontalScrollView scroller = new HorizontalScrollView(context);
		scroller.setFillViewport(true);
		scroller.setHorizontalScrollBarEnabled(false);

		LinearLayout scrollContent = new LinearLayout(context);
		scrollContent.setOrientation(LinearLayout.VERTICAL);
		scrollContent.setGravity(Gravity.CENTER_HORIZONTAL);

		for (Object[][] row : ROWS) {
			LinearLayout rowLayout = new LinearLayout(context);
			rowLayout.setOrientation(LinearLayout.HORIZONTAL);
			rowLayout.setGravity(Gravity.CENTER_HORIZONTAL);

			LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
			rowParams.topMargin = (int) density;

			for (Object[] key : row) {
				String label = (String) key[0];
				int code = (Integer) key[1];
				float relativeWidth = (Float) key[2];

				Button button = new Button(context);
				button.setText(label);
				button.setAllCaps(false);
				button.setTextColor(0xFFEEEEEE);
				button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
				button.setIncludeFontPadding(false);
				button.setMinHeight(0);
				button.setMinimumHeight(0);
				button.setMinWidth(0);
				button.setMinimumWidth(0);

				int keyWidth = (int) (relativeWidth * 34 * density);
				int keyHeight = (int) (31 * density);
				button.setPadding((int) (2 * density), (int) density, (int) (2 * density), (int) density);

				GradientDrawable keyBackground = new GradientDrawable();
				keyBackground.setColor(0xFF333333);
				keyBackground.setCornerRadius(4 * density);
				keyBackground.setStroke(1, 0xFF555555);
				button.setBackground(keyBackground);

				LinearLayout.LayoutParams keyParams = new LinearLayout.LayoutParams(keyWidth, keyHeight);
				keyParams.setMargins((int) density, 0, (int) density, 0);

				boolean isModifier = code == AK_LSH || code == AK_RSH || code == AK_CTRL || code == AK_CAPSLOCK
					|| code == AK_LALT || code == AK_RALT || code == AK_LAMI || code == AK_RAMI;

				button.setOnTouchListener((view, event) -> {
					int action = event.getActionMasked();
					if (isModifier) {
						if (action == MotionEvent.ACTION_DOWN) {
							handleModifierToggle(code, button);
						}
					} else {
						if (action == MotionEvent.ACTION_DOWN) {
							sendKey(code, 1);
							highlightKey(button, true);
						} else if (action == MotionEvent.ACTION_UP || action == MotionEvent.ACTION_CANCEL) {
							sendKey(code, 0);
							highlightKey(button, false);
							releaseAllModifiers();
						}
					}
					return true;
				});

				rowLayout.addView(button, keyParams);
			}

			scrollContent.addView(rowLayout, rowParams);
		}

		scroller.addView(scrollContent);
		container.addView(scroller);

		FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
		params.gravity = Gravity.BOTTOM;
		addView(container, params);
	}

	private void handleModifierToggle(int code, Button button) {
		boolean nowActive;
		switch (code) {
			case AK_LSH:
			case AK_RSH:
				shiftActive = !shiftActive;
				nowActive = shiftActive;
				break;
			case AK_CTRL:
				ctrlActive = !ctrlActive;
				nowActive = ctrlActive;
				break;
			case AK_LALT:
			case AK_RALT:
				altActive = !altActive;
				nowActive = altActive;
				break;
			case AK_CAPSLOCK:
			case AK_LAMI:
			case AK_RAMI:
				sendKey(code, 1);
				button.postDelayed(() -> sendKey(code, 0), 100);
				return;
			default:
				return;
		}
		sendKey(code, nowActive ? 1 : 0);
		highlightModifier(button, nowActive);
	}

	private void releaseAllModifiers() {
		if (shiftActive) {
			shiftActive = false;
			sendKey(AK_LSH, 0);
			sendKey(AK_RSH, 0);
		}
		if (ctrlActive) {
			ctrlActive = false;
			sendKey(AK_CTRL, 0);
		}
		if (altActive) {
			altActive = false;
			sendKey(AK_LALT, 0);
			sendKey(AK_RALT, 0);
		}
	}

	private void highlightKey(Button button, boolean pressed) {
		try {
			GradientDrawable background = (GradientDrawable) button.getBackground();
			background.setColor(pressed ? 0xFF1565C0 : 0xFF333333);
		} catch (Throwable ignored) {
		}
	}

	private void highlightModifier(Button button, boolean active) {
		try {
			GradientDrawable background = (GradientDrawable) button.getBackground();
			background.setColor(active ? 0xFF4CAF50 : 0xFF333333);
		} catch (Throwable ignored) {
		}
	}

	private void sendKey(int keycode, int pressed) {
		try {
			Uae4ArmEmulatorActivity.nativeSendAmigaKey(keycode, pressed);
		} catch (Throwable ignored) {
		}
	}

	public void toggle() {
		visible = !visible;
		setVisibility(visible ? View.VISIBLE : View.GONE);
	}

	public void hide() {
		visible = false;
		releaseAllModifiers();
		setVisibility(View.GONE);
	}

	public boolean isKeyboardVisible() {
		return visible;
	}
}