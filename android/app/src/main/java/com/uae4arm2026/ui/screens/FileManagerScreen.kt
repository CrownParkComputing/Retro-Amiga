package com.uae4arm2026.ui.screens

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.uae4arm2026.R
import com.uae4arm2026.data.FileManager
import com.uae4arm2026.data.model.AmigaFile
import com.uae4arm2026.data.model.FileCategory
import com.uae4arm2026.ui.components.StoragePermissionBanner
import com.uae4arm2026.ui.viewmodel.FileManagerViewModel

private fun pathToInitialUri(path: String): Uri? {
	val extRoot = Environment.getExternalStorageDirectory().absolutePath
	val docId = if (path.startsWith(extRoot)) {
		"primary:" + path.removePrefix(extRoot).trimStart('/')
	} else {
		val m = Regex("^/storage/([^/]+)(/.*)?$").find(path) ?: return null
		val vol = m.groupValues[1]
		val rel = m.groupValues[2].trimStart('/')
		"$vol:$rel"
	}
	return DocumentsContract.buildDocumentUri(
		"com.android.externalstorage.documents", docId
	)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileManagerScreen(
	initialSection: Int = 0,
	showSectionTabs: Boolean = true,
	@Suppress("UNUSED_PARAMETER") showTopBar: Boolean = true,
	navController: androidx.navigation.NavController? = null,
	viewModel: FileManagerViewModel = viewModel()
) {
	val context = LocalContext.current
	val snackbarHostState = remember { SnackbarHostState() }
	var selectedSection by rememberSaveable { mutableIntStateOf(initialSection.coerceIn(0, 1)) }
	var selectedTab by rememberSaveable { mutableIntStateOf(0) }
	val showingDownloads = selectedSection == 1

	val tabs = listOf(
		TabInfo(FileCategory.ROMS, "Kickstarts"),
		TabInfo(FileCategory.WHDLOAD_GAMES, "WHDLoad"),
		TabInfo(FileCategory.FLOPPIES, "Floppies"),
		TabInfo(FileCategory.HARD_DRIVES, "HDF"),
		TabInfo(FileCategory.CD_IMAGES, "CD")
	)
	
	var searchQuery by rememberSaveable { mutableStateOf("") }
	val currentCategory = tabs[selectedTab].category
	val allFiles by when (currentCategory) {
		FileCategory.ROMS -> viewModel.roms
		FileCategory.FLOPPIES -> viewModel.floppies
		FileCategory.HARD_DRIVES -> viewModel.hardDrives
		FileCategory.CD_IMAGES -> viewModel.cdImages
		FileCategory.WHDLOAD_GAMES -> viewModel.whdloadGames
	}.collectAsState()

	val files = if (searchQuery.isBlank()) allFiles
		else allFiles.filter { it.name.contains(searchQuery, ignoreCase = true) }

	val importResult by viewModel.importResult.collectAsState()
	val isScanning by viewModel.isScanning.collectAsState()
	val isImporting by viewModel.isImporting.collectAsState()
	val showProgress = isScanning || isImporting
	
	val folderPickerLauncher = rememberLauncherForActivityResult(
		contract = ActivityResultContracts.OpenDocumentTree()
	) { uri ->
		viewModel.setCategoryLibraryPath(currentCategory, uri)
	}
	val currentLibraryPath = viewModel.getCategoryLibraryPath(currentCategory)

	fun launchFolderPicker() {
		val dir = FileManager.getEffectiveCategoryDir(context, currentCategory)
		val initialUri = if (dir.exists()) pathToInitialUri(dir.absolutePath) else null
		folderPickerLauncher.launch(initialUri)
	}

	LaunchedEffect(importResult) {
		importResult?.let { msg ->
			snackbarHostState.showSnackbar(msg)
			viewModel.clearImportResult()
		}
	}

	Scaffold(
		snackbarHost = { SnackbarHost(snackbarHostState) }
	) { innerPadding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.padding(innerPadding)
		) {
			StoragePermissionBanner(
				modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
			)

			// ULTRA COMPACT HEADER WITH HOME BUTTON
			Row(
				modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
				verticalAlignment = Alignment.CenterVertically
			) {
				if (navController != null) {
					IconButton(onClick = {
						navController.navigate(com.uae4arm2026.ui.navigation.Screen.Configurations.route) {
							popUpTo(com.uae4arm2026.ui.navigation.Screen.Configurations.route) { inclusive = true }
						}
					}, modifier = Modifier.size(32.dp)) {
						Icon(Icons.Default.Home, contentDescription = "Home", modifier = Modifier.size(20.dp))
					}
					Spacer(modifier = Modifier.width(8.dp))
				}

				// SEARCH BAR
				Box(
					modifier = Modifier
						.weight(1f)
						.height(32.dp)
						.background(MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.small)
						.padding(horizontal = 12.dp),
					contentAlignment = Alignment.CenterStart
				) {
					if (searchQuery.isEmpty()) {
						Text(
							text = stringResource(R.string.search_placeholder),
							style = MaterialTheme.typography.bodySmall,
							color = MaterialTheme.colorScheme.onSurfaceVariant
						)
					}
					BasicTextField(
						value = searchQuery,
						onValueChange = { searchQuery = it },
						modifier = Modifier.fillMaxWidth(),
						singleLine = true,
						textStyle = MaterialTheme.typography.bodySmall.copy(color = MaterialTheme.colorScheme.onSurface)
					)
				}
			}

			// COMPACT SECTION TABS (Library / Downloads)
			if (showSectionTabs) {
				LazyRow(
					modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
					horizontalArrangement = Arrangement.spacedBy(8.dp),
					contentPadding = PaddingValues(vertical = 4.dp)
				) {
					item {
						FilterChip(
							selected = selectedSection == 0,
							onClick = { selectedSection = 0 },
							label = { Text("Library", style = MaterialTheme.typography.labelSmall) },
							modifier = Modifier.height(28.dp)
						)
					}
					item {
						FilterChip(
							selected = selectedSection == 1,
							onClick = { selectedSection = 1 },
							label = { Text("Downloads", style = MaterialTheme.typography.labelSmall) },
							modifier = Modifier.height(28.dp)
						)
					}
				}
			}

			if (showingDownloads) {
				ArchiveDownloadsPane(
					viewModel = viewModel,
					modifier = Modifier.weight(1f)
				)
			} else {
				// COMPACT CATEGORY TABS (No Icons)
				LazyRow(
					modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
					horizontalArrangement = Arrangement.spacedBy(4.dp),
					contentPadding = PaddingValues(vertical = 2.dp)
				) {
					items(tabs.size) { index ->
						FilterChip(
							selected = selectedTab == index,
							onClick = { selectedTab = index; searchQuery = "" },
							label = { Text(tabs[index].title, style = MaterialTheme.typography.labelSmall) },
							modifier = Modifier.height(28.dp)
						)
					}
				}

				// MINIMAL LIBRARY HEADER
				Row(
					modifier = Modifier
						.fillMaxWidth()
						.padding(horizontal = 16.dp, vertical = 4.dp),
					verticalAlignment = Alignment.CenterVertically
				) {
					Text(
						text = currentLibraryPath ?: "Default Storage",
						style = MaterialTheme.typography.labelSmall,
						fontFamily = FontFamily.Monospace,
						color = MaterialTheme.colorScheme.onSurfaceVariant,
						maxLines = 1,
						overflow = TextOverflow.Ellipsis,
						modifier = Modifier.weight(1f)
					)
					IconButton(onClick = { launchFolderPicker() }, modifier = Modifier.size(24.dp)) {
						Icon(Icons.Default.CreateNewFolder, contentDescription = null, modifier = Modifier.size(16.dp))
					}
					if (currentLibraryPath != null) {
						IconButton(onClick = { viewModel.clearCategoryLibraryPath(currentCategory) }, modifier = Modifier.size(24.dp)) {
							Icon(Icons.Default.Delete, contentDescription = null, modifier = Modifier.size(16.dp))
						}
					}
				}

				if (showProgress) {
					LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
				}

				LazyColumn(
					modifier = Modifier.weight(1f),
					contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
					verticalArrangement = Arrangement.spacedBy(2.dp)
				) {
					items(files, key = { it.path }) { file ->
						FileItemMinimal(
							file = file,
							onDelete = { viewModel.deleteFile(file) }
						)
					}
				}
			}
		}
	}
}

