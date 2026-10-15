class_name KorokConfig
## The korok config as typed objects, built from the dictionary the YAML
## parser returns.
##
## Build it only after ConfigSchema and ConfigReferences have both passed.
## Nothing here checks the data again, so a missing key is a runtime error.
##
## Usage:
## [codeblock]
## var config := KorokConfig.from_dict(data)
## var flying := config.bodies["flying"]
## var hand := flying.slots["left_hand"]
## for item in config.instances_for(hand):
##     print(item.id, item.texture_path())
## [/codeblock]
##
## Bodies, body parts and items are all an Instance, because they have the same
## form in the config. An Instance already includes what its group and its
## category give it, so the game never has to look those up.
##
## A Slot refers to categories by name, and an Instance to its category by
## name, so that these objects do not point at each other in a loop. Godot
## frees an object when nothing refers to it, and a loop would never be freed.

const ASSET_ROOT := "res://assets/"

var canvas_size: Vector2

## Property name to Property: "color", "grip".
var properties: Dictionary[String, Property] = {}

## Body id to its Instance: "standing", "handsup", "flying".
var bodies: Dictionary[String, Instance] = {}

## Category name to Category: "body_part.face", "item.held".
var categories: Dictionary[String, Category] = {}


static func from_dict(data: Dictionary) -> KorokConfig:
  var config := KorokConfig.new()
  config.canvas_size = to_vector(data.canvas.size)

  for property_name in data.property:
    config.properties[property_name] = Property.from_dict(property_name, data.property[property_name])

  # Bodies are not in a category, so nothing is required of them.
  config.bodies = build_instances("body", data.body, [], config.properties)

  var groups := ConfigReferences.get_groups(data)
  for category_name in data.category:
    config.categories[category_name] = Category.from_dict(
      category_name, data.category[category_name], groups[category_name], config.properties)

  # Set defaults for slot-dependent instances, e.g. the nose needs a holder to find its picture.
  for instance in config.all_instances():
    for slot in instance.slots.values():
      slot.default = config.default_for(slot)

  return config


## The whole config as plain dictionaries and arrays, for printing:
## [codeblock]
## print(JSON.stringify(config.to_dict(), "  "))
## [/codeblock]
## Every class here has a to_dict, so one instance or slot prints the same way.
## The result is not the YAML form. Each instance appears with its group's and
## category's fields already included.
func to_dict() -> Dictionary:
  return {
    "canvas": { "size": from_vector(canvas_size) },
    "property": to_dicts(properties),
    "body": to_dicts(bodies),
    "category": to_dicts(categories),
  }


static func build_instances(category_name: String, group: Dictionary, required: Array,
    defined: Dictionary[String, Property]) -> Dictionary[String, Instance]:
  var instances: Dictionary[String, Instance] = {}
  for id in group.instances:
    var own: Dictionary = group.instances[id]
    var fields := ConfigReferences.instance_fields(group, own)

    # Read from the instance's own entry. The merged fields would give an
    # instance without a label its group's label.
    var label: String = own.get("label", id.capitalize())
    instances[id] = Instance.from_dict(id, label, category_name, fields, required, defined)

  return instances


static func to_vector(pair: Array) -> Vector2:
  return Vector2(pair[0], pair[1])


static func to_properties(property_names: Array, defined: Dictionary[String, Property]) -> Array[Property]:
  var found: Array[Property] = []
  for property_name in property_names:
    found.append(defined[property_name])

  return found


static func from_vector(vector: Vector2) -> Array:
  return [vector.x, vector.y]


# A property is written as its name, so its values are not repeated under
# every instance that has it.
static func to_names(listed: Array[Property]) -> Array:
  return listed.map(func(property: Property) -> String: return property.name)


## Calls to_dict on every value of a dictionary of config objects.
static func to_dicts(objects: Dictionary) -> Dictionary:
  var plain := {}
  for key in objects:
    plain[key] = objects[key].to_dict()

  return plain


