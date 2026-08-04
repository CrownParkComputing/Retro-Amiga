package com.uae4arm2026.ui.screens.settings

import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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
import com.uae4arm2026.R
import com.uae4arm2026.data.AppPreferences
import com.uae4arm2026.data.ConfigRepository
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

	val chipsetLabels = mapOf(
		"ocs" to stringResource(R.string.settings_chipset_ocs),
		"ecs_agnus" to stringResource(R.string.settings_chipset_ecs_agnus),
		"ecs_denise" to stringResource(R.string.settings_chipset_ecs_denise),
		"ecs" to stringResource(R.string.settings_chipset_full_ecs),
		"aga" to stringResource(R.string.settings_chipset_aga)
	)
	val collisionOptions = listOf(
		"none" to stringResource(R.string.settings_option_none),
		"sprites" to stringResource(R.string.settings_chipset_collision_sprites_only),
		"playfields" to stringResource(R.string.settings_chipset_collision_sprites_playfields),
		"full" to stringResource(R.string.settings_chipset_collision_full)
	)
	val soundOutputLabels = mapOf(
		"none" to stringResource(R.string.settings_sound_output_disabled),
		"interrupts" to stringResource(R.string.settings_sound_output_emulated_no_output),
		"normal" to stringResource(R.string.settings_sound_output_normal),
		"exact" to stringResource(R.string.settings_sound_output_exact)
	)
	val freqOptions = listOf(
		22050 to stringResource(R.string.settings_sound_frequency_hz, 22050),
		44100 to stringResource(R.string.settings_sound_frequency_hz, 44100),
		48000 to stringResource(R.string.settings_sound_frequency_hz, 48000)
	)
	val channelOptions = listOf(
		"mono" to stringResource(R.string.settings_sound_channels_mono),
		"stereo" to stringResource(R.string.settings_sound_channels_stereo),
		"mixed" to stringResource(R.string.settings_sound_channels_mixed)
	)
	val interpolationOptions = listOf(
		"none" to stringResource(R.string.settings_sound_interpolation_none),
		"anti" to stringResource(R.string.settings_sound_interpolation_anti),
		"sinc" to stringResource(R.string.settings_sound_interpolation_sinc),
		"rh" to stringResource(R.string.settings_sound_interpolation_rh),
		"crux" to stringResource(R.string.settings_sound_interpolation_crux)
	)
	val amigaResPresets = listOf(
		Triple(640, 256, stringResource(R.string.settings_display_resolution_pal_low)),
		Triple(640, 512, stringResource(R.string.settings_display_resolution_pal_high)),
		Triple(720, 568, stringResource(R.string.settings_display_resolution_default)),
		Triple(800, 600, stringResource(R.string.settings_display_resolution_800_600)),
		Triple(1024, 768, stringResource(R.string.settings_display_resolution_1024_768))
	)
	val rtgResPresets = listOf(
		Triple(1280, 720, stringResource(R.string.settings_display_resolution_1280_720)),
		Triple(1600, 900, stringResource(R.string.settings_display_resolution_1600_900)),
		Triple(1920, 720, stringResource(R.string.settings_display_resolution_1920_720)),
		Triple(1920, 1080, stringResource(R.string.settings_display_resolution_1920_1080))
	)
	val portOptions = listOf(
		"none" to stringResource(R.string.settings_input_device_none),
		"joy0" to stringResource(R.string.settings_input_device_joystick_0),
		"joy1" to stringResource(R.string.settings_input_device_joystick_1),
		"mouse" to stringResource(R.string.settings_input_device_mouse),
		"kbd1" to stringResource(R.string.settings_input_device_keyboard_layout_1),
		"kbd2" to stringResource(R.string.settings_input_device_keyboard_layout_2),
		"onscreen_joy" to "On-Screen Controller"
	)
	val themeModeOptions = listOf(
		"system" to stringResource(R.string.settings_display_theme_system),
		"light" to stringResource(R.string.settings_display_theme_light),
		"dark" to stringResource(R.string.settings_display_theme_dark)
	)

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
					IconButton(onClick = { showSaveDialog = true }) {
						Icon(Icons.Default.Save, contentDescription = stringResource(R.string.action_save_configuration))
					}
					IconButton(onClick = {
						navController?.navigate(Screen.QuickStart.route) {
							popUpTo(Screen.QuickStart.route) { inclusive = false }
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
					colors = CardDefaults.cardColors(
						containerColor = MaterialTheme.colorScheme.errorContainer
					)
				) {
					Column(modifier = Modifier.padding(16.dp)) {
						Row(verticalAlignment = Alignment.CenterVertically) {
							Icon(
								Icons.Default.Warning,
								contentDescription = null,
								modifier = Modifier.size(24.dp),
								tint = MaterialTheme.colorScheme.onErrorContainer
							)
							Spacer(modifier = Modifier.width(8.dp))
							Text(
								stringResource(R.string.setup_required_title),
								style = MaterialTheme.typography.titleMedium,
								color = MaterialTheme.colorScheme.onErrorContainer
							)
						}
						Spacer(modifier = Modifier.height(8.dp))
						Text(
							text = stringResource(R.string.setup_required_message),
							style = MaterialTheme.typography.bodyMedium,
							color = MaterialTheme.colorScheme.onErrorContainer
						)
						Spacer(modifier = Modifier.height(12.dp))
						Button(
							onClick = { romPickerLauncher.launch(arrayOf("*/*")) },
							colors = ButtonDefaults.buttonColors(
								containerColor = MaterialTheme.colorScheme.onErrorContainer,
								contentColor = MaterialTheme.colorScheme.errorContainer
							)
						) {
							Text(stringResource(R.string.action_import_rom))
						}
					}
				}
			}

			// ── Model Preset ──
			SectionHeader(stringResource(R.string.settings_cpu_model_preset))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					var modelExpanded by remember { mutableStateOf(false) }
					ExposedDropdownMenuBox(
						expanded = modelExpanded,
						onExpandedChange = { modelExpanded = it }
					) {
						OutlinedTextField(
							value = settings.baseModel.displayName,
							onValueChange = {},
							readOnly = true,
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = modelExpanded) },
							modifier = Modifier
								.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
								.fillMaxWidth(),
							supportingText = {
								Text(stringResource(R.string.settings_cpu_model_preset_help))
							}
						)
						ExposedDropdownMenu(
							expanded = modelExpanded,
							onDismissRequest = { modelExpanded = false }
						) {
							AmigaModel.entries.forEach { m ->
								DropdownMenuItem(
									text = { Text("${m.displayName} - ${m.description}") },
									onClick = {
										viewModel.applyModel(m)
										modelExpanded = false
									}
								)
							}
						}
					}
				}
			}

			// ── CPU ──
			SectionHeader(stringResource(R.string.settings_cpu_section_title))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					var cpuExpanded by remember { mutableStateOf(false) }
					ExposedDropdownMenuBox(
						expanded = cpuExpanded,
						onExpandedChange = { cpuExpanded = it }
					) {
						OutlinedTextField(
							value = "${settings.cpuModel}",
							onValueChange = {},
							readOnly = true,
							label = { Text(stringResource(R.string.settings_cpu_model_label)) },
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = cpuExpanded) },
							modifier = Modifier
								.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
								.fillMaxWidth()
						)
						ExposedDropdownMenu(
							expanded = cpuExpanded,
							onDismissRequest = { cpuExpanded = false }
						) {
							EmulatorSettings.cpuModels.forEach { cpu ->
								DropdownMenuItem(
									text = { Text("$cpu") },
									onClick = {
										viewModel.updateSettings { it.copy(cpuModel = cpu) }
										cpuExpanded = false
									}
								)
							}
						}
					}

					Spacer(modifier = Modifier.height(8.dp))

					SwitchRow(
						label = stringResource(R.string.settings_cpu_fastest_possible),
						checked = settings.cpuSpeed == "max",
						enabled = !settings.cycleExact,
						onCheckedChange = {
							viewModel.updateSettings { s ->
								s.copy(cpuSpeed = if (it) "max" else "real")
							}
						}
					)
					SwitchRow(
						label = stringResource(R.string.settings_cpu_more_compatible),
						checked = settings.cpuCompatible,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(cpuCompatible = it) } }
					)
					SwitchRow(
						label = stringResource(R.string.settings_cpu_24bit_addressing),
						checked = settings.address24Bit,
						enabled = settings.cpuModel <= 68010,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(address24Bit = it) } }
					)

					// FPU
					if (settings.cpuModel >= 68020) {
						Spacer(modifier = Modifier.height(8.dp))
						val fpuOptions = buildList {
							add(0 to stringResource(R.string.settings_option_none))
							add(68881 to "68881")
							add(68882 to "68882")
							if (settings.cpuModel >= 68040) {
								add(settings.cpuModel to stringResource(R.string.settings_cpu_fpu_internal))
							}
						}
						RadioGroup(
							label = stringResource(R.string.settings_cpu_fpu_label),
							options = fpuOptions,
							selected = settings.fpuModel,
							onSelected = { viewModel.updateSettings { s -> s.copy(fpuModel = it) } }
						)
					}

					// JIT
					if (settings.cpuModel >= 68020) {
						Spacer(modifier = Modifier.height(8.dp))
						Text(stringResource(R.string.settings_cpu_jit_cache_label), style = MaterialTheme.typography.bodyMedium)
						val jitValues = listOf(0, 1024, 2048, 4096, 8192, 16384)
						val currentIndex = jitValues.indexOf(settings.jitCacheSize).coerceAtLeast(0)
						val isJitAllowed = !settings.address24Bit
						Slider(
							value = currentIndex.toFloat(),
							onValueChange = { idx ->
								val size = jitValues[idx.toInt().coerceIn(0, jitValues.lastIndex)]
								viewModel.updateSettings { s -> s.copy(jitCacheSize = size) }
							},
							valueRange = 0f..(jitValues.lastIndex).toFloat(),
							steps = jitValues.size - 2,
							enabled = isJitAllowed
						)
						Text(
							text = if (settings.jitCacheSize == 0) {
								stringResource(R.string.settings_common_disabled)
							} else {
								stringResource(R.string.settings_cpu_jit_cache_value, settings.jitCacheSize)
							},
							style = MaterialTheme.typography.bodySmall,
							color = if (isJitAllowed) MaterialTheme.colorScheme.onSurfaceVariant
							else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
						)
						SwitchRow(
							label = stringResource(R.string.settings_cpu_jit_fpu_label),
							checked = settings.jitFpu,
							enabled = settings.jitCacheSize > 0 && settings.fpuModel > 0,
							onCheckedChange = { enabled ->
								viewModel.updateSettings { s -> s.copy(jitFpu = enabled) }
							}
						)
					}
				}
			}

			// ── Chipset ──
			SectionHeader(stringResource(R.string.settings_chipset_section_title))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					RadioGroup(
						label = stringResource(R.string.settings_chipset_label),
						options = EmulatorSettings.chipsetOptions.map { (value, fallback) ->
							value to (chipsetLabels[value] ?: fallback)
						},
						selected = settings.chipset,
						onSelected = { viewModel.updateSettings { s -> s.copy(chipset = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					SwitchRow(
						label = stringResource(R.string.settings_chipset_immediate_blitter),
						checked = settings.immediateBlits,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(immediateBlits = it) } }
					)
					SwitchRow(
						label = stringResource(R.string.settings_chipset_cycle_exact),
						checked = settings.cycleExact,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(cycleExact = it) } }
					)
					SwitchRow(
						label = stringResource(R.string.settings_chipset_ntsc),
						checked = settings.ntsc,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(ntsc = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					RadioGroup(
						label = stringResource(R.string.settings_chipset_collision_level_label),
						options = collisionOptions,
						selected = settings.collisionLevel,
						onSelected = { viewModel.updateSettings { s -> s.copy(collisionLevel = it) } }
					)
				}
			}

			// ── Display ──
			SectionHeader(stringResource(R.string.settings_display_title))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					val currentAmigaResIndex = amigaResPresets.indexOfFirst {
						it.first == settings.gfxWidth && it.second == settings.gfxHeight
					}.coerceAtLeast(0)
					RadioGroup(
						label = stringResource(R.string.settings_display_amiga_resolution_label),
						options = amigaResPresets.mapIndexed { i, (_, _, label) -> i to label },
						selected = currentAmigaResIndex,
						onSelected = { idx ->
							val (w, h, _) = amigaResPresets[idx]
							viewModel.updateSettings { s -> s.copy(gfxWidth = w, gfxHeight = h) }
						}
					)

					Spacer(modifier = Modifier.height(8.dp))

					SwitchRow(
						label = stringResource(R.string.settings_display_correct_aspect_ratio),
						checked = settings.correctAspect,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(correctAspect = it) } }
					)
					SwitchRow(
						label = stringResource(R.string.settings_display_auto_crop),
						checked = settings.autoCrop,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(autoCrop = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					SwitchRow(
						label = stringResource(R.string.settings_display_rtg_label),
						checked = settings.useRtg,
						enabled = !settings.address24Bit && settings.cpuModel >= 68020,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(useRtg = it) } }
					)
					if (settings.useRtg) {
						Spacer(modifier = Modifier.height(8.dp))
						val currentRtgResIndex = rtgResPresets.indexOfFirst {
							it.first == settings.rtgWidth && it.second == settings.rtgHeight
						}.coerceAtLeast(0)
						RadioGroup(
							label = stringResource(R.string.settings_display_rtg_resolution_label),
							options = rtgResPresets.mapIndexed { i, (_, _, label) -> i to label },
							selected = currentRtgResIndex,
							onSelected = { idx ->
								val (w, h, _) = rtgResPresets[idx]
								viewModel.updateSettings { s -> s.copy(rtgWidth = w, rtgHeight = h) }
							}
						)
					}

					SwitchRow(
						label = stringResource(R.string.settings_display_show_leds),
						checked = settings.showLeds,
						onCheckedChange = { viewModel.updateSettings { s -> s.copy(showLeds = it) } }
					)
				}
			}

			// ── Sound ──
			SectionHeader(stringResource(R.string.settings_sound_title))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					RadioGroup(
						label = stringResource(R.string.settings_sound_output_label),
						options = EmulatorSettings.soundOutputOptions.map { (value, fallback) ->
							value to (soundOutputLabels[value] ?: fallback)
						},
						selected = settings.soundOutput,
						onSelected = { viewModel.updateSettings { s -> s.copy(soundOutput = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					RadioGroup(
						label = stringResource(R.string.settings_sound_sample_rate_label),
						options = freqOptions,
						selected = settings.soundFreq,
						onSelected = { viewModel.updateSettings { s -> s.copy(soundFreq = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					RadioGroup(
						label = stringResource(R.string.settings_sound_stereo_mode_label),
						options = channelOptions,
						selected = settings.soundChannels,
						onSelected = { viewModel.updateSettings { s -> s.copy(soundChannels = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					RadioGroup(
						label = stringResource(R.string.settings_sound_interpolation_label),
						options = interpolationOptions,
						selected = settings.soundInterpolation,
						onSelected = { viewModel.updateSettings { s -> s.copy(soundInterpolation = it) } }
					)

					Spacer(modifier = Modifier.height(8.dp))

					Text(stringResource(R.string.settings_sound_stereo_separation_label), style = MaterialTheme.typography.bodyMedium)
					Slider(
						value = settings.soundStereoSeparation.toFloat(),
						onValueChange = { value ->
							viewModel.updateSettings { s -> s.copy(soundStereoSeparation = value.toInt()) }
						},
						valueRange = 0f..10f,
						steps = 9
					)
					Text(
						stringResource(R.string.settings_sound_stereo_separation_value, settings.soundStereoSeparation),
						style = MaterialTheme.typography.bodySmall
					)
				}
			}

			// ── Input ──
			SectionHeader(stringResource(R.string.settings_input_port_assignments_title))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					var port0Expanded by remember { mutableStateOf(false) }
					val port0Label = portOptions.firstOrNull { it.first == settings.joyport0 }?.second
						?: settings.joyport0
					ExposedDropdownMenuBox(
						expanded = port0Expanded,
						onExpandedChange = { port0Expanded = it }
					) {
						OutlinedTextField(
							value = port0Label,
							onValueChange = {},
							readOnly = true,
							label = { Text(stringResource(R.string.settings_input_port0_label)) },
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = port0Expanded) },
							modifier = Modifier
								.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
								.fillMaxWidth()
						)
						ExposedDropdownMenu(
							expanded = port0Expanded,
							onDismissRequest = { port0Expanded = false }
						) {
							portOptions.forEach { (value, label) ->
								DropdownMenuItem(
									text = { Text(label) },
									onClick = {
										viewModel.updateSettings { s -> s.copy(joyport0 = value) }
										port0Expanded = false
									}
								)
							}
						}
					}

					Spacer(modifier = Modifier.height(8.dp))

					var port1Expanded by remember { mutableStateOf(false) }
					val port1Label = portOptions.firstOrNull { it.first == settings.joyport1 }?.second
						?: settings.joyport1
					ExposedDropdownMenuBox(
						expanded = port1Expanded,
						onExpandedChange = { port1Expanded = it }
					) {
						OutlinedTextField(
							value = port1Label,
							onValueChange = {},
							readOnly = true,
							label = { Text(stringResource(R.string.settings_input_port1_label)) },
							trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = port1Expanded) },
							modifier = Modifier
								.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
								.fillMaxWidth()
						)
						ExposedDropdownMenu(
							expanded = port1Expanded,
							onDismissRequest = { port1Expanded = false }
						) {
							portOptions.forEach { (value, label) ->
								DropdownMenuItem(
									text = { Text(label) },
									onClick = {
										viewModel.updateSettings { s ->
											s.copy(
												joyport1 = value,
												onScreenJoystick = value == "onscreen_joy"
											)
										}
										port1Expanded = false
									}
								)
							}
						}
					}
				}
			}

			// ── App Theme ──
			SectionHeader(stringResource(R.string.settings_display_app_theme))
			OutlinedCard(modifier = Modifier.fillMaxWidth()) {
				Column(modifier = Modifier.padding(16.dp)) {
					val themeMode by appPrefs.themeMode
					RadioGroup(
						label = stringResource(R.string.settings_display_theme_label),
						options = themeModeOptions,
						selected = themeMode,
						onSelected = { appPrefs.setThemeMode(it) }
					)

					if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
						Spacer(modifier = Modifier.height(8.dp))
						val useDynamicColor by appPrefs.useDynamicColor
						SwitchRow(
							label = stringResource(R.string.settings_display_dynamic_color),
							checked = useDynamicColor,
							onCheckedChange = { appPrefs.setDynamicColor(it) }
						)
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
						scope.launch {
							snackbarHostState.showSnackbar(invalidConfigNameMessage)
						}
						return@SaveConfigDialog
					}
					val savedFile = repo.saveConfig(viewModel.settings, safeName, viewModel.currentUnknownLines, description)
					if (savedFile == null) {
						scope.launch {
							snackbarHostState.showSnackbar(failedSaveConfigMessage)
						}
						return@SaveConfigDialog
					}
					showSaveDialog = false
					@Suppress("LocalContextGetResourceValueCall")
					scope.launch {
						snackbarHostState.showSnackbar(
							context.getString(R.string.msg_saved_configuration, savedFile.name)
						)
					}
				}
			)
		}
	}
}