@Composable
private fun FileItemMinimal(file: AmigaFile, onDelete: () -> Unit) {
	var showDeleteDialog by remember { mutableStateOf(false) }

	Row(
		modifier = Modifier
			.fillMaxWidth()
			.height(36.dp)
			.clickable { /* Pick logic handled elsewhere or via Home */ }
			.padding(horizontal = 4.dp),
		verticalAlignment = Alignment.CenterVertically
	) {
		Column(modifier = Modifier.weight(1f)) {
			Text(
				text = file.name, 
				style = MaterialTheme.typography.bodySmall,
				maxLines = 1,
				overflow = TextOverflow.Ellipsis
			)
			Text(
				text = file.sizeDisplay,
				style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
				color = MaterialTheme.colorScheme.onSurfaceVariant
			)
		}
		IconButton(onClick = { showDeleteDialog = true }, modifier = Modifier.size(24.dp)) {
			Icon(
				Icons.Default.Delete,
				contentDescription = null,
				modifier = Modifier.size(14.dp),
				tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
			)
		}
	}

	if (showDeleteDialog) {
		AlertDialog(
			onDismissRequest = { showDeleteDialog = false },
			title = { Text("Delete file?") },
			text = { Text("Delete ${file.name}?") },
			confirmButton = {
				TextButton(onClick = {
					onDelete()
					showDeleteDialog = false
				}) {
					Text("Delete", color = MaterialTheme.colorScheme.error)
				}
			},
			dismissButton = {
				TextButton(onClick = { showDeleteDialog = false }) {
					Text("Cancel")
				}
			}
		)
	}
}

private data class TabInfo(
	val category: FileCategory,
	val title: String
)
