package com.uae4arm2026.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.data.ModPlayer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Old-school Amiga demo-style boot intro: copper bars, a morphing vector shape (triangle ->
 * square -> circle, classic democoding fare), and a sine scroller, in the tradition of Red
 * Sector/Melon Dezign intros. Runs once per cold start (see Uae4ArmApp's nav graph - this is
 * only ever the start destination), then hands off to Configurations either automatically or
 * on tap to skip.
 *
 * The shapes and bars are drawn on a single Canvas driven by one time value advanced via
 * withFrameNanos, rather than several independent animateFloat/InfiniteTransition instances -
 * that keeps every effect locked to the same clock (as real copper/blitter demo effects were,
 * driven off one frame counter). The app's own splash badge is layered on top as a real Image
 * rather than redrawn as text, so it's the actual logo, not a re-creation of it.
 */
private const val SCROLL_TEXT =
	"    WELCOME TO UAE4ARM 2026 ... A CLASSIC AMIGA EMULATOR FOR ANDROID ... " +
		"CODED WITH CARE BY CROWN PARK COMPUTING ... POWERED BY AMIBERRY ... " +
		"GREETINGS TO ALL AMIGA SCENERS PAST AND PRESENT ... ENJOY YOUR SESSION ... "

private val CopperPalette = listOf(
	Color(0xFFFF3B3B), Color(0xFFFF9F1C), Color(0xFFFFD23F), Color(0xFF6BCB77),
	Color(0xFF4D96FF), Color(0xFF9B5DE5), Color(0xFFFF3B3B)
)

/** Seconds each shape holds/morphs before advancing to the next in the cycle. */
private const val MORPH_STEP_SECONDS = 2.2f

@Composable
fun IntroScreen(navController: NavController, onFinished: () -> Unit) {
	var time by remember { mutableFloatStateOf(0f) }
	val context = LocalContext.current

	// Kick off a random bundled tracker tune. Deliberately not stopped when the intro finishes -
	// ModPlayer is a process-wide singleton, so it keeps playing into Configurations and the Mod
	// Player screen picks it up as "already playing" if reopened. Game launches stop it (see
	// EmulatorLauncher.launchSdlActivity) so it never overlaps actual emulated audio.
	LaunchedEffect(Unit) {
		ModPlayer.randomMod(context)?.let { ModPlayer.play(context, it) }
	}

	LaunchedEffect(Unit) {
		var start = -1L
		while (true) {
			val now = withFrameNanos { it }
			if (start < 0L) start = now
			time = (now - start) / 1_000_000_000f
			if (time > 14f) {
				onFinished()
				break
			}
		}
	}

	Box(
		modifier = Modifier
			.fillMaxSize()
			.background(Color.Black)
			.clickable { onFinished() }
	) {
		Canvas(modifier = Modifier.matchParentSize()) {
			drawCopperBars(time)
			drawMorphingShape(time)
			drawScrollText(time)
		}
		// The real splash badge (Boing ball + wordmark baked into the artwork), not a
		// hand-drawn re-creation of the title text.
		Image(
			painter = painterResource(R.mipmap.ic_launcher_foreground),
			contentDescription = "UAE4ARM 2026",
			contentScale = ContentScale.Fit,
			modifier = Modifier
				.align(Alignment.TopCenter)
				.fillMaxWidth(0.42f)
		)
	}
}

private fun DrawScope.drawCopperBars(time: Float) {
	val barCount = CopperPalette.size - 1
	val barHeight = size.height * 0.05f
	val bandSpan = size.height * 0.5f
	val bandTop = size.height * 0.32f

	for (i in 0 until barCount) {
		val phase = time * 1.6f + i * 0.55f
		val y = bandTop + bandSpan * (0.5f + 0.5f * sin(phase))
		val color = CopperPalette[i]
		drawRect(
			brush = Brush.verticalGradient(
				colors = listOf(color.copy(alpha = 0f), color.copy(alpha = 0.85f), color.copy(alpha = 0f)),
				startY = y,
				endY = y + barHeight
			),
			topLeft = Offset(0f, y),
			size = Size(size.width, barHeight)
		)
	}
}

