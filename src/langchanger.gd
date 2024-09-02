extends Control

@onready var language_selector = $OptionButton  # Substitua pelo caminho correto

var config_file_path = "res://config.json"  # Caminho do arquivo config.json
var selected_language: String = "--locale=en_US"  # Variável para armazenar o parâmetro de inicialização

func _ready():
	if language_selector == null:
		print("Erro: LanguageSelector não encontrado!")
		return
	
	language_selector.add_item("English", 0)          # Inglês
	language_selector.add_item("Português", 1)        # Português
	language_selector.add_item("Türkçe", 2)           # Turco
	language_selector.add_item("Deutsch", 3)          # Alemão
	language_selector.add_item("Español", 4)          # Espanhol
	language_selector.add_item("Français", 5)         # Francês
	language_selector.add_item("Italiano", 6)         # Italiano
	language_selector.add_item("Čeština", 7)          # Tcheco
	language_selector.add_item("Ελληνικά", 8)         # Grego
	language_selector.add_item("Magyar", 9)           # Húngaro
	language_selector.add_item("Polski", 10)          # Polonês
	language_selector.add_item("Română", 11)          # Romeno
	language_selector.add_item("Русский", 12)         # Russo
	language_selector.add_item("日本語", 13)          # Japonês
	language_selector.add_item("한국어", 14)          # Coreano
	language_selector.add_item("简体中文", 15)         # Chinês (Simplificado)

	language_selector.connect("item_selected", Callable(self, "_on_language_selected"))

func _on_language_selected(index):

	selected_language = _selected_lang(index)
	print("Linguagem selecionada: ", selected_language)
	
	var config_data = _load_config_file()
	
	if config_data == {}:
		print("Erro ao carregar config.json")
		return
	
	if "launcher_settings" in config_data:
		config_data["launcher_settings"]["launcher_lang"] = selected_language
	else:
		print("Erro: launcher_settings não encontrado no config.json")
		return
	
	_save_config_file(config_data)

func _selected_lang(index):
	match index:
		0:
			return "--locale=en_US"  # Inglês
		1:
			return "--locale=pt_BR"  # Português
		2:
			return "--locale=tr_TR"  # Turco
		3:
			return "--locale=de_DE"  # Alemão
		4:
			return "--locale=es_ES"  # Espanhol
		5:
			return "--locale=fr_FR"  # Francês
		6:
			return "--locale=it_IT"  # Italiano
		7:
			return "--locale=cs_CZ"  # Tcheco
		8:
			return "--locale=el_GR"  # Grego
		9:
			return "--locale=hu_HU"  # Húngaro
		10:
			return "--locale=pl_PL"  # Polonês
		11:
			return "--locale=ro_RO"  # Romeno
		12:
			return "--locale=ru_RU"  # Russo
		13:
			return "--locale=ja_JP"  # Japonês
		14:
			return "--locale=ko_KR"  # Coreano
		15:
			return "--locale=zh_CN"  # Chinês (Simplificado)

func _load_config_file() -> Dictionary:

	if FileAccess.file_exists(config_file_path):
		var file = FileAccess.open(config_file_path, FileAccess.READ)
		var config_data = JSON.parse_string(file.get_as_text())
		file.close()
		if config_data != null and config_data is Dictionary:
			return config_data
	return {}

func _save_config_file(config_data: Dictionary):

	var file = FileAccess.open(config_file_path, FileAccess.WRITE)
	var json_string = JSON.stringify(config_data, "\t")
	file.store_string(json_string)
	file.close()
