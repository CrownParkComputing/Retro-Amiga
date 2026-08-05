package com.uae4arm2026.ui.screens.settings

import android.content.Intent
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.uae4arm2026.Uae4ArmEmulatorActivity
import com.uae4arm2026.R
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.ConfigRepository
import com.uae4arm2026.data.EmulatorLauncher
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.FileRepository
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.findActivity
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
	navController: NavController? = null,
	viewModel: SettingsViewModel = viewModel(LocalContext.current.findActivity() as androidx.activity.ComponentActivity)
) {
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val snackbarHostState = remember { SnackbarHostState() }
	var showSaveDialog by remember { mutableStateOf(false) }
	val availableRoms by viewModel.availableRoms.collectAsState()
	val canStart = viewModel.settings.romFile.isNotBlank() || availableRoms.isNotEmpty()
	val settings = viewModel.settings
	val appPrefs = AppPreferences.getInstance(context)

	val romPickerLauncher = rememberLauncherForActivityResult(
		contract = ActivityResultContracts.OpenDocument()
	) { uri ->
		uri?.let {
			scope.launch {
				val path = withContext(Dispatchers.IO) {
					FileManager.importFile(context, it, FileCategory.ROMS)
				}
				if (path != null) {
					FileRepository.getInstance(context).rescanCategory(FileCategory.ROMS)
				}
			}
		}
	}

	val invalidConfigNameMessage = stringResource(R.string.msg_invalid_config_name)
	val failedSaveConfigMessage = stringResource(R.string.msg_failed_save_config)

	Scaffold(
		snackbarHost = { SnackbarHost(snackbarHostState) }
	) { innerPadding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.padding(innerPadding)
				.verticalScroll(rememberScrollState())
				.padding(horizontal = 12.dp, vertical = 8.dp),
			verticalArrangement = Arrangement.spacedBy(8.dp)
		) {
			// Top bar: title + Save + Home
			Row(
				modifier = Modifier.fillMaxWidth(),
				verticalAlignment = Alignment.CenterVertically,
				horizontalArrangement = Arrangement.SpaceBetween
			) {
				Text(
					stringResource(R.string.settings_title),
					style = MaterialTheme.typography.titleLarge,
					fontWeight = androidx.compose.ui.text.font.FontWeight.Bold
				)
				Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
					if (Uae4ArmEmulatorActivity.isRunning) {
						TextButton(
							onClick = {
								val intent = Intent(context, Uae4ArmEmulatorActivity::class.java)
								intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
								context.startActivity(intent)
							},
							colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)
						) {
							Icon(Icons.Default.PlayArrow, contentDescription = null)
							Spacer(Modifier.width(4.dp))
							Text("Resume")
						}
						
						TextButton(
							onClick = {
								val args = viewModel.generateLaunchArgs()
								val intent = Intent(context, Uae4ArmEmulatorActivity::class.java)
								intent.putExtra("SDL_ARGS", args)
								intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
								context.startActivity(intent)
							},
							colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)
						) {
							Icon(Icons.Default.Refresh, contentDescription = null)
							Spacer(Modifier.width(4.dp))
							Text("Reboot")
						}
					}
					IconButton(onClick = { showSaveDialog = true }) {
						Icon(Icons.Default.Save, contentDescription = stringResource(R.string.action_save_configuration))
					}
					IconButton(onClick = {
						navController?.navigate(Screen.Configurations.route) {
							popUpTo(Screen.Configurations.route) { inclusive = false }
						}
					}) {
						Icon(Icons.Default.Home, contentDescription = "Home")
					}
				}
			}

			// ROM warning
			if (!canStart) {
				Card(
					modifier = Modifier.fillMaxWidth(),
					colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)
				) {
					Column(modifier = Modifier.padding(16.dp)) {
						Row(verticalAlignment = Alignment.CenterVertically) {
							Icon(Icons.Default.Warning, contentDescription = null, modifier = Modifier.size(24.dp), tint = MaterialTheme.colorScheme.onErrorContainer)
							Spacer(modifier = Modifier.width(8.dp))
							Text(stringResource(R.string.setup_required_title), style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onErrorContainer)
						}
						Spacer(modifier = Modifier.height(8.dp))
						Text(text = stringResource(R.string.setup_required_message), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onErrorContainer)
						Spacer(modifier = Modifier.height(12.dp))
						Button(
							onClick = { romPickerLauncher.launch(arrayOf("*/*")) },
							colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.onErrorContainer, contentColor = MaterialTheme.colorScheme.errorContainer)
						) {
							Text(stringResource(R.string.action_import_rom))
						}
					}
				}
			}

			SettingsSectionHeader("Machine Preset")
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					var modelExpanded by remember { mutableStateOf(false) }
					ExposedDropdownMenuBox(expanded = modelExpanded, onExpandedChange = { modelExpanded = it }) {
						OutlinedTextField(
							value = settings.baseModel.displayName,
							onValueChange = {},
							readOnly = true,
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = modelExpanded) },
							modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth(),
							supportingText = { Text(stringResource(R.string.settings_cpu_model_preset_help)) }
						)
						ExposedDropdownMenu(expanded = modelExpanded, onDismissRequest = { modelExpanded = false }) {
							AmigaModel.entries.forEach { m ->
								DropdownMenuItem(text = { Text("${m.displayName} - ${m.description}") }, onClick = {
									viewModel.applyModel(m)
									modelExpanded = false
								})
							}
						}
					}
				}
			}

			SettingsSectionHeader("Hardware Configuration")
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
					var cpuExpanded by remember { mutableStateOf(false) }
					ExposedDropdownMenuBox(expanded = cpuExpanded, onExpandedChange = { cpuExpanded = it }) {
						OutlinedTextField(
							value = "${settings.cpuModel}",
							onValueChange = {},
							readOnly = true,
							label = { Text("CPU Model") },
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = cpuExpanded) },
							modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth()
						)
						ExposedDropdownMenu(expanded = cpuExpanded, onDismissRequest = { cpuExpanded = false }) {
							EmulatorSettings.cpuModels.forEach { cpu ->
								DropdownMenuItem(text = { Text("$cpu") }, onClick = {
									viewModel.updateSettings { it.copy(cpuModel = cpu) }
									cpuExpanded = false
								})
							}
						}
					}

					SettingsSwitchRow(
						label = "JIT Acceleration",
						checked = settings.jitCacheSize > 0,
						enabled = settings.cpuModel >= 68020,
						onCheckedChange = { isChecked -> viewModel.updateSettings { it.copy(jitCacheSize = if (isChecked) 16384 else 0) } }
					)
					SettingsSwitchRow(
						label = "RTG Graphics (UAEGFX)",
						checked = settings.useRtg,
						enabled = settings.cpuModel >= 68020,
						onCheckedChange = { isChecked -> viewModel.updateSettings { it.copy(useRtg = isChecked) } }
					)
					SettingsSwitchRow(
						label = "Correct Aspect Ratio (4:3)",
						checked = settings.correctAspect,
						onCheckedChange = { isChecked -> viewModel.updateSettings { it.copy(correctAspect = isChecked) } }
					)
				}
			}

			SettingsSectionHeader("Controller Ports")
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
					Text(
						"Assign what drives each Amiga joystick/mouse port: a real mouse or " +
							"external controller if one is connected, or the on-screen touch " +
							"joystick/mouse for touchscreen-only play.",
						style = MaterialTheme.typography.bodySmall,
						color = MaterialTheme.colorScheme.onSurfaceVariant
					)

					val portOptions = listOf(
						"none" to stringResource(R.string.settings_input_device_none),
						"joy0" to stringResource(R.string.settings_input_device_joystick_0),
						"joy1" to stringResource(R.string.settings_input_device_joystick_1),
						"mouse" to stringResource(R.string.settings_input_device_mouse),
						"kbd1" to stringResource(R.string.settings_input_device_keyboard_layout_1),
						"kbd2" to stringResource(R.string.settings_input_device_keyboard_layout_2),
						"onscreen_joy" to stringResource(R.string.settings_input_device_on_screen_joystick)
					)

					// Which controller/mouse/on-screen control drives each port is a per-device
					// preference, not a per-game one - propagate it to every saved config so a
					// mismatched port doesn't silently break controls in whichever game wasn't
					// open when this was last changed.
					val portsUpdatedMessage = stringResource(R.string.msg_controller_ports_updated)
					fun propagateJoyportsToAllConfigs() {
						scope.launch(Dispatchers.IO) {
							val updated = ConfigRepository.getInstance(context).updateJoyportsForAllConfigs(
								joyport0 = viewModel.settings.joyport0,
								joyport1 = viewModel.settings.joyport1,
								onScreenJoystick = viewModel.settings.onScreenJoystick
							)
							if (updated > 0) {
								withContext(Dispatchers.Main) {
									snackbarHostState.showSnackbar(String.format(portsUpdatedMessage, updated))
								}
							}
						}
					}

					SettingsHardwareDropdown(
						label = stringResource(R.string.settings_input_port0_label),
						selected = portOptions.firstOrNull { it.first == settings.joyport0 }?.second ?: settings.joyport0,
						options = portOptions.map { it.second }
					) { label ->
						portOptions.firstOrNull { it.second == label }?.let { opt ->
							viewModel.updateSettings { it.copy(joyport0 = opt.first) }
							propagateJoyportsToAllConfigs()
						}
					}

					SettingsHardwareDropdown(
						label = stringResource(R.string.settings_input_port1_label),
						selected = portOptions.firstOrNull { it.first == settings.joyport1 }?.second ?: settings.joyport1,
						options = portOptions.map { it.second }
					) { label ->
						portOptions.firstOrNull { it.second == label }?.let { opt ->
							viewModel.updateSettings {
								it.copy(joyport1 = opt.first, onScreenJoystick = opt.first == "onscreen_joy")
							}
							propagateJoyportsToAllConfigs()
						}
					}

					Spacer(modifier = Modifier.height(4.dp))
					OutlinedButton(
						onClick = {
							context.startActivity(Intent(context, com.uae4arm2026.ControllerMapActivity::class.java))
						},
						modifier = Modifier.fillMaxWidth()
					) {
						Icon(Icons.Default.SportsEsports, contentDescription = null)
						Spacer(Modifier.width(8.dp))
						Text("Map External Controller Buttons")
					}
				}
			}

			SettingsSectionHeader("Memory")
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
					SettingsHardwareDropdown("Chip RAM", EmulatorSettings.chipRamOptions.find { it.first == settings.chipRam }?.second ?: "", EmulatorSettings.chipRamOptions.map { it.second }) { label ->
						EmulatorSettings.chipRamOptions.find { it.second == label }?.let { opt -> viewModel.updateSettings { s -> s.copy(chipRam = opt.first) } }
					}
					SettingsHardwareDropdown("Fast RAM", EmulatorSettings.fastRamOptions.find { it.first == settings.fastRam }?.second ?: "", EmulatorSettings.fastRamOptions.map { it.second }) { label ->
						EmulatorSettings.fastRamOptions.find { it.second == label }?.let { opt -> viewModel.updateSettings { s -> s.copy(fastRam = opt.first) } }
					}
				}
			}
		}

		if (showSaveDialog) {
			SaveConfigDialog(
				initialName = viewModel.currentConfigName ?: "",
				onDismiss = { showSaveDialog = false },
				onSave = { name, description ->
					val repo = ConfigRepository.getInstance(context)
					val safeName = name.trim()
					if (!repo.isValidConfigName(safeName)) {
						scope.launch { snackbarHostState.showSnackbar(invalidConfigNameMessage) }
						return@SaveConfigDialog
					}
					val savedFile = repo.saveConfig(viewModel.settings, safeName, viewModel.currentUnknownLines, description)
					if (savedFile == null) {
						scope.launch { snackbarHostState.showSnackbar(failedSaveConfigMessage) }
						return@SaveConfigDialog
					}
					showSaveDialog = false
					scope.launch { snackbarHostState.showSnackbar(context.getString(R.string.msg_saved_configuration, savedFile.name)) }
				}
			)
		}
	}
}