/**
 * Polar radius of a regular N-sided polygon at angle [theta], normalized so its flat edges sit
 * at distance [r] from the center (i.e. [r] is the polygon's apothem, not its corner radius) -
 * that keeps triangle/square/circle visually the same "size" as they morph into each other
 * instead of the corners suddenly jumping outward.
 */
private fun regularPolygonRadius(theta: Float, sides: Int, r: Float): Float {
	val angleStep = (2f * PI.toFloat()) / sides
	val halfStep = angleStep / 2f
	var t = theta % angleStep
	if (t > halfStep) t -= angleStep
	if (t < -halfStep) t += angleStep
	return r / cos(t)
}

/** Triangle -> square -> circle -> triangle, sampled at [samples] angles and cross-faded. */
private fun DrawScope.drawMorphingShape(time: Float) {
	val cx = size.width / 2f
	val cy = size.height * 0.18f
	val baseRadius = min(size.width, size.height) * 0.16f
	val rotation = time * 0.5f

	// Cycle position: 0 = triangle, 1 = square, 2 = circle, then wraps.
	val cyclePos = (time / MORPH_STEP_SECONDS) % 3f
	val shapeIndex = cyclePos.toInt()
	// Ease the blend so the shape holds briefly at each vertex count instead of constantly moving.
	val rawBlend = cyclePos - shapeIndex
	val blend = rawBlend * rawBlend * (3f - 2f * rawBlend) // smoothstep

	fun radiusFor(index: Int, theta: Float): Float = when (index % 3) {
		0 -> regularPolygonRadius(theta, 3, baseRadius)
		1 -> regularPolygonRadius(theta, 4, baseRadius)
		else -> baseRadius
	}

	val samples = 72
	val path = Path()
	for (s in 0..samples) {
		val theta = (2f * PI.toFloat() * s / samples)
		val rA = radiusFor(shapeIndex, theta)
		val rB = radiusFor(shapeIndex + 1, theta)
		val r = rA + (rB - rA) * blend
		val a = theta + rotation
		val x = cx + r * cos(a)
		val y = cy + r * sin(a)
		if (s == 0) path.moveTo(x, y) else path.lineTo(x, y)
	}
	path.close()

	val hue = (time * 50f) % 360f
	drawPath(
		path = path,
		brush = Brush.radialGradient(
			colors = listOf(Color.hsv(hue, 0.55f, 1f), Color.hsv(hue, 0.9f, 0.7f)),
			center = Offset(cx, cy),
			radius = baseRadius * 1.6f
		)
	)
	drawPath(path = path, color = Color.White.copy(alpha = 0.6f), style = androidx.compose.ui.graphics.drawscope.Stroke(width = 3f))
}

private fun DrawScope.drawScrollText(time: Float) {
	val baseY = size.height * 0.72f
	val charWidth = size.width * 0.045f
	val speed = size.width * 0.45f // px/sec
	val totalWidth = SCROLL_TEXT.length * charWidth
	// Offset wraps so the message loops seamlessly.
	val scrollOffset = (time * speed) % totalWidth
	val startX = size.width - scrollOffset

	drawContext.canvas.nativeCanvas.apply {
		val paint = android.graphics.Paint().apply {
			isAntiAlias = true
			textAlign = android.graphics.Paint.Align.CENTER
			textSize = charWidth * 1.4f
			isFakeBoldText = true
		}
		SCROLL_TEXT.forEachIndexed { index, ch ->
			val x = startX + index * charWidth
			if (x < -charWidth || x > size.width + charWidth) return@forEachIndexed
			val wave = sin(time * 3f + index * 0.35f) * (size.height * 0.05f)
			val hue = (index * 6f + time * 40f) % 360f
			paint.color = android.graphics.Color.HSVToColor(floatArrayOf(hue, 0.6f, 1f))
			drawText(ch.toString(), x, baseY + wave, paint)
		}
	}
}
