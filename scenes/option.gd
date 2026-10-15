class_name Option

var label: String
var image: Texture2D

## What the korok needs to apply the choice.
var instance: KorokConfig.Instance

## e.g. for colour variants: { "color": "blue" }
var values: Dictionary = {}

## What to multiply the image by. White leaves it as it is.
var tint: Color = Color.WHITE

static func from(lbl: String, texture_path: String, inst: KorokConfig.Instance, vals: Dictionary = {}) -> Option:
	var option := Option.new()
	option.label = lbl
	option.image = load(texture_path)
	option.instance = inst
	option.values = vals
	option.tint = inst.tint_for(vals)
	return option