@Composable
fun SaveConfigDialog(
	initialName: String = "",
	onDismiss: () -> Unit,
	onSave: (String, String) -> Unit
) {
	var name by remember { mutableStateOf(initialName) }
	var description by remember { mutableStateOf("") }
	val isOverwrite = name.trim() == initialName && initialName.isNotEmpty()

	AlertDialog(
		onDismissRequest = onDismiss,
		title = { Text(if (isOverwrite) "Update Configuration" else "Save Configuration") },
		text = {
			Column {
				if (initialName.isNotEmpty()) {
					Text("Current: $initialName", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
					Spacer(Modifier.height(8.dp))
				}
				OutlinedTextField(
					value = name,
					onValueChange = { name = it },
					label = { Text("Configuration Name") },
					singleLine = true,
					modifier = Modifier.fillMaxWidth()
				)
				Spacer(Modifier.height(12.dp))
				OutlinedTextField(
					value = description,
					onValueChange = { description = it },
					label = { Text("Description (Optional)") },
					singleLine = true,
					modifier = Modifier.fillMaxWidth()
				)
			}
		},
		confirmButton = {
			Button(
				onClick = { onSave(name.trim(), description.trim()) },
				enabled = name.isNotBlank()
			) {
				Text(if (isOverwrite) "Overwrite" else "Save As New")
			}
		},
		dismissButton = {
			TextButton(onClick = onDismiss) {
				Text(stringResource(R.string.action_cancel))
			}
		}
	)
}
