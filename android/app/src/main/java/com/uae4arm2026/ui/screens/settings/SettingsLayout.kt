package com.uae4arm2026.ui.screens.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

@Composable
fun SettingsSectionHeader(title: String) {
	Text(
		text = title,
		style = MaterialTheme.typography.titleSmall,
		color = MaterialTheme.colorScheme.primary,
		modifier = Modifier.padding(top = 4.dp)
	)
}

@Composable
fun <T> SettingsRadioGroup(
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
fun SettingsSwitchRow(
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsHardwareDropdown(label: String, selected: String, options: List<String>, onSelect: (String) -> Unit) {
	var expanded by remember { mutableStateOf(false) }
	ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
		OutlinedTextField(
			value = selected,
			onValueChange = {},
			readOnly = true,
			label = { Text(label) },
			trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
			modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)
		)
		ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
			options.forEach { option ->
				DropdownMenuItem(text = { Text(option) }, onClick = { onSelect(option); expanded = false })
			}
		}
	}
}

@Composable
fun SettingsTabContent(
	modifier: Modifier = Modifier,
	content: @Composable ColumnScope.() -> Unit
) {
	Column(
		modifier = modifier
			.fillMaxWidth()
			.verticalScroll(rememberScrollState())
			.padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 120.dp),
		verticalArrangement = Arrangement.spacedBy(16.dp),
		content = content
	)
}

@Composable
fun SettingsAdaptiveColumns(
	modifier: Modifier = Modifier,
	left: @Composable ColumnScope.() -> Unit,
	right: (@Composable ColumnScope.() -> Unit)? = null
) {
	BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
		val useTwoColumns = right != null && maxWidth >= 600.dp
		if (useTwoColumns) {
			Row(
				modifier = Modifier.fillMaxWidth(),
				horizontalArrangement = Arrangement.spacedBy(16.dp)
			) {
				Column(
					modifier = Modifier.weight(1f),
					verticalArrangement = Arrangement.spacedBy(16.dp),
					content = left
				)
				Column(
					modifier = Modifier.weight(1f),
					verticalArrangement = Arrangement.spacedBy(16.dp),
					content = right!!
				)
			}
		} else {
			Column(
				modifier = Modifier.fillMaxWidth(),
				verticalArrangement = Arrangement.spacedBy(16.dp)
			) {
				left()
				right?.invoke(this)
			}
		}
	}
}
