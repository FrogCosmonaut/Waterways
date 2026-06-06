class_name WaterwaysRiverShader
extends Resource

@export var name: String
@export var shader: Shader

## Map of TextureName and TextureImage used by the shader
## e.g. { "normal_bump_texture": image, "emission_texture": image }
@export var texture_map: Dictionary[String, Texture2D]
