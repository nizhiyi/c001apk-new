#version 460 core
#include <flutter/runtime_effect.glsl>
// Public identity shader; the basic backend uses Flutter's ordinary blur.
uniform vec2 uSize;
uniform sampler2D uBackdrop;
out vec4 fragColor;
void main() { fragColor = texture(uBackdrop, FlutterFragCoord().xy / uSize); }