// An example for the pixel package.
//
// It makes a gradient image, writes it as a PNG, reads it back, and
// prints the size.
//
// Run with: goose run examples/gradient.goose

import std;
import pixel from "..";

fn main() {
    // A 64x64 gradient: red grows to the right, green grows down.
    var img = pixel::new_image(64, 64, 0, 0, 0, 255);
    for y: i32 in 0..64 {
        for x: i32 in 0..64 {
            pixel::set_pixel(img, x, y, (x * 4) as u8, (y * 4) as u8, 128, 255);
        }
    }

    assert(pixel::write_png("gradient.png", img));
    let w, h, ok = pixel::info("gradient.png");
    print("wrote gradient.png: ", w, "x", h, " ok=", ok);

    var back = pixel::load("gradient.png");
    let r, g, b, a = pixel::pixel(back, 32, 32);
    print("middle pixel: ", r, " ", g, " ", b, " ", a);
    return 0;
}