## Every instance that can go in the slot.
func instances_for(slot: Slot) -> Array[Instance]:
  var found: Array[Instance] = []
  for category_name in slot.accepts:
    found.append_array(categories[category_name].instances.values())

  return found


## The instance a slot starts with, or null when it has no default.
func default_for(slot: Slot) -> Instance:
  for instance in instances_for(slot):
    if instance.id == slot.default_id:
      return instance

  return null


## The first instance with a slot that accepts this one, or null when nothing
## does. A texture path with {holder} needs it to show the instance on its own,
## like when it's in the grid
func first_holder_for(instance: Instance) -> Instance:
  for candidate in all_instances():
    for slot in candidate.slots.values():
      if slot.accepts.has(instance.category):
        return candidate

  return null


## Bodies first, then every category's instances.
func all_instances() -> Array[Instance]:
  var found: Array[Instance] = []
  found.assign(bodies.values())
  for category in categories.values():
    found.append_array(category.instances.values())

  return found


class Property:
  var name: String

  ## The choices the player has. Empty when the property is not a choice.
  var values: Array[String] = []

  ## The kind of fixed value each instance gives. Empty for a choice.
  var type: String

  ## Value to the color it is drawn in, for instances tinted by this property.
  var tints: Dictionary[String, Color] = {}

  func is_choice() -> bool:
    return not values.is_empty()

  static func from_dict(property_name: String, data: Dictionary) -> Property:
    var property := Property.new()
    property.name = property_name
    property.values.assign(data.get("values", []))
    property.type = data.get("type", "")

    var tint_data: Dictionary = data.get("tints", {})
    for value in tint_data:
      property.tints[value] = Color(tint_data[value])

    return property

  func to_dict() -> Dictionary:
    if not is_choice():
      return { "type": type }

    var plain := { "values": values }
    if not tints.is_empty():
      var tint_text := {}
      for value in tints:
        tint_text[value] = "#" + tints[value].to_html(false)

      plain["tints"] = tint_text

    return plain


class Category:
  var name: String
  var label: String

  ## What every instance in the category has to support.
  var required: Array[Property] = []

  ## Instance id to Instance.
  var instances: Dictionary[String, Instance] = {}

  static func from_dict(category_name: String, data: Dictionary, group: Dictionary,
      defined: Dictionary[String, Property]) -> Category:
    var required_names: Array = data.get("properties", [])
    var lbl: String = data.get("label", category_name.capitalize())

    var category := Category.new()
    category.name = category_name
    category.label = lbl
    category.required = KorokConfig.to_properties(required_names, defined)
    category.instances = KorokConfig.build_instances(category_name, group, required_names, defined)
    return category

  func to_dict() -> Dictionary:
    return {
      "label": label,
      "properties": KorokConfig.to_names(required),
      "instances": KorokConfig.to_dicts(instances),
    }


class Slot:
  var name: String

  ## Names of the categories the slot takes.
  var accepts: Array[String] = []

  ## Z index of the slot, for drawing order.
  var z: int

  ## Id of the instance put in the slot when its owner is chosen, or "".
  var default_id: String

  ## That instance itself, or null.
  var default: Instance

  ## False when whatever goes in the slot is already placed on the canvas.
  ## `position` and `rotation` only mean something when this is true.
  var has_position: bool
  var position: Vector2
  var rotation: float

  ## Radius is 0 when nothing can be dropped on the slot.
  var drop_center: Vector2
  var drop_radius: float

  static func from_dict(slot_name: String, data: Dictionary) -> Slot:
    var slot := Slot.new()
    slot.name = slot_name
    slot.accepts.assign(data.accepts)
    slot.z = data.z
    slot.default_id = data.get("default", "")

    slot.has_position = data.has("position")
    if slot.has_position:
      slot.position = KorokConfig.to_vector(data.position)
      slot.rotation = data.get("rotation", 0)

    if data.has("drop_zone"):
      slot.drop_center = KorokConfig.to_vector(data.drop_zone.center)
      slot.drop_radius = data.drop_zone.radius

    return slot

  # Leaves out what the slot does not have, as the YAML does.
  func to_dict() -> Dictionary:
    var plain := { "accepts": accepts, "z": z }
    if default_id != "":
      plain["default"] = default_id

    if has_position:
      plain["position"] = KorokConfig.from_vector(position)
      plain["rotation"] = rotation

    if drop_radius > 0:
      plain["drop_zone"] = {
        "center": KorokConfig.from_vector(drop_center),
        "radius": drop_radius,
      }

    return plain


