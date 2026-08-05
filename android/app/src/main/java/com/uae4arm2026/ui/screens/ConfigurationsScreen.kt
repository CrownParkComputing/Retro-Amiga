package com.uae4arm2026.ui.screens

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items as lazyRowItems
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.uae4arm2026.R
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.ConfigCategory
import com.uae4arm2026.data.ConfigInfo
import com.uae4arm2026.data.EmulatorLauncher
import com.uae4arm2026.data.ModPlayer
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.ui.dpadFocusIndicator
import com.uae4arm2026.ui.findActivity
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.viewmodel.ConfigurationsViewModel
import com.uae4arm2026.ui.viewmodel.SettingsViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConfigurationsScreen(
	viewModel: ConfigurationsViewModel = viewModel(),
	settingsViewModel: SettingsViewModel = viewModel(LocalContext.current.findActivity() as androidx.activity.ComponentActivity),
	navController: NavController
) {
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val snackbarHostState = remember { SnackbarHostState() }
	val appPrefs = remember { AppPreferences.getInstance(context) }
	val showBoingBall by appPrefs.showBoingBall
	val configs by viewModel.configs.collectAsState()
	var selectedCategory by remember { mutableStateOf(ConfigCategory.entries.first()) }
	var selectedMachine by remember { mutableStateOf<AmigaModel?>(null) }
	var showAddSheet by remember { mutableStateOf(false) }

	val categoryConfigs = remember(configs, selectedCategory) {
		configs.filter { it.category == selectedCategory }
	}
	// Only offer machines that actually have a config in this category - no point showing an
	// A4000 chip when every saved ADF config happens to be an A500.
	val availableMachines = remember(categoryConfigs) {
		categoryConfigs.map { it.model }.distinct().sortedBy { it.displayName }
	}
	// The selected machine only applies within its own category; switching category or losing
	// the machine from the list (e.g. its config got deleted) falls back to "All".
	LaunchedEffect(availableMachines) {
		if (selectedMachine != null && selectedMachine !in availableMachines) {
			selectedMachine = null
		}
	}
	val filteredConfigs = remember(categoryConfigs, selectedMachine) {
		val machine = selectedMachine
		if (machine == null) categoryConfigs else categoryConfigs.filter { it.model == machine }
	}

	val loadFailedMessage = stringResource(R.string.msg_failed_load_config)
	val deletedMessage = stringResource(R.string.msg_config_deleted)
	val deleteFailedMessage = stringResource(R.string.msg_failed_delete_config)
	val duplicateFailedMessage = stringResource(R.string.msg_failed_duplicate_config)
	val shareFailedMessage = stringResource(R.string.msg_failed_share_config)

	LaunchedEffect(Unit) {
		viewModel.refresh()
	}

	// Music plays by default on the launcher screen. Only kicks off when nothing is already
	// playing, so returning here doesn't cut off (or restart) whatever the boot intro or the Mod
	// Player screen started - and playback is stopped again when the app leaves the foreground
	// (MainActivity.onStop) or a game launches (EmulatorLauncher).
	LaunchedEffect(Unit) {
		if (ModPlayer.state.value.assetName == null) {
			ModPlayer.randomMod(context)?.let { ModPlayer.play(context, it) }
		}
	}

	Scaffold(
		snackbarHost = { SnackbarHost(snackbarHostState) },
		containerColor = Color.Transparent,
		topBar = {
			// Both filter rows share one line: categories left, machines right. Each is its own
			// scrollable row, so a long list on either side scrolls independently rather than
			// pushing the other off-screen.
			Row(
				modifier = Modifier
					.fillMaxWidth()
					.statusBarsPadding()
					.padding(horizontal = 8.dp),
				verticalAlignment = Alignment.CenterVertically
			) {
				CategoryFilterBar(
					modifier = Modifier.weight(1f),
					selected = selectedCategory,
					onSelect = { selectedCategory = it }
				)
				if (availableMachines.size > 1) {
					MachineFilterBar(
						modifier = Modifier.weight(1f),
						machines = availableMachines,
						selected = selectedMachine,
						onSelect = { selectedMachine = it }
					)
				}
			}
		},
		floatingActionButton = {
			// Utility icons stack directly above the + button rather than living in a bottom bar:
			// no full-width bar means nothing reserves a strip at the bottom of the screen, so the
			// Boing ball and the graphic EQ get the whole area to play with.
			//
			// navigationBarsPadding is essential here: the app draws edge-to-edge, and with the
			// bottomBar gone nothing else supplies that inset - the + button sat directly on top
			// of the system gesture/navigation bar, so presses hit the phone's launcher gestures
			// instead of our buttons.
			Column(
				modifier = Modifier.navigationBarsPadding(),
				horizontalAlignment = Alignment.CenterHorizontally
			) {
				val iconTint = MaterialTheme.colorScheme.primary
				IconButton(onClick = { navController.navigate(Screen.FileManager.route) }) {
					Icon(Icons.Default.Folder, contentDescription = stringResource(R.string.file_manager_title), tint = iconTint)
				}
				IconButton(onClick = { navController.navigate(Screen.Settings.route) }) {
					Icon(Icons.Default.SportsEsports, contentDescription = stringResource(R.string.settings_title), tint = iconTint)
				}
				IconButton(onClick = { navController.navigate(Screen.AppSettings.route) }) {
					Icon(Icons.Default.Settings, contentDescription = stringResource(R.string.settings_title), tint = iconTint)
				}
				IconButton(onClick = { navController.navigate(Screen.ModPlayer.route) }) {
					Icon(Icons.Default.MusicNote, contentDescription = stringResource(R.string.mod_player_title), tint = iconTint)
				}
				IconButton(onClick = { appPrefs.setShowBoingBall(!showBoingBall) }) {
					Icon(
						if (showBoingBall) Icons.Default.Visibility else Icons.Default.VisibilityOff,
						contentDescription = stringResource(R.string.toggle_boing_ball),
						tint = iconTint
					)
				}
				Spacer(Modifier.height(8.dp))
				FloatingActionButton(onClick = { showAddSheet = true }) {
					Icon(Icons.Default.Add, contentDescription = stringResource(R.string.configurations_add_new))
				}
			}
		}
	) { innerPadding ->
		// Boing ball + graphic EQ sit BEHIND the content (drawn first in the Box), so the cards
		// stay fully interactive. Deliberately NOT inset by innerPadding: the ball should bounce
		// around the whole screen, including behind the top bar, rather than being boxed into the
		// content area.
		if (showBoingBall) {
			BoingBallOverlay(modifier = Modifier.fillMaxSize())
		}
		Column(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
			if (filteredConfigs.isEmpty()) {
				Box(
					modifier = Modifier
						.fillMaxSize()
						.padding(32.dp),
					contentAlignment = Alignment.Center
				) {
					Column(horizontalAlignment = Alignment.CenterHorizontally) {
						Text(stringResource(R.string.configurations_empty_title), style = MaterialTheme.typography.bodyLarge)
						Spacer(modifier = Modifier.height(8.dp))
						Text(
							stringResource(R.string.configurations_empty_message),
							style = MaterialTheme.typography.bodySmall,
							color = MaterialTheme.colorScheme.onSurfaceVariant
						)
						Spacer(modifier = Modifier.height(24.dp))
						Button(onClick = { showAddSheet = true }) {
							Text("Start Guided Setup")
						}
					}
				}
			} else {
				LazyVerticalGrid(
					columns = GridCells.Adaptive(minSize = 148.dp),
					contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
					horizontalArrangement = Arrangement.spacedBy(10.dp),
					verticalArrangement = Arrangement.spacedBy(10.dp)
				) {
					items(filteredConfigs, key = { it.path }) { config ->
							ConfigCard(
								config = config,
								scope = scope,
								snackbarHostState = snackbarHostState,
								onLoad = {
									scope.launch {
										runCatching { viewModel.loadConfig(config.path) }
											.onSuccess { parsedConfig ->
												settingsViewModel.loadConfig(parsedConfig, config.name)
												navController.navigate(Screen.GuidedConfig.createRoute("edit")) {
													popUpTo(Screen.Configurations.route) { inclusive = false }
												}
											}
											.onFailure {
												snackbarHostState.showSnackbar(loadFailedMessage)
											}
									}
								},
								onDelete = {
									scope.launch {
										val deleted = viewModel.deleteConfig(config.path)
										snackbarHostState.showSnackbar(
											if (deleted) deletedMessage else deleteFailedMessage
										)
									}
								},
								onDuplicate = {
									scope.launch {
										val result = viewModel.duplicateConfig(config.path)
										val message = result.fold(
											onSuccess = { context.getString(R.string.msg_config_duplicated_as, it.nameWithoutExtension) },
											onFailure = { duplicateFailedMessage }
										)
										snackbarHostState.showSnackbar(message)
									}
								},
								onShare = {
									val file = java.io.File(config.path)
									if (file.exists()) {
										try {
											val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
											val shareIntent = Intent(Intent.ACTION_SEND).apply {
												type = "application/octet-stream"
												putExtra(Intent.EXTRA_STREAM, uri)
												addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
											}
											context.startActivity(Intent.createChooser(shareIntent, config.name))
										} catch (e: Exception) {
											scope.launch { snackbarHostState.showSnackbar(shareFailedMessage) }
										}
									}
								}
							)
					}
				}
			}
		}
	}

	if (showAddSheet) {
		AddConfigSheet(
			onDismiss = { showAddSheet = false },
			onSelect = { type ->
				showAddSheet = false
				navController.navigate(Screen.GuidedConfig.createRoute(type))
			}
		)
	}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddConfigSheet(onDismiss: () -> Unit, onSelect: (String) -> Unit) {
	ModalBottomSheet(onDismissRequest = onDismiss) {
		Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
			Text(
				text = stringResource(R.string.configurations_add_new),
				style = MaterialTheme.typography.titleMedium,
				fontWeight = FontWeight.Bold,
				modifier = Modifier.padding(bottom = 16.dp)
			)
			val types = listOf(
				Triple("adf", "ADF (Floppy)", Icons.Default.SdStorage),
				Triple("cd32", "CD32", Icons.Default.Album),
				Triple("hdf", "HDF (Hard Drive)", Icons.Default.Dns),
				Triple("whdload", "WHDLoad", Icons.Default.Archive),
				Triple("ags", "AGS", Icons.Default.AutoAwesome),
				Triple("custom", "Custom", Icons.Default.Build)
			)
			types.forEach { (type, label, icon) ->
				Row(
					modifier = Modifier
						.fillMaxWidth()
						.clickable { onSelect(type) }
						.padding(vertical = 14.dp),
					verticalAlignment = Alignment.CenterVertically
				) {
					Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
					Spacer(Modifier.width(16.dp))
					Text(label, style = MaterialTheme.typography.bodyLarge)
				}
			}
			Spacer(Modifier.height(8.dp))
		}
	}
}