@Composable
fun SectionHeader(title: String) {
	Text(
		text = title,
		style = MaterialTheme.typography.titleSmall,
		color = MaterialTheme.colorScheme.primary,
		modifier = Modifier.padding(top = 4.dp)
	)
}

@Composable
fun <T> RadioGroup(
	label: String,
	options: List<Pair<T, String>>,
	selected: T,
	onSelected: (T) -> Unit,
	enabled: Boolean = true
) {
	Column {
		Text(label, style = MaterialTheme.typography.bodyMedium)
		options.forEach { (value, text) ->
			Row(
				modifier = Modifier
					.fillMaxWidth()
					.selectable(
						selected = value == selected,
						enabled = enabled,
						role = Role.RadioButton,
						onClick = { onSelected(value) }
					)
					.padding(vertical = 2.dp),
				verticalAlignment = Alignment.CenterVertically
			) {
				RadioButton(
					selected = value == selected,
					onClick = null,
					enabled = enabled
				)
				Spacer(modifier = Modifier.width(8.dp))
				Text(
					text = text,
					style = MaterialTheme.typography.bodyMedium,
					color = if (enabled) MaterialTheme.colorScheme.onSurface
					else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
				)
			}
		}
	}
}

@Composable
fun SwitchRow(
	label: String,
	checked: Boolean,
	onCheckedChange: (Boolean) -> Unit,
	enabled: Boolean = true
) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.toggleable(
				value = checked,
				enabled = enabled,
				role = Role.Switch,
				onValueChange = onCheckedChange
			)
			.padding(vertical = 4.dp),
		verticalAlignment = Alignment.CenterVertically,
		horizontalArrangement = Arrangement.SpaceBetween
	) {
		Text(
			text = label,
			style = MaterialTheme.typography.bodyMedium,
			color = if (enabled) MaterialTheme.colorScheme.onSurface
			else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
		)
		Switch(
			checked = checked,
			onCheckedChange = null,
			enabled = enabled
		)
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
