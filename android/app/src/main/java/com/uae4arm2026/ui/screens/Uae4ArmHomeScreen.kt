package com.uae4arm2026.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.ui.navigation.Screen

// ── Palette ──────────────────────────────────────────────────────────────────
private val BgScreen         = Color(0xFF1a1a2e)
private val TextPrimary      = Color(0xFFFFFFFF)
private val TextSecondary    = Color(0xFFAAAAAA)
private val AccentColor      = Color(0xFF1565C0)
private val BorderSubtle     = Color(0x33FFFFFF)

@Composable
fun Uae4ArmHomeScreen(navController: NavController? = null) {
	Box(
		modifier = Modifier
			.fillMaxSize()
			.background(BgScreen)
			.statusBarsPadding()
	) {
		Column(
			modifier = Modifier
				.fillMaxSize()
				.padding(horizontal = 20.dp, vertical = 12.dp),
			horizontalAlignment = Alignment.CenterHorizontally,
			verticalArrangement = Arrangement.SpaceBetween
		) {
			// Top: Brand
			Column(horizontalAlignment = Alignment.CenterHorizontally) {
				Image(
					painter = painterResource(R.drawable.featured_default),
					contentDescription = "UAE4ARM",
					contentScale = ContentScale.Fit,
					modifier = Modifier.height(60.dp)
				)
				Text(
					text = "UAE4ARM 2026",
					style = MaterialTheme.typography.titleLarge,
					color = TextPrimary,
					fontWeight = FontWeight.Bold
				)
				Text(
					text = "Powered by Copperline",
					fontSize = 10.sp,
					color = AccentColor,
					fontWeight = FontWeight.Medium
				)
			}

			// Middle: Launch Primary Action
			Button(
				onClick = { navController?.navigate(Screen.Configurations.route) },
				modifier = Modifier
					.fillMaxWidth()
					.height(56.dp),
				colors = ButtonDefaults.buttonColors(containerColor = AccentColor),
				shape = RoundedCornerShape(10.dp)
			) {
				Icon(Icons.Default.PlayCircle, contentDescription = null, modifier = Modifier.size(24.dp))
				Spacer(Modifier.width(12.dp))
				Text("Launch Saved System", fontSize = 16.sp, fontWeight = FontWeight.Bold)
			}

			// Grid Area
			Column(modifier = Modifier.fillMaxWidth()) {
				Text(
					text = "Create New Configuration",
					color = TextSecondary,
					fontSize = 11.sp,
					fontWeight = FontWeight.Bold,
					modifier = Modifier.padding(bottom = 8.dp)
				)
				
				// 3x2 Grid for 6 options
				val gridModifier = Modifier.weight(1f)
				Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
					WizardCard(gridModifier, "ADF", Icons.Default.SdStorage) { navController?.navigate(Screen.GuidedConfig.createRoute("adf")) }
					WizardCard(gridModifier, "CD32", Icons.Default.Album) { navController?.navigate(Screen.GuidedConfig.createRoute("cd32")) }
					WizardCard(gridModifier, "HDF", Icons.Default.Dns) { navController?.navigate(Screen.GuidedConfig.createRoute("hdf")) }
				}
				Spacer(Modifier.height(6.dp))
				Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
					WizardCard(gridModifier, "WHDLoad", Icons.Default.Archive) { navController?.navigate(Screen.GuidedConfig.createRoute("whdload")) }
					WizardCard(gridModifier, "AGS", Icons.Default.AutoAwesome) { navController?.navigate(Screen.GuidedConfig.createRoute("ags")) }
					WizardCard(gridModifier, "Custom", Icons.Default.Build) { navController?.navigate(Screen.GuidedConfig.createRoute("custom")) }
				}
			}

			// Bottom: Tools Row
			Row(
				modifier = Modifier.fillMaxWidth(),
				horizontalArrangement = Arrangement.SpaceEvenly,
				verticalAlignment = Alignment.CenterVertically
			) {
				ToolIconButton(Icons.Default.Folder, "Files") { navController?.navigate(Screen.FileManager.route) }
				ToolIconButton(Icons.Default.Settings, "Settings") { navController?.navigate(Screen.AppSettings.route) }
				ToolIconButton(Icons.Default.Replay, "Rerun Setup") { navController?.navigate(Screen.Onboarding.route) }
			}
		}
	}
}

@Composable
private fun WizardCard(
	modifier: Modifier = Modifier,
	label: String,
	icon: ImageVector,
	onClick: () -> Unit
) {
	Surface(
		onClick = onClick,
		modifier = modifier.height(64.dp),
		shape = RoundedCornerShape(8.dp),
		color = Color(0x14FFFFFF),
		border = androidx.compose.foundation.BorderStroke(1.dp, BorderSubtle)
	) {
		Column(
			modifier = Modifier.fillMaxSize(),
			horizontalAlignment = Alignment.CenterHorizontally,
			verticalArrangement = Arrangement.Center
		) {
			Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(24.dp))
			Spacer(Modifier.height(4.dp))
			Text(label, color = TextPrimary, fontSize = 10.sp, fontWeight = FontWeight.Bold)
		}
	}
}

@Composable
private fun ToolIconButton(
	icon: ImageVector,
	label: String,
	onClick: () -> Unit
) {
	Column(
		horizontalAlignment = Alignment.CenterHorizontally,
		modifier = Modifier
			.clip(RoundedCornerShape(6.dp))
			.clickable(onClick = onClick)
			.padding(4.dp)
	) {
		Icon(icon, contentDescription = label, tint = TextSecondary, modifier = Modifier.size(20.dp))
		Spacer(Modifier.height(2.dp))
		Text(label, color = TextSecondary, fontSize = 9.sp)
	}
}
