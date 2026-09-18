class_name AtomicJsonFile
extends RefCounted


## 完整写入临时文件后替换存档，沿用原有备份恢复格式。
## [param path] 原生绝对文件路径。[param document] 隔离且可序列化的完整快照。
## 返回实际写盘结果；失败时保留或恢复上一份正式存档。
static func write_document(path: String, document: Dictionary) -> DomainResult:
	var directory_path := path.get_base_dir()
	var make_error := DirAccess.make_dir_recursive_absolute(directory_path)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return DomainResult.failure(&"persistence.storage_error", "cannot create database directory")
	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null: return DomainResult.failure(&"persistence.storage_error", "cannot open temporary database file")
	file.store_string(JSON.stringify(document, "  "))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK: return DomainResult.failure(&"persistence.storage_error", "cannot write database snapshot")
	var directory := DirAccess.open(directory_path)
	if directory == null: return DomainResult.failure(&"persistence.storage_error", "cannot open database directory")
	var database_name := path.get_file()
	var temporary_name := temporary_path.get_file()
	var backup_name := backup_path.get_file()
	if directory.file_exists(backup_name): directory.remove(backup_name)
	var had_original := directory.file_exists(database_name)
	if had_original and directory.rename(database_name, backup_name) != OK:
		return DomainResult.failure(&"persistence.storage_error", "cannot stage previous database snapshot")
	if directory.rename(temporary_name, database_name) != OK:
		if had_original: directory.rename(backup_name, database_name)
		return DomainResult.failure(&"persistence.storage_error", "cannot install database snapshot")
	if had_original: directory.remove(backup_name)
	return DomainResult.ok()
