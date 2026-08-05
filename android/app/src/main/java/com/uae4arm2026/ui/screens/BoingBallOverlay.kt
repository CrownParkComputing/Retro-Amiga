package com.uae4arm2026.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.uae4arm2026.data.ModPlayer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The Amiga "Boing" ball bouncing behind the launcher, plus a graphic EQ driven by the actual
 * audio coming out of ModPlayer (see ModPlayer.levels - real FFT bands, not a canned animation).
 *
 * Drawn as a non-interactive backdrop: the caller stacks this behind the real UI in a Box, and
 * everything here is pure Canvas with no hit-testing, so taps still land on the content above.
 * One withFrameNanos clock drives the physics, matching IntroScreen's approach.
 */
/** Mutable ball physics state, integrated per frame so travel direction is actually known. */
private class BallState {
	// Position/velocity are kept in normalised 0..1 space so they survive rotation/resize without
	// the ball jumping or escaping the new bounds.
	var x = 0.35f
	var y = 0.30f
	var vx = 0.21f   // fraction of the screen per second
	var vy = 0.17f

	// Orientation as a full 3x3 rotation matrix, updated by composing a small incremental
	// rotation each frame. Storing a single accumulated angle about "the current axis" (as this
	// did before) makes the texture visibly jump every time the axis changes - i.e. on every
	// bounce and every tap - because the same angle suddenly means a rotation about a different
	// axis. Composing increments keeps orientation continuous no matter how the axis moves.
	var m = floatArrayOf(
		1f, 0f, 0f,
		0f, 1f, 0f,
		0f, 0f, 1f
	)

	/** Compose a rotation of [angle] radians about the in-plane unit axis ([ax], [ay], 0). */
	fun rotateBy(ax: Float, ay: Float, angle: Float) {
		val c = cos(angle)
		val s = sin(angle)
		val t = 1f - c
		// Rodrigues as a matrix, with az == 0.
		val r = floatArrayOf(
			t * ax * ax + c, t * ax * ay, ay * s,
			t * ax * ay, t * ay * ay + c, -ax * s,
			-ay * s, ax * s, c
		)
		val out = FloatArray(9)
		for (row in 0..2) {
			for (col in 0..2) {
				var sum = 0f
				for (k in 0..2) sum += r[row * 3 + k] * m[k * 3 + col]
				out[row * 3 + col] = sum
			}
		}
		m = out
	}
}

@Composable
fun BoingBallOverlay(modifier: Modifier = Modifier) {
	val levels by ModPlayer.levels.collectAsState()
	val ball = remember { BallState() }
	// Bumped on each physics step purely to trigger recomposition of the Canvas.
	var tick by remember { mutableFloatStateOf(0f) }

	LaunchedEffect(Unit) {
		var last = -1L
		while (true) {
			val now = withFrameNanos { it }
			if (last < 0L) last = now
			// Clamp dt so a dropped frame / backgrounding can't teleport the ball through a wall.
			val dt = ((now - last) / 1_000_000_000f).coerceIn(0f, 0.05f)
			last = now

			ball.x += ball.vx * dt
			ball.y += ball.vy * dt
			// Reflect off each edge. Margin is in normalised space and matches the radius fraction
			// used when drawing, so the ball touches the edges rather than clipping through them.
			val m = BALL_RADIUS_FRACTION
			if (ball.x < m) { ball.x = m; ball.vx = abs(ball.vx) }
			if (ball.x > 1f - m) { ball.x = 1f - m; ball.vx = -abs(ball.vx) }
			if (ball.y < m) { ball.y = m; ball.vy = abs(ball.vy) }
			if (ball.y > 1f - m) { ball.y = 1f - m; ball.vy = -abs(ball.vy) }

			// Roll like a ball on a surface seen from above: the rotation axis is perpendicular to
			// the direction of travel (screen-normal x velocity), so the checkers visibly travel
			// across the face the same way the ball is heading, in ANY direction - not just the
			// horizontal-only wheel spin this used to do. Applied as an incremental composition so
			// direction changes never snap the pattern (see BallState.rotateBy).
			val speed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy)
			if (speed > 1e-4f) {
				ball.rotateBy(-ball.vy / speed, ball.vx / speed, speed * dt * 9f)
			}

			tick += dt
		}
	}

	Canvas(
		modifier = modifier
			.fillMaxSize()
			// Tapping the ball kicks it away from the touch point. This overlay sits BEHIND the
			// real UI in the parent Box, so Compose offers touches to the content first - taps on
			// cards/buttons still work, and only presses landing on empty background reach here.
			.pointerInput(Unit) {
				detectTapGestures { offset ->
					val w = size.width.toFloat()
					val h = size.height.toFloat()
					if (w <= 0f || h <= 0f) return@detectTapGestures
					val radiusPx = min(w, h) * BALL_RADIUS_FRACTION
					val dx = offset.x - ball.x * w
					val dy = offset.y - ball.y * h
					val dist = sqrt(dx * dx + dy * dy)
					if (dist > radiusPx) return@detectTapGestures

					// Kick along the touch->centre vector so it always moves away from the finger.
					// Falls back to a fixed direction for a dead-centre tap where that vector is zero.
					val speed = sqrt(ball.vx * ball.vx + ball.vy * ball.vy).coerceAtLeast(0.18f)
					val boosted = (speed * 1.35f).coerceAtMost(0.9f)
					if (dist > 1e-3f) {
						ball.vx = -dx / dist * boosted
						ball.vy = -dy / dist * boosted
					} else {
						ball.vx = boosted
						ball.vy = -boosted
					}
				}
			}
	) {
		@Suppress("UNUSED_EXPRESSION") tick // read so this Canvas recomposes each frame
		drawBoingBall(ball)
		drawGraphicEq(levels)
	}
}

