class_name AppLanguageController
extends Control

## Language dropdown. The selected locale is persisted in the app config
## file and applied globally through the TranslationServer.

const CONFIG_KEY := "SelectedLanguage"
const DEFAULT_LOCALE := "en_US"

const LOCALES: Dictionary = {
	0: "en_US",
	1: "pt_BR",
	2: "zh_CN",
	3: "es_ES",
	4: "ko_KR",
}

const LOCALE_NAMES: Dictionary = {
	"en_US": "English (US)",
	"pt_BR": "Português (Brasil)",
	"zh_CN": "中文 (简体)",
	"es_ES": "Español (España)",
	"ko_KR": "한국어",
}

@onready var _dropdown: OptionButton = $Panel/OptionButton if has_node("Panel/OptionButton") else null


func _ready() -> void:
	_load_and_apply_saved_locale()
	if not _dropdown:
		return
	_dropdown.clear()
	for id in LOCALES:
		var locale_code: String = LOCALES[id]
		_dropdown.add_item(LOCALE_NAMES.get(locale_code, locale_code), id)
	_dropdown.item_selected.connect(_on_language_selected)
	_update_dropdown_selection()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_update_dropdown_selection()


func _on_language_selected(index: int) -> void:
	if not LOCALES.has(index):
		printerr("Lang: Invalid language index: ", index)
		return
	var selected_locale: String = LOCALES[index]
	if TranslationServer.get_locale() == selected_locale:
		return
	TranslationServer.set_locale(selected_locale)
	_save_locale(selected_locale)


func _update_dropdown_selection() -> void:
	if not is_instance_valid(_dropdown) or _dropdown.get_item_count() == 0:
		return
	var current_locale := TranslationServer.get_locale()
	for id in LOCALES:
		if LOCALES[id] == current_locale:
			if _dropdown.selected != id:
				_dropdown.select(id)
			return
	_dropdown.select(0)


func _load_and_apply_saved_locale() -> void:
	var saved_locale := DEFAULT_LOCALE
	var config = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if config is Dictionary:
		var loaded: String = config.get(CONFIG_KEY, "")
		if loaded in LOCALES.values():
			saved_locale = loaded
	if TranslationServer.get_locale() != saved_locale:
		TranslationServer.set_locale(saved_locale)


func _save_locale(locale_code: String) -> void:
	# Re-read from disk so unrelated config keys are preserved.
	var config = JsonFile.load_data(AppPaths.CONFIG_FILE)
	if not config is Dictionary:
		config = {}
	config[CONFIG_KEY] = locale_code
	if not JsonFile.save_data(AppPaths.CONFIG_FILE, config):
		printerr("Lang: Failed to save the selected language.")
