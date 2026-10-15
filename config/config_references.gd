class_name ConfigReferences
## Checks the rules in the korok config that span more than one entry: names
## that have to refer to something defined elsewhere, and properties a category
## requires of its instances.
##
## Run it after ConfigSchema has passed. It relies on the fields and types
## that ConfigSchema checks, and does not check them again.
##
## Usage:
## [codeblock]
## for error in ConfigReferences.check(config):
##     push_error(error)
## [/codeblock]
##
## A group is an entry with an `instances` list: `body`, each entry under
## `body_part`, and each entry under `item`. A group's path, like
## `body_part.face`, is also the name of its category.


## Returns every problem found, or an empty array when the config is consistent.
static func check(config: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var groups := get_groups(config)

	_check_properties(config, errors)
	_check_categories(config, groups, errors)
	for path in groups:
		_check_group(config, groups, path, errors)

	return errors


## Every group in the config, by its path.
static func get_groups(config: Dictionary) -> Dictionary:
	var groups := { "body": config.body }
	for section in ["body_part", "item"]:
		for group_name in config[section]:
			groups["%s.%s" % [section, group_name]] = config[section][group_name]

	return groups


# A property is either a choice with `values` or a fixed value with a `type`.
static func _check_properties(config: Dictionary, errors: Array[String]) -> void:
	for property_name in config.property:
		var property: Dictionary = config.property[property_name]
		if property.has("values") == property.has("type"):
			errors.append("property.%s needs either `values` or `type`, and not both" % property_name)

		if property.has("tints"):
			_check_tints(property_name, property, errors)


# Every value needs a tint, or choosing it would leave nothing to draw with.
static func _check_tints(property_name: String, property: Dictionary, errors: Array[String]) -> void:
	for value in property.get("values", []):
		if not property.tints.has(value):
			errors.append("property.%s has no tint for '%s'" % [property_name, value])

	for value in property.tints:
		if not property.get("values", []).has(value):
			errors.append("property.%s has a tint for '%s', which is not one of its values" % [property_name, value])

		elif not Color.html_is_valid(property.tints[value]):
			errors.append("property.%s tint for '%s' is not a color: %s" % [property_name, value, property.tints[value]])


static func _check_categories(config: Dictionary, groups: Dictionary, errors: Array[String]) -> void:
	for category_name in config.category:
		if not groups.has(category_name):
			errors.append("category '%s' has no entry at that path" % category_name)

		var required: Array = config.category[category_name].get("properties", [])
		_check_defined(config, required, "category '%s'" % category_name, errors)


static func _check_group(config: Dictionary, groups: Dictionary, path: String, errors: Array[String]) -> void:
	var group: Dictionary = groups[path]
	var required: Array = config.category.get(path, {}).get("properties", [])

	_check_slots(config, groups, path, group.get("slots", {}), errors)

	for id in group.instances:
		var instance: Dictionary = group.instances[id]
		var where := "%s.instances.%s" % [path, id]
		var fields := instance_fields(group, instance)
		var supported: Array = required + group.get("properties", []) + instance.get("properties", [])

		_check_defined(config, supported, where, errors)
		_check_required_values(config, required, fields, where, errors)
		_check_variants(config, supported, fields, where, errors)
		_check_tint(config, supported, fields, where, errors)
		_check_slots(config, groups, where, instance.get("slots", {}), errors)


## What an instance ends up with: the group's fields, with its own on top.
static func instance_fields(group: Dictionary, instance: Dictionary) -> Dictionary:
	var fields := group.duplicate()
	fields.erase("instances")
	fields.merge(instance, true)
	return fields


static func _check_defined(config: Dictionary, property_names: Array, where: String, errors: Array[String]) -> void:
	for property_name in property_names:
		if not config.property.has(property_name):
			errors.append("%s uses property '%s', which is not defined under `property`" % [where, property_name])


# A choice like color gets its value while the game runs, when the player
# picks one. A typed property like grip has no other source, so the instance
# or its group has to give one.
static func _check_required_values(config: Dictionary, required: Array, fields: Dictionary, where: String, errors: Array[String]) -> void:
	for property_name in required:
		var property: Dictionary = config.property.get(property_name, {})
		if property.has("type") and not fields.has(property_name):
			errors.append("%s has no '%s', which its category requires" % [where, property_name])


static func _check_variants(config: Dictionary, supported: Array, fields: Dictionary, where: String, errors: Array[String]) -> void:
	if not fields.has("texture"):
		errors.append("%s has no texture" % where)
		return

	for property_name in fields.get("variants", []):
		if not supported.has(property_name):
			errors.append("%s has variant '%s', which is not one of its properties" % [where, property_name])
			continue

		if not config.property.get(property_name, {}).has("values"):
			errors.append("%s has variant '%s', which is not a choice with `values`" % [where, property_name])

		if not fields.texture.contains("{%s}" % property_name):
			errors.append("%s has variant '%s' but its texture has no {%s} placeholder" % [where, property_name, property_name])


static func _check_tint(config: Dictionary, supported: Array, fields: Dictionary, where: String, errors: Array[String]) -> void:
	if not fields.has("tint"):
		return

	var property_name: String = fields.tint
	if not supported.has(property_name):
		errors.append("%s is tinted by '%s', which is not one of its properties" % [where, property_name])

	elif not config.property.get(property_name, {}).has("tints"):
		errors.append("%s is tinted by '%s', which has no `tints`" % [where, property_name])


static func _check_slots(config: Dictionary, groups: Dictionary, where: String, slots: Dictionary, errors: Array[String]) -> void:
	for slot_name in slots:
		var slot: Dictionary = slots[slot_name]
		var slot_where := "%s.slots.%s" % [where, slot_name]

		for category_name in slot.accepts:
			if not config.category.has(category_name):
				errors.append("%s accepts '%s', which is not listed under `category`" % [slot_where, category_name])

		if slot.has("default") and not _accepts_instance(groups, slot, slot.default):
			errors.append("%s has default '%s', which is not an instance of a category it accepts" % [slot_where, slot.default])


static func _accepts_instance(groups: Dictionary, slot: Dictionary, id: String) -> bool:
	for category_name in slot.accepts:
		if groups.get(category_name, {}).get("instances", {}).has(id):
			return true

	return false
