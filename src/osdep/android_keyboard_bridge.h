#pragma once

void android_toggle_virtual_keyboard();
void android_hide_virtual_keyboard();
void android_show_pause_menu();

extern "C" void android_set_pause(bool paused);
extern "C" void android_insert_floppy(int drive, const char* path);
extern "C" void android_eject_floppy(int drive);