class Instance:
  var id: String

  ## The name shown to the player, without any variant values.
  var label: String

  ## Name of the category the instance is in, or "body" for a body.
  var category: String

  ## Everything the instance supports: what its category requires, what its
  ## group lists, and what it lists itself.
  var properties: Array[Property] = []

  ## The properties that pick which texture is drawn.
  var variants: Array[Property] = []

  ## The property whose tint the texture is multiplied by, or null.
  var tint: Property

  ## The texture path as written, placeholders included.
  var texture: String

  ## Slot name to Slot.
  var slots: Dictionary[String, Slot] = {}

  ## Only held items have a grip.
  var has_grip: bool
  var grip: Vector2

  ## Fills in the texture's placeholders. `values` has one entry per
  ## placeholder other than {id}, for example
  ## { "holder": "red-chevron", "color": "blue" }.
  func texture_path(values: Dictionary = {}) -> String:
    var filled := values.duplicate()
    filled["id"] = id
    return KorokConfig.ASSET_ROOT + texture.format(filled)

  ## Every property the player picks a value for: the variants, then the tint.
  func choices() -> Array[Property]:
    var picked := variants.duplicate()
    if tint != null and not picked.has(tint):
      picked.append(tint)

    return picked

  ## The color to multiply the texture by. White, which changes nothing, when
  ## the instance has no tint or `values` has no value for it.
  func tint_for(values: Dictionary) -> Color:
    if tint == null or not values.has(tint.name):
      return Color.WHITE

    return tint.tints[values[tint.name]]

  ## The label for one variant of this instance, for example "Standing, Blue"
  ## for { "color": "blue" }. With no values it is the label alone.
  func label_for(values: Dictionary = {}) -> String:
    var parts: Array[String] = [label]
    for value in values.values():
      parts.append(String(value).capitalize())

    return ", ".join(parts)

  static func from_dict(instance_id: String, instance_label: String, category_name: String,
      fields: Dictionary, required: Array, defined: Dictionary[String, Property]) -> Instance:
    var instance := Instance.new()
    instance.id = instance_id
    instance.label = instance_label
    instance.category = category_name
    instance.properties = KorokConfig.to_properties(required + fields.get("properties", []), defined)
    instance.variants = KorokConfig.to_properties(fields.get("variants", []), defined)
    if fields.has("tint"):
      instance.tint = defined[fields.tint]

    instance.texture = fields.texture

    var slot_data: Dictionary = fields.get("slots", {})
    for slot_name in slot_data:
      instance.slots[slot_name] = Slot.from_dict(slot_name, slot_data[slot_name])

    instance.has_grip = fields.has("grip")
    if instance.has_grip:
      instance.grip = KorokConfig.to_vector(fields.grip)

    return instance

  func to_dict() -> Dictionary:
    var plain := {
      "label": label,
      "category": category,
      "properties": KorokConfig.to_names(properties),
      "variants": KorokConfig.to_names(variants),
      "texture": texture,
      "slots": KorokConfig.to_dicts(slots),
    }
    if has_grip:
      plain["grip"] = KorokConfig.from_vector(grip)

    if tint != null:
      plain["tint"] = tint.name

    return plain
