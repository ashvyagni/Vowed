extends SceneTree

## Headless test runner for VOWED.
##
##     godot --headless --path . -s tests/framework/TestRunner.gd
##     godot --headless --path . -s tests/framework/TestRunner.gd -- --filter=buffer
##
## Exits 0 when everything passes, 1 otherwise, so it drops straight into a
## pre-commit hook or CI without a wrapper.
##
## WHY AN IN-HOUSE RUNNER INSTEAD OF GUT
##
## GUT is good, and this decision is not a criticism of it. But what this project
## needs to test is overwhelmingly *pure logic*: frame-data validity, combo-graph
## resolution, input-buffer windows, save migrations. That needs discovery,
## assertions and an exit code — roughly 250 lines, all of it under our control.
##
## Against that, an addon brings a dependency to version-track, its own licence
## and provenance record to maintain, and its own upgrade risk at each Godot
## minor release. For this test shape the dependency costs more than it saves.
##
## Revisit at M16 if QA needs what GUT genuinely does better — scene-tree
## integration fixtures, doubles and spies, parameterised tests. Swapping in GUT
## later is cheap because `TestCase`'s assertion surface is deliberately close to
## GUT's, so test bodies would mostly port unchanged.

const TEST_DIRS: PackedStringArray = ["res://tests/unit", "res://tests/integration"]
const TEST_SUFFIX: String = "_test.gd"

var _files_run: int = 0
var _tests_run: int = 0
var _tests_passed: int = 0
var _tests_failed: int = 0
var _assertions: int = 0
var _failure_report: PackedStringArray = []
var _filter: String = ""


func _initialize() -> void:
	_parse_args()

	var start_usec: int = Time.get_ticks_usec()
	var files: PackedStringArray = _discover()

	if files.is_empty():
		print("No test files found under %s" % ", ".join(TEST_DIRS))
		quit(1)
		return

	print("Running %d test file(s)%s\n" % [
		files.size(),
		"" if _filter.is_empty() else " matching '%s'" % _filter,
	])

	for path: String in files:
		_run_file(path)

	var elapsed_ms: float = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_print_summary(elapsed_ms)
	quit(0 if _tests_failed == 0 else 1)


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			_filter = arg.substr("--filter=".length())


func _discover() -> PackedStringArray:
	var found: PackedStringArray = []
	for dir_path: String in TEST_DIRS:
		_scan(dir_path, found)
	found.sort()
	return found


func _scan(dir_path: String, into: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan(full, into)
		elif entry.ends_with(TEST_SUFFIX):
			if _filter.is_empty() or full.containsn(_filter):
				into.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _run_file(path: String) -> void:
	var script: Resource = load(path)
	if script == null or not script is GDScript:
		_record_file_error(path, "could not be loaded as a GDScript")
		return

	var gd: GDScript = script as GDScript
	var probe: Variant = gd.new()
	if probe == null:
		_record_file_error(path, "could not be instantiated")
		return
	if not probe is TestCase:
		_record_file_error(path, "does not extend TestCase")
		return

	var method_names: PackedStringArray = _test_methods(probe as TestCase)
	if method_names.is_empty():
		_record_file_error(path, "contains no test_* methods")
		return

	_files_run += 1
	print("  %s" % path.replace("res://tests/", ""))

	for method_name: String in method_names:
		# A fresh instance per test: shared state between tests is how a suite
		# starts passing or failing depending on execution order, which makes it
		# worse than no suite at all.
		var instance: TestCase = gd.new() as TestCase
		if instance == null:
			_record_file_error(path, "failed to instantiate for %s" % method_name)
			continue
		_run_one(path, instance, method_name)

	print("")


func _test_methods(probe: TestCase) -> PackedStringArray:
	var names: PackedStringArray = []
	for method: Dictionary in probe.get_method_list():
		var method_name: String = str(method.get("name", ""))
		if method_name.begins_with("test_") \
				and int(method.get("args", [] as Array).size()) == 0:
			if not names.has(method_name):
				names.append(method_name)
	names.sort()
	return names


func _run_one(path: String, instance: TestCase, method_name: String) -> void:
	_tests_run += 1
	instance._test_reset()

	instance.before_each()
	instance.call(method_name)
	instance.after_each()

	var failures: PackedStringArray = instance._test_failures()
	_assertions += instance._test_assertion_count()

	if failures.is_empty():
		_tests_passed += 1
		print("    \u001b[32mPASS\u001b[0m %s  (%d assertion%s)" % [
			method_name, instance._test_assertion_count(),
			"" if instance._test_assertion_count() == 1 else "s",
		])
	else:
		_tests_failed += 1
		print("    \u001b[31mFAIL\u001b[0m %s  (%d failure%s)" % [
			method_name, failures.size(), "" if failures.size() == 1 else "s",
		])
		for failure: String in failures:
			print("        - %s" % failure)
		_failure_report.append("%s :: %s" % [
			path.replace("res://tests/", ""), method_name,
		])


func _record_file_error(path: String, reason: String) -> void:
	_tests_failed += 1
	print("  \u001b[31mERROR\u001b[0m %s — %s" % [path, reason])
	_failure_report.append("%s (%s)" % [path, reason])


func _print_summary(elapsed_ms: float) -> void:
	print("".lpad(62, "-"))
	if _tests_failed == 0:
		print("\u001b[32mALL PASS\u001b[0m  %d test(s) in %d file(s), %d assertion(s), %.1f ms" % [
			_tests_run, _files_run, _assertions, elapsed_ms,
		])
		return

	print("\u001b[31mFAILED\u001b[0m  %d of %d test(s) failed  (%d assertion(s), %.1f ms)" % [
		_tests_failed, _tests_run, _assertions, elapsed_ms,
	])
	print("")
	for line: String in _failure_report:
		print("  %s" % line)
