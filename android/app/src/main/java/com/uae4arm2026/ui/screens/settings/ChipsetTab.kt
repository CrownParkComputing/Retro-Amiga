package com.uae4arm2026.ui.screens.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.uae4arm2026.R
import com.uae4arm2026.data.model.EmulatorSettings
import com.uae4arm2026.ui.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChipsetTab(viewModel: SettingsViewModel) {
	val settings = viewModel.settings
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
	val chipsetSummary = buildList {
		add(chipsetLabels[settings.chipset] ?: settings.chipset)
		if (settings.cycleExact) add(stringResource(R.string.settings_chipset_cycle_exact))
		if (settings.immediateBlits) add(stringResource(R.string.settings_chipset_immediate_blitter))
		if (settings.ntsc) add(stringResource(R.string.settings_chipset_ntsc))
	}.joinToString(separator = " • ")

	SettingsTabContent {
		SettingsAdaptiveColumns(
			left = {
				OutlinedCard(modifier = Modifier.fillMaxWidth()) {
					Column(modifier = Modifier.padding(16.dp)) {
						Text(stringResource(R.string.settings_chipset_section_title), style = MaterialTheme.typography.titleMedium)
						Spacer(modifier = Modifier.height(8.dp))

						var chipsetExpanded by remember { mutableStateOf(false) }
						ExposedDropdownMenuBox(
							expanded = chipsetExpanded,
							onExpandedChange = { chipsetExpanded = it }
						) {
							val displayName = chipsetLabels[settings.chipset] ?: settings.chipset
							OutlinedTextField(
								value = displayName,
								onValueChange = {},
								readOnly = true,
								label = { Text(stringResource(R.string.settings_chipset_label)) },
								trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = chipsetExpanded) },
								modifier = Modifier
									.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
									.fillMaxWidth()
							)
							ExposedDropdownMenu(
								expanded = chipsetExpanded,
								onDismissRequest = { chipsetExpanded = false }
							) {
								EmulatorSettings.chipsetOptions.forEach { (value, fallbackLabel) ->
									DropdownMenuItem(
										text = { Text(chipsetLabels[value] ?: fallbackLabel) },
										onClick = {
											viewModel.updateSettings { s -> s.copy(chipset = value) }
											chipsetExpanded = false
										}
									)
								}
							}
						}

						Spacer(modifier = Modifier.height(8.dp))

						SettingsSwitchRow(
							label = stringResource(R.string.settings_chipset_immediate_blitter),
							checked = settings.immediateBlits,
							onCheckedChange = { viewModel.updateSettings { s -> s.copy(immediateBlits = it) } }
						)

						SettingsSwitchRow(
							label = stringResource(R.string.settings_chipset_cycle_exact),
							checked = settings.cycleExact,
							onCheckedChange = { viewModel.updateSettings { s -> s.copy(cycleExact = it) } }
						)

						SettingsSwitchRow(
							label = stringResource(R.string.settings_chipset_ntsc),
							checked = settings.ntsc,
							onCheckedChange = { viewModel.updateSettings { s -> s.copy(ntsc = it) } }
						)

						var collisionExpanded by remember { mutableStateOf(false) }
						ExposedDropdownMenuBox(
							expanded = collisionExpanded,
							onExpandedChange = { collisionExpanded = it }
						) {
							val displayName = collisionOptions.firstOrNull { it.first == settings.collisionLevel }?.second ?: settings.collisionLevel
							OutlinedTextField(
								value = displayName,
								onValueChange = {},
								readOnly = true,
								label = { Text(stringResource(R.string.settings_chipset_collision_level_label)) },
								trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = collisionExpanded) },
								modifier = Modifier
									.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
									.fillMaxWidth()
							)
							ExposedDropdownMenu(
								expanded = collisionExpanded,
								onDismissRequest = { collisionExpanded = false }
							) {
								collisionOptions.forEach { (value, label) ->
									DropdownMenuItem(
										text = { Text(label) },
										onClick = {
											viewModel.updateSettings { s -> s.copy(collisionLevel = value) }
											collisionExpanded = false
										}
									)
								}
							}
						}
					}
				}
			},
			right = {
				OutlinedCard(modifier = Modifier.fillMaxWidth()) {
					Column(modifier = Modifier.padding(16.dp)) {
						Text(stringResource(R.string.settings_chipset_summary_title), style = MaterialTheme.typography.titleMedium)
						Spacer(modifier = Modifier.height(8.dp))
						Text(
							text = if (chipsetSummary.isBlank()) {
								stringResource(R.string.settings_chipset_summary_default)
							} else {
								chipsetSummary
							},
							style = MaterialTheme.typography.bodyMedium
						)
						Spacer(modifier = Modifier.height(12.dp))
						Text(
							stringResource(
								R.string.settings_chipset_collision_summary,
								collisionOptions.firstOrNull { it.first == settings.collisionLevel }?.second ?: settings.collisionLevel
							),
							style = MaterialTheme.typography.bodyMedium
						)
					}
				}
			}
		)
	}
}
