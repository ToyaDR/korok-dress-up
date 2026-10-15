extends Node2D
## Draws the korok from what the player picks. Nothing is drawn until a body
## is set. Everything else goes in a slot, either on the body or on something
## already placed. Example: the nose slot on a face.
##
## Each placed thing is a layer that is a child of whatever it's placed on.
## This is ensures that removing a face removes its nose with it.

## Emitted after anything is placed, so the UI can follow along. For example,
## the nose panel can show the new face's nose.
signal placed(instance: KorokConfig.Instance, holder: KorokConfig.Instance)


class Layer extends Sprite2D:
	var instance: KorokConfig.Instance
	var values: Dictionary

	## False for something put in automatically as a slot's default. Defaults
	## are not carried over to a new body, so they are made again from it.
	var chosen: bool


var _body: Layer


## Swaps the body. Whatever the player placed on the old body moves to the new
## one, into the slot with the same name if the new body has it.
func set_body(body: KorokConfig.Instance, values: Dictionary) -> void:
	var carried: Array[Layer] = []
	if _body != null:
		for child in _body.get_children():
			carried.append(child)

		remove_child(_body)
		_body.queue_free()

	_body = _make_layer(body, values, null, null)
	_body.name = "Body"
	add_child(_body)
	placed.emit(body, null)

	for layer in carried:
		_place_again(layer)


## Puts the instance in a slot that accepts it: the preferred slot if there is
## one by that name, otherwise the first empty one, otherwise the first one.
## Returns null before a body is set, or when nothing has a slot for it.
func place(instance: KorokConfig.Instance, values: Dictionary, preferred_slot := "", chosen := true) -> Layer:
	if _body == null:
		return null

	var spot := _find_slot(instance.category, preferred_slot)
	if spot.is_empty():
		return null

	var holder: Layer = spot.holder
	var slot: KorokConfig.Slot = spot.slot
	var old := holder.get_node_or_null(NodePath(slot.name))
	if old != null:
		holder.remove_child(old)
		old.queue_free()

	var layer := _make_layer(instance, values, holder, slot)
	layer.chosen = chosen
	holder.add_child(layer)
	placed.emit(instance, holder.instance)

	for own_slot in instance.slots.values():
		if own_slot.default != null:
			place(own_slot.default, _values_from_body(own_slot.default), own_slot.name, false)

	return layer


## Places a layer from the old body again, then whatever the player chose to
## put on it. Defaults are left out, since placing the layer makes them anew.
func _place_again(old: Layer) -> void:
	var slot_name := String(old.name)
	if place(old.instance, old.values, slot_name, true) == null:
		return

	for child in old.get_children():
		if child is Layer and child.chosen:
			_place_again(child)


## Every slot that accepts the category, on the body and on everything placed
## on it, as { holder, slot }. Picks one as described on `place`.
func _find_slot(category: String, preferred_slot: String) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var to_visit: Array[Layer] = [_body]
	while not to_visit.is_empty():
		var layer: Layer = to_visit.pop_front()
		for slot in layer.instance.slots.values():
			if slot.accepts.has(category):
				candidates.append({ "holder": layer, "slot": slot })

		for child in layer.get_children():
			if child is Layer:
				to_visit.append(child)

	for candidate in candidates:
		if candidate.slot.name == preferred_slot:
			return candidate

	for candidate in candidates:
		if not candidate.holder.has_node(NodePath(candidate.slot.name)):
			return candidate

	return {} if candidates.is_empty() else candidates[0]


## A default picks up whatever values the body has for its properties, so the
## nose starts out the body's color.
func _values_from_body(instance: KorokConfig.Instance) -> Dictionary:
	var values := {}
	for property in instance.choices():
		if _body.values.has(property.name):
			values[property.name] = _body.values[property.name]

	return values


func _make_layer(instance: KorokConfig.Instance, values: Dictionary, holder: Layer, slot: KorokConfig.Slot) -> Layer:
	var layer := Layer.new()
	layer.instance = instance
	layer.values = values

	var picture_values := values.duplicate()
	picture_values["body"] = instance.id if _body == null else _body.instance.id
	if holder != null:
		picture_values["holder"] = holder.instance.id

	layer.texture = load(instance.texture_path(picture_values))
	layer.self_modulate = instance.tint_for(values)
	if slot == null:
		return layer

	layer.name = slot.name
	layer.z_index = slot.z

	# Most art is drawn already in place on the full canvas, so it lines up
	# with the body at the same origin. A slot with a position, like a hand,
	# places a cropped item there instead, turning it around its grip.
	# TODO: faces are now one set for every body, so they no longer sit right
	# on the flying body. Give each body's face slot a position and rotation,
	# and place faces the way hands place items.
	if slot.has_position and instance.has_grip and layer.texture != null:
		layer.centered = false
		layer.offset = -instance.grip * layer.texture.get_size()
		layer.position = slot.position - _body.texture.get_size() / 2
		layer.rotation_degrees = slot.rotation

	return layer


# design thoughts
#
# items slot into body parts. pose changes mean stuff may need to move/rotate,
# which is what slot position + rotation are for
#
# buttons first, drag and drop later: drop zones for collision checks
#
# data flow:
#   korok.yaml -> YAML -> ConfigSchema (right fields/types?) ->
#   ConfigReferences (does everything exist?) -> KorokConfig
#
# signal / data flow:
#   panel fires on "picked something" (option_selected)
#   -> korok updates itself, says "placed this" (placed)
#   -> main.gd picks it up, fixes up the panels (enable stuff, swap nose pics)
#   panels don't know about the korok, korok doesn't know about panels.
#   main.gd is the parent of both, so it wires them up
#
# original plan + where it landed:
#   - button class firing a signal -> OptionPanel. body / body part / item
#     buttons collapsed into one, since body parts and items both fill slots
#   - korok has a body + free floating items. body yes, free items not yet
#   - body: slots w/ fixed spots + angles, built-in bits like hands, texture.
#     all in yaml now
#   - body part: lives in a slot, can have variants + its own slots (nose!)
#   - item: grip point, goes at its slot's position/rotation. needs cropped
#     upright art, accessories aren't there yet
#   - yaml -> load -> validate -> button per entry: done
#   - no items before a body: korok ignores them, panels not disabled yet
#   - main scene has the korok + floating items
#   - clicking a body:
#     1. no body yet: set it, enable the rest (enable part still todo)
#     2. new body: swap it, carry stuff over (done)
#     3. body unset: clear everything (todo)
#   - clicking a body part / item: korok shoves it in a slot that takes it,
#     as long as there's a body
