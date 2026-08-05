package com.uae4arm2026.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.data.ModPlayer

/**
 * Bundled tracker-module playback (see ModPlayer/mod_player_jni.cpp/libopenmpt). Tap a track to
 * play it - the same singleton player the boot intro uses, so whatever's already playing (e.g.
 * from the intro) shows up here already selected.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModPlayerScreen(navController: NavController? = null) {
	val context = LocalContext.current
	val mods = remember { ModPlayer.listAvailableMods(context) }
	val state by ModPlayer.state.collectAsState()

	Scaffold(
		topBar = { TopAppBar(title = { Text(stringResource(R.string.mod_player_title)) }) }
	) { padding ->
		Column(modifier = Modifier.fillMaxSize().padding(padding)) {
			if (state.assetName != null) {
				Surface(
					modifier = Modifier.fillMaxWidth().padding(16.dp),
					tonalElevation = 2.dp,
					shape = MaterialTheme.shapes.medium
				) {
					Row(
						modifier = Modifier.fillMaxWidth().padding(12.dp),
						verticalAlignment = Alignment.CenterVertically
					) {
						Icon(Icons.Default.MusicNote, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
						Spacer(Modifier.width(12.dp))
						Column(modifier = Modifier.weight(1f)) {
							Text(state.title, fontWeight = FontWeight.Bold, maxLines = 1)
							Text(state.assetName ?: "", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
						}
						IconButton(onClick = { ModPlayer.stop() }) {
							Icon(Icons.Default.Stop, contentDescription = stringResource(R.string.action_cancel))
						}
					}
				}
			}

			if (mods.isEmpty()) {
				Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
					Text("No bundled mod music found", color = MaterialTheme.colorScheme.onSurfaceVariant)
				}
			} else {
				LazyColumn(contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
					items(mods, key = { it }) { modName ->
						val isCurrent = state.assetName == modName
						ListItem(
							headlineContent = { Text(modName.removeSuffix(".mod")) },
							leadingContent = {
								Icon(
									if (isCurrent && state.isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
									contentDescription = null,
									tint = if (isCurrent) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
								)
							},
							modifier = Modifier.clickable {
								if (isCurrent) {
									ModPlayer.stop()
								} else {
									ModPlayer.play(context, modName)
								}
							}
						)
						HorizontalDivider()
					}
				}
			}
		}
	}
}
