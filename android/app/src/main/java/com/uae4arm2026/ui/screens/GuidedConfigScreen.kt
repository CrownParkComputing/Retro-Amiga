package com.uae4arm2026.ui.screens

import android.content.Intent
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import com.uae4arm2026.Uae4ArmEmulatorActivity
import com.uae4arm2026.R
import com.uae4arm2026.data.AgsDetector
import com.uae4arm2026.data.ConfigRepository
import com.uae4arm2026.data.EmulatorLauncher
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.FileRepository
import com.uae4arm2026.data.model.AmigaFile
import com.uae4arm2026.data.model.AmigaModel
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.ui.findActivity
import com.uae4arm2026.ui.navigation.Screen
import com.uae4arm2026.ui.viewmodel.SettingsViewModel
import com.uae4arm2026.ui.viewmodel.QuickStartViewModel
import com.uae4arm2026.ui.screens.settings.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private enum class WizardStep { MACHINE, ROM, MEDIA_PRIMARY, MEDIA_OPTIONAL, TAILOR, SAVE }

// Every machine amiberry's own --model quickstart handler supports (see the --model
// dispatch in main.cpp: bip_a500/bip_a500plus/.../bip_cdtv) - the full quick-config set,
// not just a curated subset.
private val PRIMARY_MODELS = listOf(
	AmigaModel.A500,
	AmigaModel.A500_PLUS,
	AmigaModel.A600,
	AmigaModel.A1000,
	AmigaModel.A2000,
	AmigaModel.A1200,
	AmigaModel.A3000,
	AmigaModel.A4000,
	AmigaModel.CD32,
	AmigaModel.CDTV
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GuidedConfigScreen(
	mode: String,
	navController: NavController,
	settingsViewModel: SettingsViewModel = viewModel(LocalContext.current.findActivity() as ComponentActivity)
) {
	val context = LocalContext.current
	val scope = rememberCoroutineScope()
	val snackbarHostState = remember { SnackbarHostState() }

	// Editing a config for a game that's still running (paused in the background - see
	// Uae4ArmEmulatorActivity.openEditConfig()) should feel like a detour, not a trip back to the
	// launcher. Hardware/gesture back is handled app-wide in Uae4ArmApp's BackHandler; this local
	// action backs the on-screen arrow icon below once the wizard is at its first step.
	val returningToRunningGame = mode == "edit" && Uae4ArmEmulatorActivity.isRunning
	val returnToGame: () -> Unit = {
		val intent = Intent(context, Uae4ArmEmulatorActivity::class.java)
		intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
		context.startActivity(intent)
	}
	
	var currentStep by remember { mutableStateOf(WizardStep.MACHINE) }
	var wizardSettings by remember { mutableStateOf(EmulatorSettings()) }
	var configName by remember { mutableStateOf("") }
	
	val availableRoms by settingsViewModel.availableRoms.collectAsState()
	val availableFloppies by settingsViewModel.availableFloppies.collectAsState()
	val availableHdfs by settingsViewModel.availableHardDrives.collectAsState()
	val availableCds by settingsViewModel.availableCds.collectAsState()
	val availableWhdloads by FileRepository.getInstance(context).whdloadGames.collectAsState()

	val folderPickerLauncher = rememberLauncherForActivityResult(
		ActivityResultContracts.OpenDocumentTree()
	) { uri ->
		if (uri != null) {
			scope.launch {
				val path = FileManager.treeUriToPath(uri)
				if (path != null) {
					val install = withContext(Dispatchers.IO) {
						AgsDetector.detectFromPath(context, path)
					}
					if (install != null) {
						val drives = withContext(Dispatchers.IO) {
							AgsDetector.mountableHardDrives(context, install)
						}
						wizardSettings = wizardSettings.copy(
							baseModel = AmigaModel.A1200,
							romFile = install.romFile ?: wizardSettings.romFile,
							hardDrives = drives,
							useRtg = true,
							z3Ram = 512,
							cpuModel = 68020,
							chipset = "aga"
						)
						currentStep = WizardStep.ROM
					} else {
						snackbarHostState.showSnackbar(context.getString(R.string.guided_config_error_no_ags))
					}
				}
			}
		}
	}

	// Detect the effective wizard mode from the loaded settings when editing.
	// This ensures CD32/HD configs show the right media picker, not floppy.
	val effectiveMode = remember(mode, wizardSettings) {
		if (mode == "edit") {
			when {
				wizardSettings.whdloadFilename.isNotBlank() -> "whdload"
				wizardSettings.cdImage.isNotBlank() || wizardSettings.baseModel == AmigaModel.CD32 -> "cd32"
				wizardSettings.hardDrives.any { it.isNotBlank() } -> "hdf"
				wizardSettings.floppy0.isNotBlank() -> "adf"
				wizardSettings.baseModel == AmigaModel.CDTV -> "cd32"
				else -> "custom"
			}
		} else {
			mode
		}
	}

	val filteredModels = remember(effectiveMode) {
		when (mode) {
			"cd32" -> listOf(AmigaModel.CD32)
			/* CDTV hidden - CD32 covers all CD-based consoles */
			// "whdload" -> ... handled below
			"whdload" -> listOf(AmigaModel.A1200, AmigaModel.A4000, AmigaModel.A600)
			"ags" -> listOf(AmigaModel.A1200, AmigaModel.A4000)
			else -> PRIMARY_MODELS
		}
	}

	LaunchedEffect(mode) {
		if (mode == "edit") {
			wizardSettings = settingsViewModel.settings
			configName = settingsViewModel.currentConfigName ?: ""
			// Jump straight to the settings/tailor screen — an existing config already has a
			// machine picked, so re-showing the model-selection step first is just an extra,
			// pointless tap (and risks resetting cpu/chipset fields if the user taps a model).
			currentStep = WizardStep.TAILOR
		} else {
			val initialModel = when (mode) {
				"cd32" -> AmigaModel.CD32
				"whdload" -> AmigaModel.A1200
				"hdf" -> AmigaModel.A1200
				"ags" -> AmigaModel.A1200
				else -> AmigaModel.A500
			}
			wizardSettings = EmulatorSettings.fromModel(initialModel)

			// CD32 has only one possible machine and needs no CPU/JIT/RAM tailoring — a stock
			// CD32 profile is already correct. Skip straight to picking the disc image, and
			// resolve the CD32 + extended ROMs automatically if available.
			if (mode == "cd32") {
				val selectedRoms = settingsViewModel.selectRomsForModel(AmigaModel.CD32, availableRoms)
				if (selectedRoms.kick != null && selectedRoms.ext != null) {
					wizardSettings = wizardSettings.copy(
						romFile = selectedRoms.kick.path,
						romExtFile = selectedRoms.ext.path
					)
					currentStep = WizardStep.MEDIA_PRIMARY
				} else {
					currentStep = WizardStep.ROM
				}
			}
		}
	}

	Scaffold(
		snackbarHost = { SnackbarHost(snackbarHostState) },
		bottomBar = {
			Surface(tonalElevation = 1.dp) {
				BottomActionRow(
					currentStep = currentStep,
					onBack = {
						if (currentStep != WizardStep.MACHINE) {
							currentStep = WizardStep.entries[currentStep.ordinal - 1]
						}
					},
					onNext = { 
						when (currentStep) {
							WizardStep.MACHINE -> {
								if (mode == "ags") {
									folderPickerLauncher.launch(null)
								} else {
									val selectedModel = wizardSettings.baseModel
									val selectedRoms = settingsViewModel.selectRomsForModel(selectedModel, availableRoms)
									
									val isCd = selectedModel == AmigaModel.CD32 || selectedModel == AmigaModel.CDTV
									val canSkip = if (isCd) selectedRoms.kick != null && selectedRoms.ext != null else selectedRoms.kick != null

									if (canSkip) {
										wizardSettings = wizardSettings.copy(
											romFile = selectedRoms.kick!!.path,
											romExtFile = selectedRoms.ext?.path ?: ""
										)
										currentStep = WizardStep.MEDIA_PRIMARY
									} else {
										currentStep = WizardStep.ROM
									}
								}
							}
							WizardStep.MEDIA_PRIMARY -> {
								when (mode) {
									"adf", "hdf" -> currentStep = WizardStep.MEDIA_OPTIONAL
									"cd32" -> {
										// Skip CPU/JIT/RAM tailoring entirely for CD32 — jump straight
										// to naming + saving with the stock CD32 defaults.
										if (configName.isBlank()) {
											configName = wizardSettings.cdImage.substringAfterLast('/').substringBeforeLast('.')
										}
										currentStep = WizardStep.SAVE
									}
									else -> currentStep = WizardStep.TAILOR
								}
							}
							WizardStep.MEDIA_OPTIONAL -> currentStep = WizardStep.TAILOR
							WizardStep.TAILOR -> {
								if (configName.isBlank()) {
									val mediaPath = wizardSettings.floppy0.takeIf { it.isNotBlank() }
										?: wizardSettings.whdloadFilename.takeIf { it.isNotBlank() }
										?: wizardSettings.cdImage.takeIf { it.isNotBlank() }
										?: wizardSettings.hardDrives.firstOrNull { it.isNotBlank() }
									
									configName = mediaPath?.substringAfterLast('/')?.substringBeforeLast('.') ?: ""
								}
								currentStep = WizardStep.SAVE
							}
							WizardStep.SAVE -> {
								if (configName.isNotBlank()) {
									scope.launch(Dispatchers.IO) {
										ConfigRepository.getInstance(context).saveConfig(wizardSettings, configName)
										withContext(Dispatchers.Main) {
											if (Uae4ArmEmulatorActivity.isRunning) {
												// A game is already running (paused in the background) - hard-reboot
												// it into the edited config. CLEAR_TASK replaces the stale instance
												// entirely so the old and new emulator activities never coexist.
												val args = settingsViewModel.generateLaunchArgs()
												val i = Intent(context, Uae4ArmEmulatorActivity::class.java)
												i.putExtra("SDL_ARGS", args)
												i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
												context.startActivity(i)
											} else if (mode == "edit") {
												// Editing an existing config (e.g. via the pencil icon in
												// Configurations) with nothing currently running: "save and
												// restart" should actually launch it, not just silently save
												// and drop back to the list.
												val args = settingsViewModel.generateLaunchArgs()
												val i = Intent(context, Uae4ArmEmulatorActivity::class.java)
												i.putExtra("SDL_ARGS", args)
												context.startActivity(i)
											} else {
												navController.navigate(Screen.Configurations.route) {
													popUpTo(Screen.Configurations.route) { inclusive = true }
												}
											}
										}
									}
								}
							}
							else -> currentStep = WizardStep.entries[currentStep.ordinal + 1]
						}
					},
					canFinish = when (currentStep) {
						WizardStep.SAVE -> configName.isNotBlank()
						WizardStep.ROM -> wizardSettings.romFile.isNotBlank()
						WizardStep.MEDIA_PRIMARY -> when(effectiveMode) {
							"adf" -> wizardSettings.floppy0.isNotBlank()
							"hdf" -> wizardSettings.hardDrives.firstOrNull()?.isNotBlank() == true
							"cd32" -> wizardSettings.cdImage.isNotBlank()
							"whdload" -> wizardSettings.whdloadFilename.isNotBlank()
							else -> true
						}
						else -> true
					},
					nextLabel = when (currentStep) {
						WizardStep.SAVE -> {
							if (Uae4ArmEmulatorActivity.isRunning) "Reboot System"
							else if (mode == "edit" && configName.trim() == settingsViewModel.currentConfigName) "Save & Launch"
							else "Save & Finish"
						}
						WizardStep.MACHINE -> if (mode == "ags") "Select Folder" else "Next"
						else -> "Next"
					}
				)
			}
		}
	) { padding ->
		Box(modifier = Modifier.fillMaxSize().padding(padding)) {
			Column(
				modifier = Modifier
					.fillMaxSize()
					.padding(horizontal = 24.dp)
			) {
				Spacer(Modifier.height(56.dp)) // Space for floating header
				StepIndicatorDots(currentStep)
				Spacer(Modifier.height(16.dp))

				AnimatedContent(
					targetState = currentStep,
					transitionSpec = {
						if (targetState.ordinal > initialState.ordinal) {
							slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
						} else {
							slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
						}
					},
					label = "wizard_step",
					modifier = Modifier.weight(1f)
				) { step ->
					when (step) {
						WizardStep.MACHINE -> MachineSelectionStep(filteredModels, wizardSettings.baseModel) { model ->
							val base = EmulatorSettings.fromModel(model)
							wizardSettings = wizardSettings.copy(
								baseModel = model,
								cpuModel = base.cpuModel,
								chipset = base.chipset,
								chipRam = base.chipRam,
								slowRam = base.slowRam,
								fastRam = base.fastRam,
								jitCacheSize = base.jitCacheSize,
								useRtg = base.useRtg
							)
						}
						WizardStep.ROM -> RomSelectionStep(availableRoms, wizardSettings, settingsViewModel) { 
							wizardSettings = wizardSettings.copy(romFile = it.path)
						}
						WizardStep.MEDIA_PRIMARY -> PrimaryMediaStep(
							mode = effectiveMode,
							settings = wizardSettings,
							availableFloppies = availableFloppies,
							availableHdfs = availableHdfs,
							availableCds = availableCds,
							availableWhdloads = availableWhdloads,
							onUpdate = { wizardSettings = it }
						)
						WizardStep.MEDIA_OPTIONAL -> OptionalMediaStep(
							mode = effectiveMode,
							settings = wizardSettings,
							availableFloppies = availableFloppies,
							availableHdfs = availableHdfs,
							onUpdate = { wizardSettings = it }
						)
						WizardStep.TAILOR -> TailorStep(wizardSettings) { wizardSettings = it }
						WizardStep.SAVE -> FinalSaveStep(configName, { configName = it }, wizardSettings, settingsViewModel.currentConfigName)
					}
				}
			}

			// Floating Header
			Row(
				modifier = Modifier
					.fillMaxWidth()
					.padding(top = 16.dp, start = 8.dp, end = 16.dp),
				verticalAlignment = Alignment.CenterVertically
			) {
				IconButton(
					onClick = {
						if (currentStep != WizardStep.MACHINE) {
							currentStep = WizardStep.entries[currentStep.ordinal - 1]
						} else if (returningToRunningGame) {
							returnToGame()
						} else {
							navController.popBackStack()
						}
					}
				) {
					Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = MaterialTheme.colorScheme.primary)
				}
				Spacer(Modifier.width(8.dp))
				Column(modifier = Modifier.weight(1f)) {
					Text(
						text = effectiveMode.uppercase() + " SETUP",
						style = MaterialTheme.typography.labelMedium,
						fontWeight = FontWeight.Black,
						color = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f),
						letterSpacing = 1.sp
					)
				}
				
				if (Uae4ArmEmulatorActivity.isRunning) {
					IconButton(onClick = returnToGame) {
						Icon(Icons.Default.PlayArrow, contentDescription = "Resume", tint = MaterialTheme.colorScheme.primary)
					}
				}
			}
		}
	}
}

