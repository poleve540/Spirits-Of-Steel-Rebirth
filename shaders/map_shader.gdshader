shader_type canvas_item;

// --- TEXTURES ---
uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;
uniform sampler2D original_texture : filter_nearest; // Sea
uniform vec2 tex_size;

// --- BORDER SETTINGS ---
uniform vec4 country_border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float internal_border_darkness : hint_range(0.0, 1.0) = 0.2;
uniform float border_scan_distance : hint_range(1.0, 5.0) = 2.0;

// --- SHORELINE SETTINGS ---
//uniform vec4 shoreline_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
//uniform float shoreline_size : hint_range(0.0, 10.0) = 2.0;

// --- COUNTRY BORDER GLOW SETTINGS ---
uniform float country_glow_radius : hint_range(1.0, 15.0) = 8.0;      // How far inward the glow reaches
uniform float country_glow_intensity : hint_range(0.0, 1.0) = 0.35;  // Overall strength
uniform float country_glow_falloff : hint_range(0.1, 5.0) = 1.8;     // Higher = sharper falloff

// Standard 8-way offsets
const vec2 DIRS[8] = vec2[8](
    vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(1.0, 0.0),
    vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0)
);

// --- HELPER FUNCTIONS ---

int get_id(vec2 uv) {
    vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
    vec4 c = texture(region_id_map, cuv);
    int r = int(round(c.r * 255.0));
    int g = int(round(c.g * 255.0));
    return r + g * 256;
}

vec4 get_country_color(int id) {
    if (id <= 1) return vec4(0.0);
    float u = (float(id) + 0.5) / float(textureSize(state_colors, 0).x);
    return texture(state_colors, vec2(u, 0.0));
}

vec4 get_border_context(vec2 uv, vec2 pixel_size, out bool is_hard_border) {
    is_hard_border = false;
    vec4 detected_color = vec4(0.0);
    bool found_any_color = false;

    for (int i = 0; i < 8; i++) {
        for (float d = 1.0; d <= border_scan_distance; d += 1.0) {
            vec2 sample_pos = uv + (DIRS[i] * pixel_size * d);
            int nid = get_id(sample_pos);

            if (nid == 1) continue;

            if (nid == 0) {
                is_hard_border = true;
                return country_border_color;
            }

            vec4 c = get_country_color(nid);

            if (!found_any_color) {
                detected_color = c;
                found_any_color = true;
            } else {
                if (distance(c.rgb, detected_color.rgb) > 0.01) {
                    is_hard_border = true;
                    return country_border_color;
                }
            }

            break;
        }
    }

    if (found_any_color) {
        return detected_color;
    }

    return country_border_color;
}

void fragment() {
    int id = get_id(UV);
    vec2 pixel_size = 1.0 / tex_size;
    vec4 final_color = vec4(0.0);

    // --- SEA LOGIC ---
    if (id == 0) {
        final_color = texture(original_texture, UV);
    }

    // --- LAND LOGIC ---
    else if (id > 1) {
        vec4 base_color = get_country_color(id);
        final_color = base_color;

        // Smooth outer border glow (only near hard borders)
        float min_dist = country_glow_radius + 1.0;  // large initial value

        for (int i = 0; i < 8; i++) {
            for (float d = 1.0; d <= country_glow_radius + 2.0; d += 1.0) {  // slightly oversample
                vec2 sample_uv = UV + DIRS[i] * pixel_size * d;
                int nid = get_id(sample_uv);

                if (nid == 1) {
                    // Found a border pixel → check if it's a hard border
                    bool is_hard;
                    get_border_context(sample_uv, pixel_size, is_hard);
                    if (is_hard) {
                        min_dist = min(min_dist, d);
                        break; // no need to look further in this direction
                    }
                }
            }
        }

        if (min_dist <= country_glow_radius) {
            // Distance-based smooth falloff
            float strength = 1.0 - pow(min_dist / country_glow_radius, country_glow_falloff);
            strength = clamp(strength, 0.0, 1.0);

            // Brighten in the country's own color
            vec4 glow_color = base_color * 1.6;
            glow_color.a = 1.0;

            final_color = mix(base_color, glow_color, strength * country_glow_intensity);
        }
    }

    // --- BORDER/GRID LOGIC (ID == 1) ---
    else {
        bool is_hard_border = false;
        vec4 context_color = get_border_context(UV, pixel_size, is_hard_border);

        if (is_hard_border) {
            final_color = country_border_color;
        } else {
            final_color = mix(context_color, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        }
    }

    COLOR = final_color;
}