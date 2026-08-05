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
import com.uae4arm2026.ui.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InputTab(viewModel: SettingsViewModel) {
    val settings = viewModel.settings
    val portOptions = listOf(
        "none" to stringResource(R.string.settings_input_device_none),
        "joy0" to stringResource(R.string.settings_input_device_joystick_0),
        "joy1" to stringResource(R.string.settings_input_device_joystick_1),
        "mouse" to stringResource(R.string.settings_input_device_mouse),
        "kbd1" to stringResource(R.string.settings_input_device_keyboard_layout_1),
        "kbd2" to stringResource(R.string.settings_input_device_keyboard_layout_2),
        "onscreen_joy" to stringResource(R.string.settings_input_device_on_screen_joystick)
    )

    SettingsTabContent {
        SettingsAdaptiveColumns(
            left = {
                OutlinedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            stringResource(R.string.settings_input_port_assignments_title),
                            style = MaterialTheme.typography.titleMedium
                        )
                        Spacer(modifier = Modifier.height(8.dp))

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
                                            viewModel.updateSettings { state -> state.copy(joyport0 = value) }
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
                                            viewModel.updateSettings { state ->
                                                state.copy(
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
            },
            right = {
            }
        )
    }
}