/** Ball radius as a fraction of the smaller screen dimension (also the bounce margin). */
private const val BALL_RADIUS_FRACTION = 0.18f

private fun DrawScope.drawBoingBall(ball: BallState) {
	val radius = min(size.width, size.height) * BALL_RADIUS_FRACTION
	// Constant-speed travel with hard reflections at every edge - no gravity easing, matching the
	// original Boing demo. Physics runs in normalised space (see BallState), so it bounces around
	// the whole screen regardless of aspect/rotation.
	val cx = ball.x * size.width
	val cy = ball.y * size.height
	val center = Offset(cx, cy)

	// Soft contact shadow so the ball reads as being in front of the content behind it.
	drawCircle(
		color = Color.Black.copy(alpha = 0.18f),
		radius = radius * 1.02f,
		center = Offset(cx + radius * 0.12f, cy + radius * 0.12f)
	)

	// Checkerboard sphere. Each lat/lon quad's corners are unit vectors rotated by the ball's
	// current roll (Rodrigues, about the in-plane axis perpendicular to travel) and then
	// orthographically projected. Rotating the geometry - rather than just offsetting the
	// longitude as before - is what lets the checkers travel in the ball's actual direction of
	// motion instead of only spinning horizontally like a wheel.
	val latBands = 10
	val lonBands = 10
	val m = ball.m

	/** Apply the ball's accumulated orientation matrix to a unit vector. */
	fun rotate(vx: Float, vy: Float, vz: Float): Triple<Float, Float, Float> = Triple(
		m[0] * vx + m[1] * vy + m[2] * vz,
		m[3] * vx + m[4] * vy + m[5] * vz,
		m[6] * vx + m[7] * vy + m[8] * vz
	)

	for (lat in 0 until latBands) {
		val t0 = PI.toFloat() * lat / latBands
		val t1 = PI.toFloat() * (lat + 1) / latBands
		for (lon in 0 until lonBands) {
			val p0 = 2f * PI.toFloat() * lon / lonBands
			val p1 = 2f * PI.toFloat() * (lon + 1) / lonBands

			val corners = listOf(t0 to p0, t0 to p1, t1 to p1, t1 to p0)
			val projected = corners.map { (theta, phi) ->
				rotate(sin(theta) * sin(phi), -cos(theta), sin(theta) * cos(phi))
			}
			// Skip quads on the far side (+z points at the viewer after rotation).
			if (projected.all { it.third <= 0f }) continue

			val path = Path()
			projected.forEachIndexed { index, (rx, ry, _) ->
				val x = cx + radius * rx
				val y = cy + radius * ry
				if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
			}
			path.close()
			val isRed = (lat + lon) % 2 == 0
			drawPath(path, color = if (isRed) Color(0xFFD32F2F) else Color(0xFFF5F5F5))
		}
	}

	// Rim + specular highlight to round the flat quads off into a sphere.
	drawCircle(color = Color.Black.copy(alpha = 0.35f), radius = radius, center = center, style = androidx.compose.ui.graphics.drawscope.Stroke(width = 2f))
	drawCircle(
		color = Color.White.copy(alpha = 0.22f),
		radius = radius * 0.28f,
		center = Offset(cx - radius * 0.35f, cy - radius * 0.4f)
	)
}

private fun DrawScope.drawGraphicEq(levels: FloatArray) {
	if (levels.isEmpty()) return
	val baseline = size.height * 0.97f
	val maxBarHeight = size.height * 0.30f
	val slotWidth = size.width / levels.size
	val barWidth = slotWidth * 0.62f
	val gap = (slotWidth - barWidth) / 2f

	levels.forEachIndexed { index, level ->
		val h = (level.coerceIn(0f, 1f)) * maxBarHeight
		if (h <= 1f) return@forEachIndexed
		val left = index * slotWidth + gap
		// Green -> amber -> red up the bar, classic hardware-EQ colouring.
		val hue = 120f - 120f * (h / maxBarHeight).coerceIn(0f, 1f)
		drawRect(
			color = Color.hsv(hue, 0.75f, 1f, alpha = 0.55f),
			topLeft = Offset(left, baseline - h),
			size = Size(barWidth, h)
		)
	}
}
