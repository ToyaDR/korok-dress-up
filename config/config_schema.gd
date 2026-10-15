class_name ConfigSchema
## Checks that the data parsed from the korok config has the fields and types
## the game expects, using Zodot.
##
## Usage:
## [codeblock]
## var checked := ConfigSchema.validate(result.get_data())
## if not checked.ok():
##     push_error(checked.error)
## [/codeblock]
##
## This only checks the form of the data. It does not check that names refer
## to things that exist, for example that a slot accepts a category that is
## listed under `category`.
##
## In Zodot, `.nullable()` is how a key is marked optional, and keys the schema
## does not mention are ignored, so a misspelled optional key passes.


## An [x, y] pair of numbers. Zodot's array validator cannot check length.
class Point extends Zodot:
	func parse(value: Variant, field: String = "") -> ZodotResult:
		if _nullable and value == null:
			return ZodotResult.good(value)

		if typeof(value) != TYPE_ARRAY or value.size() != 2:
			return ZodotResult.constraint_error(field, "Expected [x, y]")

		for n in value:
			if typeof(n) != TYPE_INT and typeof(n) != TYPE_FLOAT:
				return ZodotResult.constraint_error(field, "Expected [x, y] to be numbers")

		return ZodotResult.good(value)


static func validate(data: Variant) -> ZodotResult:
	return _config().parse(data)


static func _config() -> Zodot:
	return Z.schema({
		"version": Z.integer(),
		"canvas": Z.schema({ "size": Point.new() }),
		"property": Z.dictionary(_property()).non_empty(),
		"category": Z.dictionary(_category()).non_empty(),
		"body": _group(),
		"body_part": Z.dictionary(_group()),
		"item": Z.dictionary(_group()),
	})


# YAML gives an int for `33` and a float for `33.5`, and both are fine.
static func _number() -> Zodot:
	return Z.union([Z.integer(), Z.float()])


static func _names() -> Zodot:
	return Z.array(Z.string().non_empty())


static func _property() -> Zodot:
	return Z.schema({
		"values": _names().non_empty().nullable(),
		"type": Z.string().non_empty().nullable(),
		"tints": Z.dictionary(Z.string().non_empty()).nullable(),
	})


static func _category() -> Zodot:
	return Z.schema({
		"label": Z.string().non_empty().nullable(),
		"properties": _names().nullable(),
	})


# The fields a group and an instance share. A group's value applies to every
# instance in it, so each one is optional in both places.
static func _shared_fields() -> Dictionary:
	return {
		"properties": _names().nullable(),
		"variants": _names().nullable(),
		"tint": Z.string().non_empty().nullable(),
		"texture": Z.string().non_empty().nullable(),
		"slots": Z.dictionary(_slot()).nullable(),
	}


static func _group() -> Zodot:
	var fields := _shared_fields()
	fields["instances"] = Z.dictionary(_instance()).non_empty()
	return Z.schema(fields)


static func _instance() -> Zodot:
	var fields := _shared_fields()
	fields["grip"] = Point.new().nullable()
	fields["label"] = Z.string().non_empty().nullable()
	return Z.schema(fields)


static func _slot() -> Zodot:
	return Z.schema({
		"accepts": _names().non_empty(),
		"z": Z.integer(),
		"default": Z.string().non_empty().nullable(),
		"position": Point.new().nullable(),
		"rotation": _number().nullable(),
		"drop_zone": Z.schema({
			"center": Point.new(),
			"radius": _number(),
		}).nullable(),
	})
