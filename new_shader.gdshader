shader_type canvas_item;

uniform float tolerance : hint_range(0.0, 1.0) = 0.1; // Controle de tolerância

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    // Calcular a diferença do fundo para o preto puro
    float diff = length(tex.rgb - vec3(0.0, 0.0, 0.0));

    // Se a diferença estiver dentro da tolerância, descartar
    if (diff < tolerance) {
        discard;
    }

    COLOR = tex;
}