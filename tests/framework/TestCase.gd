class_name TestCase
extends RefCounted

## Base class for VOWED tests.
##
## Subclass it, name the file `*_test.gd` under `tests/`, and name each test
## method `test_*`. `TestRunner` discovers the rest.
##
## Assertions record failures instead of halting, so one test reports every
## problem it finds in a single run rather than one problem per run. When combat
## frame data breaks, several assertions usually break together and their
## pattern is the actual diagnosis.

var _failures: PackedStringArray = []
var _assertion_count: int = 0


## Per-test setup. Runs before each `test_*` method on a FRESH instance.
func before_each() -> void:
	pass


## Per-test teardown.
func after_each() -> void:
	pass


# --- assertions -------------------------------------------------------------

func assert_true(value: bool, message: String = "") -> void:
	_assertion_count += 1
	if not value:
		_fail("expected true, got false", message)


func assert_false(value: bool, message: String = "") -> void:
	_assertion_count += 1
	if value:
		_fail("expected false, got true", message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual != expected:
		_fail("expected %s, got %s" % [_show(expected), _show(actual)], message)


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	_assertion_count += 1
	if actual == unexpected:
		_fail("expected value other than %s" % _show(unexpected), message)


func assert_almost_eq(actual: float, expected: float,
		tolerance: float = 0.0001, message: String = "") -> void:
	_assertion_count += 1
	if absf(actual - expected) > tolerance:
		_fail("expected %f +/- %f, got %f (off by %f)"
			% [expected, tolerance, actual, absf(actual - expected)], message)


func assert_gt(actual: float, floor_value: float, message: String = "") -> void:
	_assertion_count += 1
	if actual <= floor_value:
		_fail("expected > %s, got %s" % [floor_value, actual], message)


func assert_lt(actual: float, ceiling: float, message: String = "") -> void:
	_assertion_count += 1
	if actual >= ceiling:
		_fail("expected < %s, got %s" % [ceiling, actual], message)


func assert_ge(actual: float, floor_value: float, message: String = "") -> void:
	_assertion_count += 1
	if actual < floor_value:
		_fail("expected >= %s, got %s" % [floor_value, actual], message)


func assert_null(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if value != null:
		_fail("expected null, got %s" % _show(value), message)


func assert_not_null(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if value == null:
		_fail("expected non-null", message)


func assert_empty(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	var size: int = _size_of(value)
	if size != 0:
		_fail("expected empty, got %d element(s): %s" % [size, _show(value)],
			message)


func assert_not_empty(value: Variant, message: String = "") -> void:
	_assertion_count += 1
	if _size_of(value) == 0:
		_fail("expected non-empty", message)


func assert_size(value: Variant, expected: int, message: String = "") -> void:
	_assertion_count += 1
	var size: int = _size_of(value)
	if size != expected:
		_fail("expected %d element(s), got %d: %s"
			% [expected, size, _show(value)], message)


func assert_contains(haystack: Variant, needle: Variant,
		message: String = "") -> void:
	_assertion_count += 1
	var found: bool = false
	if haystack is String or haystack is StringName:
		found = str(haystack).contains(str(needle))
	elif haystack is Array or haystack is PackedStringArray:
		for item: Variant in haystack:
			if item == needle:
				found = true
				break
	if not found:
		_fail("expected %s to contain %s"
			% [_show(haystack), _show(needle)], message)


## Unconditional failure, for unreachable branches.
func fail(message: String) -> void:
	_assertion_count += 1
	_fail("explicit failure", message)


# --- runner interface -------------------------------------------------------

func _test_failures() -> PackedStringArray:
	return _failures


func _test_assertion_count() -> int:
	return _assertion_count


func _test_reset() -> void:
	_failures = []
	_assertion_count = 0


# --- internals --------------------------------------------------------------

func _fail(detail: String, message: String) -> void:
	var line: String = detail
	if not message.is_empty():
		line = "%s  (%s)" % [message, detail]
	var where: String = _caller_location()
	if not where.is_empty():
		line = "%s\n        at %s" % [line, where]
	_failures.append(line)


## Best-effort source location of the assertion. `get_stack()` is only populated
## in debug builds; tests always run in debug, but the empty case is handled so
## a release run degrades to a message-only failure instead of crashing.
func _caller_location() -> String:
	var stack: Array[Dictionary] = get_stack()
	if stack.is_empty():
		return ""
	for entry: Dictionary in stack:
		var source: String = str(entry.get("source", ""))
		if source.ends_with("_test.gd"):
			return "%s:%d in %s()" % [
				source, int(entry.get("line", 0)), str(entry.get("function", "?")),
			]
	return ""


func _show(value: Variant) -> String:
	if value == null:
		return "null"
	if value is String:
		return "\"%s\"" % value
	if value is StringName:
		return "&\"%s\"" % value
	if value is float:
		return "%.4f" % value
	return str(value)


func _size_of(value: Variant) -> int:
	if value is Array or value is Dictionary or value is String \
			or value is PackedStringArray or value is PackedInt32Array \
			or value is PackedByteArray:
		return value.size()
	if value is StringName:
		return str(value).length()
	return -1
