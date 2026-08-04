package com.uae4arm2026.ui.screens

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
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
import com.uae4arm2026.data.ConfigCategory
import com.uae4arm2026.data.ConfigInfo
import com.uae4arm2026.data.EmulatorLauncher
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
	val configs by viewModel.configs.collectAsState()
	var selectedCategory by remember { mutableStateOf<ConfigCategory?>(null) }

	val filteredConfigs = remember(configs, selectedCategory) {
		if (selectedCategory == null) configs
		else configs.filter { it.category == selectedCategory }
	}

	val groupedConfigs = remember(filteredConfigs) {
		filteredConfigs.groupBy { it.category }
	}

	val loadFailedMessage = stringResource(R.string.msg_failed_load_config)
	val deletedMessage = stringResource(R.string.msg_config_deleted)
	val deleteFailedMessage = stringResource(R.string.msg_failed_delete_config)
	val duplicateFailedMessage = stringResource(R.string.msg_failed_duplicate_config)
	val shareFailedMessage = stringResource(R.string.msg_failed_share_config)

	LaunchedEffect(Unit) {
		viewModel.refresh()
	}

	Scaffold(
		snackbarHost = { SnackbarHost(snackbarHostState) },
		topBar = {
			Column {
				TopAppBar(title = { Text(stringResource(R.string.configurations_title)) })
				CategoryFilterBar(
					selected = selectedCategory,
					onSelect = { selectedCategory = it }
				)
			}
		}
	) { innerPadding ->
		Column(modifier = Modifier.fillMaxSize().padding(innerPadding)) {
			if (configs.isEmpty()) {
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
						Button(onClick = { navController.navigate(Screen.QuickStart.route) }) {
							Text("Start Guided Setup")
						}
					}
				}
			} else {
				LazyColumn(
					contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
					verticalArrangement = Arrangement.spacedBy(8.dp)
				) {
					groupedConfigs.forEach { (category, categoryConfigs) ->
						item(key = category.name) {
							Text(
								text = category.name,
								style = MaterialTheme.typography.labelLarge,
								color = MaterialTheme.colorScheme.primary,
								modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
							)
						}
						items(categoryConfigs, key = { it.path }) { config ->
							ConfigItem(
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
	}
}

@Composable
private fun CategoryFilterBar(
	selected: ConfigCategory?,
	onSelect: (ConfigCategory?) -> Unit
) {
	LazyRow(
		modifier = Modifier
			.fillMaxWidth()
			.padding(horizontal = 16.dp, vertical = 8.dp),
		horizontalArrangement = Arrangement.spacedBy(8.dp)
	) {
		item {
			FilterChip(
				selected = selected == null,
				onClick = { onSelect(null) },
				label = { Text("All") }
			)
		}
		items(ConfigCategory.entries.toTypedArray()) { category ->
			FilterChip(
				selected = selected == category,
				onClick = { onSelect(category) },
				label = { Text(category.name) }
			)
		}
	}
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ConfigItem(
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

	Card(
		modifier = Modifier
			.fillMaxWidth()
			.dpadFocusIndicator()
			.combinedClickable(
				onClick = onLoad,
				onLongClick = { showMenu = true }
			)
	) {
		Row(
			modifier = Modifier
				.fillMaxWidth()
				.padding(12.dp),
			verticalAlignment = Alignment.CenterVertically
		) {
			// Machine Icon
			Image(
				painter = painterResource(artworkFor(config.model)),
				contentDescription = config.model.displayName,
				modifier = Modifier
					.size(48.dp)
					.clip(RoundedCornerShape(4.dp)),
				contentScale = ContentScale.Fit
			)
			
			Spacer(modifier = Modifier.width(16.dp))

			Column(modifier = Modifier.weight(1f)) {
				Row(verticalAlignment = Alignment.CenterVertically) {
					Text(
						text = config.name,
						style = MaterialTheme.typography.titleMedium,
						modifier = Modifier.weight(1f, fill = false)
					)
					Spacer(Modifier.width(8.dp))
					if (config.validationError == null) {
						Icon(Icons.Default.CheckCircle, contentDescription = "Ready", tint = Color(0xFF4CAF50), modifier = Modifier.size(16.dp))
					} else {
						Icon(Icons.Default.Cancel, contentDescription = "Error", tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(16.dp))
					}
				}
				if (config.validationError != null) {
					Text(
						text = config.validationError,
						style = MaterialTheme.typography.labelSmall,
						color = MaterialTheme.colorScheme.error,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis
					)
				}
				if (config.description.isNotEmpty()) {
					Text(
						text = config.description,
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant
					)
				}
				Row(verticalAlignment = Alignment.CenterVertically) {
					Surface(
						color = MaterialTheme.colorScheme.secondaryContainer,
						shape = RoundedCornerShape(4.dp),
						modifier = Modifier.padding(vertical = 2.dp)
					) {
						Text(
							text = config.category.name,
							style = MaterialTheme.typography.labelSmall,
							modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
						)
					}
					Spacer(modifier = Modifier.width(8.dp))
					Text(
						text = formatDate(config.lastModified),
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant
					)
				}
			}

			// Quick action buttons
			Row(
				modifier = Modifier.wrapContentWidth(),
				verticalAlignment = Alignment.CenterVertically
			) {
				val isReady = config.validationError == null
				IconButton(
					onClick = {
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
				) {
					Icon(
						if (isReady) Icons.Default.PlayArrow else Icons.Default.Cancel,
						contentDescription = stringResource(R.string.action_launch),
						modifier = Modifier.size(28.dp),
						tint = if (isReady) Color(0xFF4CAF50) else MaterialTheme.colorScheme.error
					)
				}
				IconButton(onClick = onLoad) {
					Icon(
						Icons.Default.Edit,
						contentDescription = stringResource(R.string.action_edit_config),
						modifier = Modifier.size(24.dp)
					)
				}

				// More options button (D-pad accessible alternative to long-press)
				Box {
					IconButton(onClick = { showMenu = true }) {
						Icon(
							Icons.Default.MoreVert,
							contentDescription = stringResource(R.string.more_options),
							modifier = Modifier.size(24.dp)
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
