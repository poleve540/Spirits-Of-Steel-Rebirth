shader_type canvas_item;

uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;
uniform sampler2D original_texture : filter_nearest; // Sea
uniform vec2 tex_size;

uniform vec4 country_border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float internal_border_darkness : hint_range(0.0, 1.0) = 0.2;

// --- NEW SHORELINE PARAMETERS ---
uniform vec4 shoreline_color : source_color = vec4(1.0, 1.0, 1.0, 0.5); // Light glow
uniform float shoreline_size : hint_range(0.0, 5.0) = 2.0;

// 8 constant directions (must be const in Godot)
const vec2 DIRS[8] = vec2[8](
    vec2(0.0, -1.0),
    vec2(0.0,  1.0),
    vec2(-1.0, 0.0),
    vec2(1.0,  0.0),
    vec2(-1.0, -1.0),
    vec2(1.0,  -1.0),
    vec2(-1.0, 1.0),
    vec2(1.0,  1.0)
);

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

// Scans neighbors at a given distance (in pixels).
bool detect_border_at_distance(vec2 origin_uv, float dist_px, out vec4 out_color, out bool is_black) {
    vec2 pixel_size = 1.0 / tex_size;
    out_color = vec4(0.0);
    is_black = false;

    bool found_color = false;
    vec4 reference = vec4(0.0);

    for (int i = 0; i < 8; i++) {
        vec2 sample_uv = clamp(origin_uv + DIRS[i] * pixel_size * dist_px, vec2(0.0), vec2(1.0));
        int nid = get_id(sample_uv);

        if (nid == 0) {
            is_black = true;
            return true;
        }

        if (nid > 1) {
            vec4 c = get_country_color(nid);
            if (!found_color) {
                reference = c;
                found_color = true;
            } else {
                if (distance(reference.rgb, c.rgb) > 0.005) {
                    is_black = true;
                    return true;
                }
            }
        }
    }

    if (found_color) {
        out_color = mix(reference, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        return true;
    }

    return false;
}

void fragment() {
    vec4 out_color = vec4(0.0);
    int id = get_id(UV);

    // SEA: draw original sea texture + shorelines
    if (id == 0) {
        out_color = texture(original_texture, UV);
        
        // SHORELINE LOGIC: Check if land is nearby
        vec2 pixel_size = 1.0 / tex_size;
        float land_proximity = 0.0;
        for (int i = 0; i < 8; i++) {
            // Check neighbors at shoreline_size distance
            int nid = get_id(UV + DIRS[i] * pixel_size * shoreline_size);
            if (nid > 0) {
                land_proximity = 1.0;
                break;
            }
        }
        
        if (land_proximity > 0.0) {
            out_color = mix(out_color, shoreline_color, shoreline_color.a);
        }
    }
    // LAND: draw lookup color
    else if (id > 1) {
        out_color = get_country_color(id);
    }
    // GRID / AMBIGUOUS PIXEL: decide based on neighbors
    else {
        vec4 c_detect = vec4(0.0);
        bool must_be_black = false;
        bool decided = false;

        if (detect_border_at_distance(UV, 1.0, c_detect, must_be_black)) decided = true;
        
        if (!decided) {
            if (detect_border_at_distance(UV, 2.0, c_detect, must_be_black)) decided = true;
        }

        if (!decided) {
            if (detect_border_at_distance(UV, 3.0, c_detect, must_be_black)) decided = true;
        }

        if (decided) {
            if (must_be_black) {
                out_color = country_border_color;
            } else {
                out_color = c_detect;
            }
        } else {
            out_color = country_border_color;
        }
    }

    COLOR = out_color;
}