/** Display names for the filter tabs - the enum's own names aren't all user-friendly. */
private fun categoryLabel(category: ConfigCategory): String = when (category) {
	ConfigCategory.WHDLOAD -> "WHD"
	ConfigCategory.GENERIC -> "Custom"
	else -> category.name
}

@Composable
private fun CategoryFilterBar(
	selected: ConfigCategory,
	onSelect: (ConfigCategory) -> Unit,
	modifier: Modifier = Modifier
) {
	LazyRow(
		modifier = modifier.padding(vertical = 8.dp),
		horizontalArrangement = Arrangement.spacedBy(8.dp)
	) {
		lazyRowItems(ConfigCategory.entries.toTypedArray()) { category ->
			FilterChip(
				selected = selected == category,
				onClick = { onSelect(category) },
				label = { Text(categoryLabel(category)) }
			)
		}
	}
}

@Composable
private fun MachineFilterBar(
	machines: List<AmigaModel>,
	selected: AmigaModel?,
	onSelect: (AmigaModel?) -> Unit,
	modifier: Modifier = Modifier
) {
	LazyRow(
		modifier = modifier.padding(vertical = 8.dp),
		// Machines are the right-hand half of the shared filter line, so pack them to the right
		// (spacedBy with an alignment keeps normal item order, unlike reverseLayout).
		horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)
	) {
		item {
			FilterChip(
				selected = selected == null,
				onClick = { onSelect(null) },
				label = { Text("All") }
			)
		}
		lazyRowItems(machines) { machine ->
			FilterChip(
				selected = selected == machine,
				onClick = { onSelect(machine) },
				label = { Text(machine.cmdArg) }
			)
		}
	}
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConfigCard(
	config: ConfigInfo,
	scope: CoroutineScope,
	snackbarHostState: SnackbarHostState,
	onLoad: () -> Unit,
	onDelete: () -> Unit,
	onDuplicate: () -> Unit,
	onShare: () -> Unit
) {
	val context = LocalContext.current
	var showMenu by remember { mutableStateOf(false) }
	var showDeleteDialog by remember { mutableStateOf(false) }
	val isReady = config.validationError == null

	val onPlay: () -> Unit = {
		if (isReady) {
			EmulatorLauncher.launchWithConfig(context, config.path, skipGui = true)
		} else {
			scope.launch {
				snackbarHostState.showSnackbar(
					message = config.validationError ?: "Invalid Configuration",
					duration = SnackbarDuration.Long,
					actionLabel = "Edit"
				).let { result ->
					if (result == SnackbarResult.ActionPerformed) {
						onLoad()
					}
				}
			}
		}
	}

	Card(
		modifier = Modifier
			.fillMaxWidth()
			.dpadFocusIndicator()
			.combinedClickable(
				onClick = onPlay,
				onLongClick = { showMenu = true }
			)
	) {
		Column {
			Box {
				Image(
					painter = painterResource(artworkFor(config.model)),
					contentDescription = config.model.displayName,
					modifier = Modifier
						.fillMaxWidth()
						.height(88.dp),
					contentScale = ContentScale.Crop
				)
				Icon(
					if (isReady) Icons.Default.CheckCircle else Icons.Default.Cancel,
					contentDescription = if (isReady) "Ready" else "Error",
					tint = if (isReady) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error,
					modifier = Modifier
						.align(Alignment.TopEnd)
						.padding(6.dp)
						.size(18.dp)
				)
				// Amiga model (A500/A1200/...) rather than the category - the filter tabs
				// already tell you the category, but which machine a config runs isn't
				// otherwise visible at a glance.
				Surface(
					color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.9f),
					shape = RoundedCornerShape(4.dp),
					modifier = Modifier
						.align(Alignment.TopStart)
						.padding(6.dp)
				) {
					Text(
						// cmdArg is the compact form ("A500", "A1200", "CD32"); displayName
						// ("Amiga 500") is too wide for a corner badge on a grid card.
						text = config.model.cmdArg,
						style = MaterialTheme.typography.labelSmall,
						fontWeight = FontWeight.Bold,
						modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
					)
				}
			}

			Column(modifier = Modifier.padding(10.dp)) {
				Text(
					text = config.name,
					style = MaterialTheme.typography.titleSmall,
					fontWeight = FontWeight.Bold,
					maxLines = 1,
					overflow = TextOverflow.Ellipsis
				)
				if (config.validationError != null) {
					Text(
						text = config.validationError,
						style = MaterialTheme.typography.labelSmall,
						color = MaterialTheme.colorScheme.error,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis
					)
				} else if (config.description.isNotEmpty()) {
					Text(
						text = config.description,
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis
					)
				}
				Text(
					text = formatDate(config.lastModified),
					style = MaterialTheme.typography.labelSmall,
					color = MaterialTheme.colorScheme.onSurfaceVariant
				)

				Spacer(Modifier.height(4.dp))

				Row(
					modifier = Modifier.fillMaxWidth(),
					horizontalArrangement = Arrangement.End,
					verticalAlignment = Alignment.CenterVertically
				) {
					// Tapping the card itself now launches (see onPlay above) - no separate play
					// icon needed. Edit (pencil) and the overflow menu remain as explicit actions.
					IconButton(modifier = Modifier.size(36.dp), onClick = onLoad) {
						Icon(
							Icons.Default.Edit,
							contentDescription = stringResource(R.string.action_edit_config),
							modifier = Modifier.size(20.dp)
						)
					}

					// More options button (D-pad accessible alternative to long-press)
					Box {
						IconButton(modifier = Modifier.size(36.dp), onClick = { showMenu = true }) {
							Icon(
								Icons.Default.MoreVert,
								contentDescription = stringResource(R.string.more_options),
								modifier = Modifier.size(20.dp)
							)
						}
						DropdownMenu(
							expanded = showMenu,
							onDismissRequest = { showMenu = false }
						) {
							DropdownMenuItem(
								text = { Text(stringResource(R.string.action_duplicate)) },
								onClick = {
									onDuplicate()
									showMenu = false
								},
								leadingIcon = { Icon(Icons.Default.ContentCopy, contentDescription = null) }
							)
							DropdownMenuItem(
								text = { Text(stringResource(R.string.action_share)) },
								onClick = {
									onShare()
									showMenu = false
								},
								leadingIcon = { Icon(Icons.Default.Share, contentDescription = null) }
							)
							DropdownMenuItem(
								text = { Text(stringResource(R.string.action_delete)) },
								onClick = {
									showDeleteDialog = true
									showMenu = false
								},
								leadingIcon = {
									Icon(
										Icons.Default.Delete,
										contentDescription = null,
										tint = MaterialTheme.colorScheme.error
									)
								}
							)
						}
					}
				}
			}
		}
	}

	// Delete confirmation dialog
	if (showDeleteDialog) {
		AlertDialog(
			onDismissRequest = { showDeleteDialog = false },
			title = { Text(stringResource(R.string.dialog_delete_config_title)) },
			text = { Text(stringResource(R.string.dialog_delete_config_message, config.name)) },
			confirmButton = {
				TextButton(onClick = {
					onDelete()
					showDeleteDialog = false
				}) {
					Text(stringResource(R.string.action_delete), color = MaterialTheme.colorScheme.error)
				}
			},
			dismissButton = {
				TextButton(onClick = { showDeleteDialog = false }) {
					Text(stringResource(R.string.action_cancel))
				}
			}
		)
	}
}

private fun formatDate(timestamp: Long): String {
	if (timestamp == 0L) return ""
	return DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT, Locale.getDefault())
		.format(Date(timestamp))
}

@androidx.annotation.DrawableRes
private fun artworkFor(model: AmigaModel): Int = when (model) {
	AmigaModel.A1200 -> R.drawable.featured_a1200
	AmigaModel.A3000 -> R.drawable.featured_a3000
	AmigaModel.A4000 -> R.drawable.featured_a4000
	AmigaModel.CD32,
	AmigaModel.CDTV -> R.drawable.featured_cd32
	else -> R.drawable.featured_a500
}