@Composable
private fun StepIndicatorDots(currentStep: WizardStep) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.padding(vertical = 8.dp), 
		horizontalArrangement = Arrangement.Center
	) {
		WizardStep.entries.forEach { step ->
			val isActive = step == currentStep
			val isCompleted = step.ordinal < currentStep.ordinal
			val color = if (isActive) MaterialTheme.colorScheme.primary 
						else if (isCompleted) MaterialTheme.colorScheme.primary.copy(alpha = 0.6f)
						else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f)
			Box(
				modifier = Modifier
					.padding(horizontal = 6.dp)
					.size(if (isActive) 12.dp else 8.dp)
					.clip(CircleShape)
					.background(color)
					.then(if (isActive) Modifier.border(2.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.1f), CircleShape) else Modifier)
			)
		}
	}
}

@Composable
private fun MachineSelectionStep(models: List<AmigaModel>, selected: AmigaModel, onSelect: (AmigaModel) -> Unit) {
	Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxSize()) {
		// Hero machine preview
		Box(
			contentAlignment = Alignment.Center, 
			modifier = Modifier
				.weight(1f)
				.fillMaxWidth()
		) {
			Column(horizontalAlignment = Alignment.CenterHorizontally) {
				Image(
					painter = painterResource(artworkFor(selected)),
					contentDescription = selected.displayName,
					contentScale = ContentScale.Fit,
					modifier = Modifier.fillMaxHeight(0.7f).fillMaxWidth().padding(16.dp)
				)
				Text(selected.displayName, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold, color = MaterialTheme.colorScheme.primary)
				Text(selected.description, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
			}
		}
		
		Spacer(Modifier.height(16.dp))
		
		// Selectable footer for model swapping
		LazyRow(
			modifier = Modifier.fillMaxWidth().height(80.dp),
			horizontalArrangement = Arrangement.spacedBy(12.dp),
			contentPadding = PaddingValues(horizontal = 16.dp),
			verticalAlignment = Alignment.CenterVertically
		) {
			items(models) { model ->
				val isSelected = model == selected
				Surface(
					onClick = { onSelect(model) },
					shape = RoundedCornerShape(12.dp),
					color = if (isSelected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant,
					modifier = Modifier.size(100.dp, 60.dp),
					border = if (isSelected) androidx.compose.foundation.BorderStroke(2.dp, MaterialTheme.colorScheme.primary) else null
				) {
					Box(contentAlignment = Alignment.Center) {
						Text(
							model.displayName.removePrefix("Amiga "), 
							fontSize = 13.sp, 
							fontWeight = FontWeight.Bold,
							color = if (isSelected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant
						)
					}
				}
			}
		}
		Spacer(Modifier.height(8.dp))
	}
}

@Composable
private fun RomSelectionStep(roms: List<AmigaFile>, settings: EmulatorSettings, settingsViewModel: SettingsViewModel, onSelect: (AmigaFile) -> Unit) {
	val bestMatch = remember(settings.baseModel, roms) {
		val profile = SettingsViewModel.MODEL_ROM_PROFILE[settings.baseModel]
		val modelKeywords = SettingsViewModel.MODEL_KEYWORDS[settings.baseModel] ?: emptyList()
		
		roms.find { rom ->
			val romId = settingsViewModel.detectRomId(rom)
			romId != null && profile?.kickIds?.contains(romId) == true
		} ?: roms.find { rom ->
			val name = rom.name.lowercase()
			modelKeywords.any { name.contains(it) } && !name.contains("ext")
		} ?: roms.firstOrNull { it.name.lowercase().contains("kick") }
	}

	Column(modifier = Modifier.fillMaxSize()) {
		Text(stringResource(R.string.guided_config_instruction_rom), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
		Spacer(Modifier.height(16.dp))
		
		if (bestMatch != null) {
			Text("Recommended ROM", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
			Card(
				onClick = { onSelect(bestMatch) },
				colors = CardDefaults.cardColors(containerColor = if (settings.romFile == bestMatch.path) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant),
				modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
			) {
				Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
					Icon(Icons.Default.Verified, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
					Spacer(Modifier.width(12.dp))
					Text(bestMatch.name, fontWeight = FontWeight.Bold, fontSize = 14.sp)
				}
			}
		}
		
		Spacer(Modifier.height(12.dp))
		Text("Others", style = MaterialTheme.typography.labelLarge)
		LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
			items(roms.filter { it.path != bestMatch?.path }) { rom ->
				val isSelected = rom.path == settings.romFile
				ListItem(
					headlineContent = { Text(rom.name, fontSize = 13.sp) },
					trailingContent = { if (isSelected) Icon(Icons.Default.Check, contentDescription = null) },
					modifier = Modifier.clickable { onSelect(rom) }
				)
			}
		}
	}
}

@Composable
private fun PrimaryMediaStep(
	mode: String,
	settings: EmulatorSettings,
	availableFloppies: List<AmigaFile>,
	availableHdfs: List<AmigaFile>,
	availableCds: List<AmigaFile>,
	availableWhdloads: List<AmigaFile>,
	onUpdate: (EmulatorSettings) -> Unit
) {
	Column(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
		val instruction = when(mode) {
			"whdload" -> "Select the .LHA game archive"
			"cd32" -> "Select the CD disc image"
			"hdf" -> "Select the system hard drive (.HDF)"
			else -> stringResource(R.string.guided_config_instruction_media_primary)
		}
		Text(instruction, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
		Spacer(Modifier.height(32.dp))
		
		val art = when(mode) {
			"cd32" -> R.drawable.featured_cd32
			"hdf" -> R.drawable.featured_drive_dh0
			else -> R.drawable.featured_drive_df0
		}
		val currentPath = when(mode) {
			"adf" -> settings.floppy0
			"hdf" -> settings.hardDrives.firstOrNull() ?: ""
			"cd32" -> settings.cdImage
			"whdload" -> settings.whdloadFilename
			else -> ""
		}
		val options = when(mode) {
			"adf" -> availableFloppies
			"hdf" -> availableHdfs
			"cd32" -> availableCds
			"whdload" -> availableWhdloads
			else -> emptyList()
		}

		SingleMediaPicker(
			label = when(mode) {
				"whdload" -> "Game File"
				"cd32" -> "CD-ROM"
				"hdf" -> "DH0:"
				else -> "DF0:"
			},
			art = art,
			currentPath = currentPath,
			options = options,
			onSelect = { path ->
				when (mode) {
					"adf" -> onUpdate(settings.copy(floppy0 = path))
					"hdf" -> onUpdate(settings.copy(hardDrives = listOf(path)))
					"cd32" -> {
						// Picking a CD image always means "boot this as a CD-console" — without
						// promoting baseModel here, an 'edit' session on a non-CD32 config (e.g.
						// A1200) would save a CD image with no chipset_compatible=CD32/cd32cd
						// flags, leaving a plain Amiga with no CD-boot ROM (stuck at "insert disk").
						val cdModel = if (settings.baseModel == AmigaModel.CDTV) AmigaModel.CDTV else AmigaModel.CD32
						onUpdate(settings.copy(cdImage = path, baseModel = cdModel))
					}
					"whdload" -> onUpdate(settings.copy(whdloadFilename = path))
				}
			}
		)
	}
}

@Composable
private fun OptionalMediaStep(
	mode: String,
	settings: EmulatorSettings,
	availableFloppies: List<AmigaFile>,
	availableHdfs: List<AmigaFile>,
	onUpdate: (EmulatorSettings) -> Unit
) {
	Column(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
		Text(stringResource(R.string.guided_config_instruction_media_optional), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
		Spacer(Modifier.height(16.dp))

		if (mode == "adf") {
			SingleMediaPicker(
				label = "DF1:",
				art = R.drawable.featured_drive_df_external,
				currentPath = settings.floppy1,
				options = availableFloppies,
				onSelect = { onUpdate(settings.copy(floppy1 = it, floppy1Type = if (it.isEmpty()) -1 else 0)) }
			)
		} else {
			val currentHdf1 = settings.hardDrives.getOrNull(1) ?: ""
			SingleMediaPicker(
				label = "DH1:",
				art = R.drawable.featured_drive_dh0,
				currentPath = currentHdf1,
				options = availableHdfs,
				onSelect = { path ->
					val list = settings.hardDrives.toMutableList()
					if (list.size < 2) list.add(path) else list[1] = path
					onUpdate(settings.copy(hardDrives = list))
				}
			)
		}
	}
}

@Composable
private fun TailorStep(settings: EmulatorSettings, onUpdate: (EmulatorSettings) -> Unit) {
	Column(modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
		Text(stringResource(R.string.guided_config_instruction_tailor), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
		Spacer(Modifier.height(16.dp))

		SettingsHardwareDropdown("CPU Model", settings.cpuModel.toString(), EmulatorSettings.cpuModels.map { it.toString() }) {
			onUpdate(settings.copy(cpuModel = it.toInt()))
		}
		
		Spacer(Modifier.height(12.dp))

		if (settings.cpuModel >= 68020) {
			SettingsSwitchRow(
				label = "JIT Acceleration",
				checked = settings.jitCacheSize > 0,
				onCheckedChange = { isChecked -> onUpdate(settings.copy(jitCacheSize = if (isChecked) 16384 else 0)) }
			)
			SettingsSwitchRow(
				label = "RTG Graphics (UAEGFX)",
				checked = settings.useRtg,
				onCheckedChange = { isChecked -> onUpdate(settings.copy(useRtg = isChecked)) }
			)
			Spacer(Modifier.height(12.dp))
		}
		
		SettingsHardwareDropdown("Chip RAM", EmulatorSettings.chipRamOptions.find { it.first == settings.chipRam }?.second ?: "", EmulatorSettings.chipRamOptions.map { it.second }) { label ->
			EmulatorSettings.chipRamOptions.find { it.second == label }?.let { onUpdate(settings.copy(chipRam = it.first)) }
		}

		Spacer(Modifier.height(12.dp))

		SettingsHardwareDropdown("Fast RAM", EmulatorSettings.fastRamOptions.find { it.first == settings.fastRam }?.second ?: "", EmulatorSettings.fastRamOptions.map { it.second }) { label ->
			EmulatorSettings.fastRamOptions.find { it.second == label }?.let { onUpdate(settings.copy(fastRam = it.first)) }
		}
		
		if (settings.baseModel == AmigaModel.A1200 || settings.baseModel == AmigaModel.A4000) {
			Spacer(Modifier.height(12.dp))
			SettingsHardwareDropdown("Z3 RAM", EmulatorSettings.z3RamOptions.find { it.first == settings.z3Ram }?.second ?: "", EmulatorSettings.z3RamOptions.map { it.second }) { label ->
				EmulatorSettings.z3RamOptions.find { it.second == label }?.let { onUpdate(settings.copy(z3Ram = it.first)) }
			}
		}

		Spacer(Modifier.height(12.dp))
		SettingsSwitchRow(
			label = "NTSC (60Hz, US region)",
			checked = settings.ntsc,
			onCheckedChange = { isChecked -> onUpdate(settings.copy(ntsc = isChecked)) }
		)

		if (settings.baseModel == AmigaModel.CD32) {
			SettingsSwitchRow(
				label = "FMV Cartridge (MPEG video)",
				checked = settings.cd32Fmv,
				onCheckedChange = { isChecked -> onUpdate(settings.copy(cd32Fmv = isChecked)) }
			)
		}
	}
}

@Composable
private fun SingleMediaPicker(
	label: String,
	@androidx.annotation.DrawableRes art: Int,
	currentPath: String,
	options: List<AmigaFile>,
	onSelect: (String) -> Unit
) {
	var expanded by remember { mutableStateOf(false) }
	val hasFile = currentPath.isNotBlank()

	Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
		Box(
			modifier = Modifier
				.size(120.dp)
				.background(if (hasFile) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(16.dp))
				.clickable { expanded = true },
			contentAlignment = Alignment.Center
		) {
			Image(painterResource(art), contentDescription = null, modifier = Modifier.size(80.dp))
			if (!hasFile) Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(40.dp).align(Alignment.Center), tint = Color.Gray.copy(alpha = 0.5f))
		}
		Spacer(Modifier.height(16.dp))
		Text(label, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.titleMedium)
		Text(
			if (hasFile) currentPath.substringAfterLast('/') else "Tap to Select",
			style = MaterialTheme.typography.bodyMedium,
			color = if (hasFile) MaterialTheme.colorScheme.onSurface else Color.Gray,
			maxLines = 1,
			overflow = TextOverflow.Ellipsis
		)
		
		if (hasFile) {
			TextButton(onClick = { onSelect("") }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) {
				Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(16.dp))
				Spacer(Modifier.width(4.dp))
				Text("Remove")
			}
		}
	}

	if (expanded) {
		AlertDialog(
			onDismissRequest = { expanded = false },
			title = { Text("Select for $label") },
			modifier = Modifier.fillMaxWidth(0.95f),
			text = {
				if (options.isEmpty()) {
					Text("No files found. Please import some to your library first.")
				} else {
					LazyColumn(modifier = Modifier.heightIn(max = 400.dp)) {
						items(options) { file ->
							ListItem(
								headlineContent = { Text(file.name) },
								supportingContent = { Text(file.sizeDisplay, style = MaterialTheme.typography.labelSmall) },
								modifier = Modifier.clickable { onSelect(file.path); expanded = false }
							)
						}
					}
				}
			},
			confirmButton = { TextButton(onClick = { expanded = false }) { Text("Cancel") } }
		)
	}
}

@Composable
private fun FinalSaveStep(
	name: String, 
	onNameChange: (String) -> Unit, 
	settings: EmulatorSettings,
	initialName: String? = null
) {
	Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxSize()) {
		Text(stringResource(R.string.guided_config_instruction_save), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
		Spacer(Modifier.height(24.dp))
		
		if (!initialName.isNullOrBlank()) {
			Text("Original Name: $initialName", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
			Spacer(Modifier.height(8.dp))
		}

		OutlinedTextField(
			value = name,
			onValueChange = onNameChange,
			label = { Text(stringResource(R.string.label_configuration_name)) },
			modifier = Modifier.fillMaxWidth(),
			singleLine = true,
			placeholder = { Text("e.g. Workbench 3.1") }
		)
		
		Spacer(Modifier.height(32.dp))
		
		Text("System Summary", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary)
		Spacer(Modifier.height(8.dp))
		Card(modifier = Modifier.fillMaxWidth()) {
			Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
				Text("${settings.baseModel.displayName} (${settings.baseModel.chipset})", fontWeight = FontWeight.Bold)
				if (settings.romFile.isNotBlank()) {
					Text("Firmware: ${settings.romFile.substringAfterLast('/')}", fontSize = 12.sp)
				}
				if (settings.whdloadFilename.isNotBlank()) {
					Text("LHA Game: ${settings.whdloadFilename.substringAfterLast('/')}", fontSize = 12.sp)
				} else if (settings.floppy0.isNotBlank()) {
					Text("Primary Disk: ${settings.floppy0.substringAfterLast('/')}", fontSize = 12.sp)
				}
				Text("CPU: ${settings.cpuModel}", fontSize = 12.sp)
				Text("RAM: ${settings.chipRam/2.0}MB Chip, ${settings.fastRam}MB Fast", fontSize = 12.sp)
			}
		}
	}
}

@Composable
private fun BottomActionRow(
	currentStep: WizardStep, 
	onNext: () -> Unit, 
	onBack: () -> Unit, 
	canFinish: Boolean,
	nextLabel: String
) {
	Row(
		modifier = Modifier
			.fillMaxWidth()
			.padding(horizontal = 24.dp, vertical = 12.dp),
		horizontalArrangement = Arrangement.SpaceBetween,
		verticalAlignment = Alignment.CenterVertically
	) {
		TextButton(
			onClick = onBack, 
			enabled = currentStep != WizardStep.MACHINE,
			colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
		) {
			Text(stringResource(R.string.action_back), fontWeight = FontWeight.Bold)
		}
		
		Button(
			onClick = onNext, 
			enabled = canFinish,
			shape = RoundedCornerShape(16.dp),
			modifier = Modifier.defaultMinSize(minWidth = 150.dp, minHeight = 48.dp),
			elevation = ButtonDefaults.buttonElevation(defaultElevation = 4.dp)
		) {
			Text(nextLabel, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black)
		}
	}
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
