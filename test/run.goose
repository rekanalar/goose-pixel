// Tests for the pixel package. Run with: goose run test/run.goose
//
// The test makes images, writes them, and reads them back. The pixels of
// the read image must hold the colors that were written.

import std;
import os;
import pixel from "..";
import gif_tests;
import geometry_cases;
import gif_cases;
import jpeg_cases;
import webp_cases;
import avif_cases;
import avif_enc_cases;
import png16_cases;
import tiff_cases;

fn test_round_trip() {
    // A 4x3 image: every pixel holds the color of its place.
    var img = pixel::new_image(4, 3, 0, 0, 0, 255);
    for y: i32 in 0..3 {
        for x: i32 in 0..4 {
            pixel::set_pixel(img, x, y, (x * 60) as u8, (y * 80) as u8, 128, 255);
        }
    }

    // The size and one pixel.
    assert(img.width == 4);
    assert(img.height == 3);
    let r, g, b, a = pixel::pixel(img, 2, 1);
    assert(r == 120);
    assert(g == 80);
    assert(b == 128);
    assert(a == 255);

    // A place outside the image gives the empty color.
    let r2, g2, b2, a2 = pixel::pixel(img, 9, 9);
    assert(r2 == 0 && g2 == 0 && b2 == 0 && a2 == 0);

    // Write the three formats and read each back.
    assert(pixel::write_png("test-image.png", img));
    assert(pixel::write_bmp("test-image.bmp", img));
    assert(pixel::write_jpeg("test-image.jpg", img));

    let from_png = pixel::load("test-image.png");
    assert(from_png.width == 4 && from_png.height == 3);
    let pr, pg, pb, pa = pixel::pixel(from_png, 2, 1);
    assert(pr == 120 && pg == 80 && pb == 128 && pa == 255);

    let from_bmp = pixel::load("test-image.bmp");
    assert(from_bmp.width == 4 && from_bmp.height == 3);
    let br, bg, bb, ba = pixel::pixel(from_bmp, 3, 2);
    assert(br == 180 && bg == 160 && bb == 128 && ba == 255);

    // JPEG takes losses, so the test checks the size and a close color.
    let from_jpg = pixel::load("test-image.jpg");
    assert(from_jpg.width == 4 && from_jpg.height == 3);
    let jr, jg, jb, ja = pixel::pixel(from_jpg, 2, 1);
    assert(ja == 255);
    let jd = jr as i32 - 120;
    if jd < 0 { assert(-jd <= 12); } else { assert(jd <= 12); }
    let jd2 = jg as i32 - 80;
    if jd2 < 0 { assert(-jd2 <= 12); } else { assert(jd2 <= 12); }
}

fn test_info() {
    let w, h, ok = pixel::info("test-image.png");
    assert(ok);
    assert(w == 4 && h == 3);

    let w2, h2, ok2 = pixel::info("no-such-file.png");
    assert(!ok2);
}

fn test_load_failure() {
    let empty = pixel::load("no-such-file.png");
    assert(empty.width == 0);
    assert(empty.height == 0);
    assert(empty.pixels.len == 0);
}

// A 32x32 image with a smooth gradient and a hard edge, so that the
// quality and the level change the size of the output.
fn make_busy() -> pixel::Image {
    var img = pixel::new_image(32, 32, 0, 0, 0, 255);
    for y: i32 in 0..32 {
        for x: i32 in 0..32 {
            let v = ((x * 7 + y * 13) % 256) as u8;
            pixel::set_pixel(img, x, y, v, (x * 8) as u8, (y * 8) as u8, 255);
        }
    }
    return img;
}

fn near(a: u8, b: u8, tol: i32) -> bool {
    let d = a - b as i32;
    return d <= tol && -d <= tol;
}

fn test_memory_round_trip() {
    let img = make_busy();
    // PNG, BMP and TGA keep every pixel.
    for f: i32 in 0..4 {
        if f == pixel::FORMAT_JPEG { continue; }
        let bytes = pixel::encode(img, f, 0);
        assert(bytes.len > 0);
        let back = pixel::decode(bytes);
        assert(back.width == 32 && back.height == 32);
        assert(back.pixels.len == img.pixels.len);
        for i in 0..img.pixels.len { assert(back.pixels[i] == img.pixels[i]); }
    }
    // JPEG keeps the size and a close color.
    let jb = pixel::encode(img, pixel::FORMAT_JPEG, 95);
    let jr = pixel::decode(jb);
    assert(jr.width == 32 && jr.height == 32);
    let r, g, b, a = pixel::pixel(jr, 16, 16);
    let r0, g0, b0, a0 = pixel::pixel(img, 16, 16);
    assert(near(r, r0, 25) && near(g, g0, 25) && near(b, b0, 25) && a == 255);
}

fn test_options() {
    let img = make_busy();
    let lo = pixel::encode(img, pixel::FORMAT_JPEG, 5);
    let hi = pixel::encode(img, pixel::FORMAT_JPEG, 100);
    assert(lo.len > 0 && hi.len > lo.len);
    // The TGA run-length flag: 2 is off, so the output is larger on flat data.
    let flat = pixel::new_image(32, 32, 9, 9, 9, 255);
    let rle = pixel::encode(flat, pixel::FORMAT_TGA, 1);
    let raw = pixel::encode(flat, pixel::FORMAT_TGA, 2);
    assert(rle.len < raw.len);
    // Every PNG level decodes to the same pixels.
    for lvl: i32 in 1..10 {
        let p = pixel::encode(flat, pixel::FORMAT_PNG, lvl);
        let back = pixel::decode(p);
        assert(back.width == 32 && back.pixels[0] == 9);
    }
    // A bad image does not encode.
    let none = pixel::Image { width: 4, height: 4, pixels: [], icc: [], exif: [] };
    assert(pixel::encode(none, pixel::FORMAT_PNG, 0).len == 0);
}

fn test_files() {
    let img = make_busy();
    assert(pixel::write_tga("test-image.tga", img));
    assert(pixel::write_hdr("test-image.hdr", img));
    let t = pixel::load("test-image.tga");
    assert(t.width == 32 && t.pixels[0] == img.pixels[0]);
    // HDR keeps 8 bits of mantissa shared by the three parts, so it is close.
    let hd = pixel::load("test-image.hdr");
    assert(hd.width == 32 && hd.height == 32);
    let hr, hg, hb, ha = pixel::pixel(hd, 20, 3);
    let r0, g0, b0, a0 = pixel::pixel(img, 20, 3);
    assert(near(hr, r0, 40) && near(hg, g0, 40) && near(hb, b0, 40));
}

fn test_metadata() {
    let img = make_busy();
    let png = pixel::encode(img, pixel::FORMAT_PNG, 0);
    let m = pixel::metadata_bytes(png);
    assert(m.ok && m.width == 32 && m.height == 32 && m.kind == pixel::KIND_PNG);
    assert(m.channels == 3 || m.channels == 4);
    let kinds: i32[5] = [pixel::KIND_PNG, pixel::KIND_JPEG, pixel::KIND_BMP, pixel::KIND_TGA, pixel::KIND_HDR];
    for f: i32 in 0..5 {
        let mm = pixel::metadata_bytes(pixel::encode(img, f, 0));
        assert(mm.ok && mm.width == 32 && mm.height == 32 && mm.kind == kinds[f]);
    }
    let fm = pixel::metadata("test-image.png");
    assert(fm.ok && fm.width == 4 && fm.height == 3);
    assert(!pixel::metadata("no-such-file.png").ok);
    assert(!pixel::metadata_bytes("not an image").ok);
    assert(pixel::decode("not an image").width == 0);
}

fn test_resize() {
    let img = make_busy();
    for f: i32 in 0..8 {
        let small = pixel::resize(img, 8, 16, f);
        assert(small.width == 8 && small.height == 16);
        assert(small.pixels.len == 8 * 16 * 4);
        let big = pixel::resize(img, 50, 40, f);
        assert(big.width == 50 && big.height == 40 && big.pixels.len == 50 * 40 * 4);
    }
    // A flat image stays flat, in every filter.
    let flat = pixel::new_image(10, 10, 100, 150, 200, 255);
    for f: i32 in 0..8 {
        let s = pixel::resize(flat, 3, 7, f);
        for y: i32 in 0..7 {
            for x: i32 in 0..3 {
                let r, g, b, a = pixel::pixel(s, x, y);
                assert(near(r, 100, 1) && near(g, 150, 1) && near(b, 200, 1) && a == 255);
            }
        }
    }
    // Nearest takes source pixels, so a 2x1 image doubled gives two pairs.
    var two = pixel::new_image(2, 1, 10, 0, 0, 255);
    pixel::set_pixel(two, 1, 0, 200, 0, 0, 255);
    let dbl = pixel::resize(two, 4, 1, pixel::FILTER_NEAREST);
    let p0, _g0, _b0, _a0 = pixel::pixel(dbl, 0, 0);
    let p1, _g1, _b1, _a1 = pixel::pixel(dbl, 1, 0);
    let p2, _g2, _b2, _a2 = pixel::pixel(dbl, 2, 0);
    let p3, _g3, _b3, _a3 = pixel::pixel(dbl, 3, 0);
    assert(p0 == 10 && p1 == 10 && p2 == 200 && p3 == 200);
    // A box filter on a 2x1 halved gives the mean.
    let avg = pixel::resize(two, 1, 1, pixel::FILTER_BOX);
    let ar, _ag, _ab, _aa = pixel::pixel(avg, 0, 0);
    assert(near(ar, 105, 1));
    // Bad input gives the empty image.
    assert(pixel::resize(img, 0, 5, 0).width == 0);
    assert(pixel::resize(img, 5, 5, 99).width == 0);
    // fit keeps the aspect ratio.
    let wide = pixel::new_image(40, 20, 1, 2, 3, 255);
    let f1 = pixel::fit(wide, 10, 10, pixel::FILTER_DEFAULT);
    assert(f1.width == 10 && f1.height == 5);
    let f2 = pixel::fit(wide, 100, 100, pixel::FILTER_DEFAULT);
    assert(f2.width == 100 && f2.height == 50);
    // A resized image survives a write and a read.
    let small = pixel::resize(img, 8, 8, pixel::FILTER_BICUBIC);
    let rt = pixel::decode(pixel::encode(small, pixel::FORMAT_PNG, 0));
    assert(rt.width == 8 && rt.height == 8);
}

// is_empty tells whether the image has no pixels.
fn is_empty(img: pixel::Image) -> bool {
    return img.width == 0 && img.height == 0 && img.pixels.len == 0;
}

// test_geometry_contract checks the rules of the geometry calls that Pillow
// does not state the same way: empty results, limits and hostile input.
fn test_geometry_contract() {
    var img = pixel::new_image(4, 3, 10, 20, 30, 255);
    pixel::set_pixel(img, 1, 1, 200, 100, 50, 128);

    // A box without area gives an empty image. Pillow raises an error for an
    // inverted box and gives a side of zero for an empty one.
    assert(is_empty(pixel::crop(img, 2, 0, 1, 1)));
    assert(is_empty(pixel::crop(img, 1, 0, 1, 2)));
    assert(is_empty(pixel::crop(img, 0, 3, 4, 3)));
    // A box that is too large gives an empty image and does not abort.
    assert(is_empty(pixel::crop(img, 0, 0, 2147483647, 2147483647)));
    assert(is_empty(pixel::crop(img, -2147483647, -2147483647, 2147483647, 2147483647)));
    assert(is_empty(pixel::crop(img, 0, 0, 40000, 40000)));
    // A box far outside the image gives transparent black.
    let far = pixel::crop(img, 1000, 1000, 1002, 1001);
    assert(far.width == 2 && far.height == 1);
    let r, g, b, a = pixel::pixel(far, 1, 0);
    assert(r == 0 && g == 0 && b == 0 && a == 0);

    // An unknown operation gives an empty image.
    assert(is_empty(pixel::transpose(img, -1)));
    assert(is_empty(pixel::transpose(img, 7)));

    // An empty image and a short buffer count as empty.
    let none = pixel::Image { width: 0, height: 0, pixels: [], icc: [], exif: [] };
    let short = pixel::Image { width: 4, height: 3, pixels: [1, 2, 3], icc: [], exif: [] };
    assert(is_empty(pixel::crop(none, 0, 0, 1, 1)));
    assert(is_empty(pixel::crop(short, 0, 0, 1, 1)));
    assert(is_empty(pixel::transpose(none, 0)));
    assert(is_empty(pixel::transpose(short, 2)));
    assert(is_empty(pixel::rotate(short, 30.0, true)));
    assert(is_empty(pixel::rotate(none, 30.0, false)));

    // A paste with an empty or short source leaves the destination as it is.
    var dst = pixel::new_image(4, 3, 1, 2, 3, 4);
    let before = dst.pixels;
    pixel::paste(dst, none, 0, 0);
    pixel::paste(dst, short, 0, 0);
    pixel::alpha_composite(dst, none, 0, 0);
    pixel::alpha_composite(dst, short, 0, 0);
    assert(dst.pixels == before);
    // A place far outside changes nothing and does not abort.
    var small = pixel::new_image(2, 2, 9, 9, 9, 255);
    pixel::paste(dst, small, 2147483647, 2147483647);
    pixel::paste(dst, small, -2147483647, -2147483647);
    pixel::alpha_composite(dst, small, 2147483647, -2147483647);
    pixel::alpha_composite(dst, small, -100, -100);
    assert(dst.pixels == before);

    // An image with a huge size and a short buffer is empty. The count of
    // the pixels overflows when it is computed with the four bytes of each
    // pixel, so the test must not abort.
    let huge = pixel::Image { width: 2147483647, height: 2147483647, pixels: [1, 2, 3, 4], icc: [], exif: [] };
    assert(is_empty(pixel::crop(huge, 0, 0, 10, 10)));
    assert(is_empty(pixel::transpose(huge, 2)));
    assert(is_empty(pixel::rotate(huge, 30.0, true)));
    var hdst = pixel::new_image(2, 2, 1, 2, 3, 4);
    let hbefore = hdst.pixels;
    pixel::paste(hdst, huge, 0, 0);
    pixel::alpha_composite(hdst, huge, 0, 0);
    assert(hdst.pixels == hbefore);

    // An angle that is not a number gives an empty image.
    let nan_angle = 0.0 / 0.0;
    assert(is_empty(pixel::rotate(img, nan_angle, false)));
    assert(is_empty(pixel::rotate(img, nan_angle, true)));

    // An angle that is far too large gives an empty image.
    assert(is_empty(pixel::rotate(img, 1.0e30, false)));
    assert(is_empty(pixel::rotate(img, -1.0e30, true)));
    // An angle of a full turn gives the same pixels.
    let full = pixel::rotate(img, 360.0, false);
    assert(full.width == 4 && full.height == 3 && full.pixels == img.pixels);
    let twice = pixel::rotate(img, -360.0, true);
    assert(twice.pixels == img.pixels);
}

// grid makes an image with a different value in every pixel.
fn grid(w: i32, h: i32) -> pixel::Image {
    var img = pixel::new_image(w, h, 0, 0, 0, 255);
    for y: i32 in 0..h {
        for x: i32 in 0..w {
            pixel::set_pixel(img, x, y, (y * w + x) as u8, (x * 7) as u8, (y * 11) as u8, 255);
        }
    }
    return img;
}

// test_paste_values checks one copy and one blend by hand.
fn test_paste_values() {
    var dst = pixel::new_image(3, 2, 10, 20, 30, 200);
    var src = pixel::new_image(1, 1, 200, 100, 50, 128);
    pixel::paste(dst, src, 1, 1);
    let r, g, b, a = pixel::pixel(dst, 1, 1);
    assert(r == 200 && g == 100 && b == 50 && a == 128);
    let r0, g0, b0, a0 = pixel::pixel(dst, 0, 0);
    assert(r0 == 10 && g0 == 20 && b0 == 30 && a0 == 200);
    // The blend of the probe of the research file.
    var base = pixel::new_image(1, 1, 10, 20, 30, 200);
    pixel::alpha_composite(base, src, 0, 0);
    let r1, g1, b1, a1 = pixel::pixel(base, 0, 0);
    assert(r1 == 117 && g1 == 65 && b1 == 41 && a1 == 228);
    // A paste of an image onto itself reads the source as it was before.
    var overlap = grid(3, 3);
    pixel::paste(overlap, overlap, 1, 1);
    let p0, _, _, _ = pixel::pixel(overlap, 1, 1);
    let p1, _, _, _ = pixel::pixel(overlap, 2, 1);
    let p2, _, _, _ = pixel::pixel(overlap, 1, 2);
    let p3, _, _, _ = pixel::pixel(overlap, 2, 2);
    assert(p0 == 0 && p1 == 1 && p2 == 3 && p3 == 4);
    // A source with no alpha leaves the destination as it is.
    var clear = pixel::new_image(1, 1, 255, 255, 255, 0);
    pixel::alpha_composite(base, clear, 0, 0);
    let r2, g2, b2, a2 = pixel::pixel(base, 0, 0);
    assert(r2 == 117 && g2 == 65 && b2 == 41 && a2 == 228);
}

// inverse_of gives the operation that undoes the operation. The turns of
// 90 and 270 degrees undo each other. The other operations undo themselves.
fn inverse_of(op: i32) -> i32 {
    if op == pixel::TRANSPOSE_ROTATE_90 { return pixel::TRANSPOSE_ROTATE_270; }
    if op == pixel::TRANSPOSE_ROTATE_270 { return pixel::TRANSPOSE_ROTATE_90; }
    return op;
}

// check_inverse applies each operation and then its inverse to the image.
fn check_inverse(img: pixel::Image&) {
    for op: i32 in 0..7 {
        var once = pixel::transpose(img, op);
        let back = pixel::transpose(once, inverse_of(op));
        assert(back.width == img.width && back.height == img.height);
        assert(back.pixels == img.pixels);
    }
}

// test_transpose_inverse checks that an operation and its inverse give the
// source image back.
fn test_transpose_inverse() {
    var small = grid(3, 2);
    check_inverse(small);
    var square = grid(4, 4);
    check_inverse(square);
}

// test_geometry runs the cases that Pillow made. The file
// test/geometry_cases.goose holds them.
fn test_geometry() {
    test_geometry_contract();
    test_transpose_inverse();
    test_paste_values();
    geometry_cases::check_crop();
    geometry_cases::check_transpose();
    geometry_cases::check_paste();
    geometry_cases::check_blend();
    geometry_cases::check_rotate();
}


fn test_hostile_size() {
    // The limit of the buffer: 2147483647 bytes.
    assert(pixel::size_ok(23170, 23170));
    assert(!pixel::size_ok(23171, 23170));
    assert(pixel::size_ok(536870911, 1));
    assert(!pixel::size_ok(536870912, 1));
    assert(!pixel::size_ok(0, 5));
    assert(!pixel::size_ok(5, 0));
    assert(!pixel::size_ok(-5, 3));
    assert(!pixel::size_ok(2147483647, 2147483647));

    // pixel and set_pixel on an image whose size does not match the buffer.
    var huge = pixel::Image { width: 2147483647, height: 2147483647, pixels: [1, 2, 3, 4], icc: [], exif: [] };
    let r, g, b, a = pixel::pixel(huge, 1, 1);
    assert(r == 0 && g == 0 && b == 0 && a == 0);
    let r0, g0, b0, a0 = pixel::pixel(huge, 0, 0);
    assert(r0 == 1 && g0 == 2 && b0 == 3 && a0 == 4);
    let r1, g1, b1, a1 = pixel::pixel(huge, 2147483646, 2147483646);
    assert(r1 == 0 && g1 == 0 && b1 == 0 && a1 == 0);
    pixel::set_pixel(huge, 1, 1, 9, 9, 9, 9);
    pixel::set_pixel(huge, 2147483646, 2147483646, 9, 9, 9, 9);
    pixel::set_pixel(huge, -1, 0, 9, 9, 9, 9);
    let first: u8[4] = [1, 2, 3, 4];
    assert(huge.pixels == first);
    pixel::set_pixel(huge, 0, 0, 5, 6, 7, 8);
    let second: u8[4] = [5, 6, 7, 8];
    assert(huge.pixels == second);

    // new_image gives the empty image for a bad size.
    let bad_w: i32[4] = [2147483647, -5, 0, 3];
    let bad_h: i32[4] = [2147483647, 3, 3, 0];
    for i in 0..4 {
        let e = pixel::new_image(bad_w[i], bad_h[i], 1, 2, 3, 4);
        assert(e.width == 0 && e.height == 0 && e.pixels.len == 0);
    }
    let big = pixel::new_image(536870912, 1, 1, 2, 3, 4);
    assert(big.width == 0 && big.height == 0 && big.pixels.len == 0);
    // A size that worked before gives the same image.
    let ok = pixel::new_image(3, 2, 1, 2, 3, 4);
    assert(ok.width == 3 && ok.height == 2 && ok.pixels.len == 24);
    assert(ok.pixels[0] == 1 && ok.pixels[1] == 2 && ok.pixels[2] == 3 && ok.pixels[3] == 4);
    assert(ok.pixels[23] == 4);

    // A buffer longer than the size needs: the size rules, the extra bytes stay.
    var longer = pixel::new_image(2, 4, 7, 7, 7, 7);
    longer.height = 2;
    pixel::set_pixel(longer, 1, 1, 9, 9, 9, 9);
    let lr, lg, lb, la = pixel::pixel(longer, 1, 1);
    assert(lr == 9 && lg == 9 && lb == 9 && la == 9);
    let nr, ng, nb, na = pixel::pixel(longer, 2, 0);
    assert(nr == 0 && ng == 0 && nb == 0 && na == 0);
    assert(longer.pixels.len == 32 && longer.pixels[16] == 7 && longer.pixels[31] == 7);

    // resize, fit, encode and write_with refuse the mismatched image.
    let rs = pixel::resize(huge, 4, 4, pixel::FILTER_BOX);
    assert(rs.width == 0 && rs.pixels.len == 0);
    let ft = pixel::fit(huge, 4, 4, pixel::FILTER_BOX);
    assert(ft.width == 0 && ft.pixels.len == 0);
    let small = pixel::new_image(2, 2, 1, 2, 3, 4);
    let rt = pixel::resize(small, 536870912, 1, pixel::FILTER_BOX);
    assert(rt.width == 0 && rt.pixels.len == 0);
    assert(pixel::encode(huge, pixel::FORMAT_PNG, 0).len == 0);
    assert(!pixel::write_with("tmp-hostile.png", huge, pixel::FORMAT_PNG, 0));
}


// The metadata cases: the ICC profile and the EXIF block ride with
// the file, on JPEG and on PNG.
fn meta_cases() {
    var jpg: u8[>..] = [];
    assert(read_file("test/meta-audit.jpg", jpg));
    assert(jpg.len > 0);
    let img = pixel::decode(jpg);
    assert(img.width == 4);
    assert(img.icc.len == 2048);
    assert(img.exif.len == 62);
    assert(img.exif[0] == 0x4d);

    // The tag reader: the description and the orientation.
    let text = pixel::exif_text(img.exif[..], 0x010e);
    assert(text == "goose image description");
    let orient = pixel::exif_short(img.exif[..], 0x0112);
    assert(orient == 1);

    // A round trip through encode keeps both fields, on JPEG and on
    // PNG.
    let jb = pixel::encode(img, pixel::FORMAT_JPEG, 90);
    let jback = pixel::decode(jb);
    assert(jback.icc[..] == img.icc[..]);
    assert(jback.exif[..] == img.exif[..]);
    let pb = pixel::encode(img, pixel::FORMAT_PNG, 8);
    let pback = pixel::decode(pb);
    assert(pback.icc[..] == img.icc[..]);
    assert(pback.exif[..] == img.exif[..]);

    // A write without metadata makes no marker.
    let plain = pixel::new_image(4, 4, 1, 2, 3, 255);
    let jb2 = pixel::encode(plain, pixel::FORMAT_JPEG, 90);
    let plainback = pixel::decode(jb2);
    assert(plainback.icc.len == 0);
    assert(plainback.exif.len == 0);

    // A truncated APP part never aborts and gives an empty field.
    var cut: u8[>..] = [];
    cut.append(jpg[..40]);
    let cback = pixel::decode(cut[..]);
    assert(cback.icc.len == 0);

    print("metadata cases ok\n");
}

// test_webp checks the codec: the files of Pillow, the writer of the package
// and the hostile bytes.
fn test_webp() {
    webp_cases::check_decode();
    webp_cases::check_hostile();

    // A lossless write keeps every pixel, also under a clear alpha.
    var img = make_busy();
    pixel::set_pixel(img, 3, 3, 12, 34, 56, 0);
    let ll = pixel::encode_webp(img, 100, true);
    assert(ll.len > 12 && ll[0] == 'R' && ll[8] == 'W');
    let back = pixel::decode(ll);
    assert(back.width == 32 && back.height == 32 && back.pixels == img.pixels);
    // The same bytes come out of a second write, and a second round is stable.
    assert(pixel::encode_webp(img, 100, true) == ll);
    assert(pixel::encode_webp(back, 100, true) == ll);

    // A lossy write keeps the size and a close color. The quality changes the size.
    let flat = pixel::new_image(64, 64, 90, 160, 30, 255);
    let lo = pixel::encode_webp(img, 10, false);
    let hi = pixel::encode_webp(img, 100, false);
    assert(lo.len > 0 && hi.len > lo.len);
    let lb = pixel::decode(hi);
    assert(lb.width == 32 && lb.height == 32);
    let r, g, b, a = pixel::pixel(lb, 16, 16);
    let r0, g0, b0, a0 = pixel::pixel(img, 16, 16);
    assert(near(r, r0, 30) && near(g, g0, 30) && near(b, b0, 30) && a == 255);
    let fb = pixel::decode(pixel::encode_webp(flat, 90, false));
    let fr, fg, fbl, fa = pixel::pixel(fb, 40, 40);
    assert(near(fr, 90, 6) && near(fg, 160, 6) && near(fbl, 30, 6) && fa == 255);
    // The lossy alpha survives.
    let tr = pixel::new_image(8, 8, 200, 100, 50, 77);
    let ta = pixel::decode(pixel::encode_webp(tr, 90, false));
    let ar, ag, ab, aa = pixel::pixel(ta, 4, 4);
    assert(aa == 77);

    // encode and write take the format. The param is the quality.
    let via = pixel::encode(img, pixel::FORMAT_WEBP, 50);
    assert(via.len > 0 && pixel::decode(via).width == 32);
    // The file that the Python check reads back with Pillow. It holds the
    // plain image, without the clear pixel of the test above.
    var plain = make_busy();
    assert(pixel::write("test-image.webp", plain, pixel::FORMAT_WEBP));
    let fl = pixel::load("test-image.webp");
    assert(fl.width == 32 && fl.height == 32);
    let fm = pixel::metadata("test-image.webp");
    assert(fm.ok && fm.kind == pixel::KIND_WEBP && fm.width == 32 && fm.height == 32);
    let mm = pixel::metadata_bytes(ll);
    assert(mm.ok && mm.kind == pixel::KIND_WEBP && mm.width == 32);
    // The old format numbers keep their values.
    assert(pixel::FORMAT_PNG == 0 && pixel::FORMAT_JPEG == 1 && pixel::FORMAT_BMP == 2);
    assert(pixel::FORMAT_TGA == 3 && pixel::FORMAT_HDR == 4 && pixel::FORMAT_WEBP == 5);
    assert(pixel::KIND_PIC == 9 && pixel::KIND_WEBP == 10);

    // Bad input to the writer gives the empty result.
    let none = pixel::Image { width: 4, height: 4, pixels: [], icc: [], exif: [] };
    assert(pixel::encode_webp(none, 80, false).len == 0);
    assert(pixel::encode_webp(none, 80, true).len == 0);
    let wide = pixel::Image { width: 16384, height: 1, pixels: [], icc: [], exif: [] };
    assert(pixel::encode_webp(wide, 80, true).len == 0);
    let big = pixel::new_image(16384, 1, 1, 2, 3, 4);
    assert(pixel::encode_webp(big, 80, true).len == 0);
    // A quality out of range does not abort.
    assert(pixel::encode_webp(img, -5, false).len > 0);
    assert(pixel::encode_webp(img, 900, false).len > 0);

    // Hostile bytes: a cut file, a wrong size, a header with no body.
    for n in 0..ll.len {
        if n % 7 != 0 { continue; }
        var cut: u8[>..] = [];
        cut.append(ll[..n]);
        let c = pixel::decode(cut[..]);
        assert(c.pixels.len == 0 || c.pixels.len == 32 * 32 * 4);
        pixel::metadata_bytes(cut[..]);
    }
    var cut2: u8[>..] = [];
    cut2.append(hi[..hi.len / 2]);
    assert(pixel::decode(cut2[..]).pixels.len == 0 || pixel::decode(cut2[..]).width == 32);
    assert(pixel::decode("RIFF").width == 0);
    assert(pixel::decode("RIFF\x04\x00\x00\x00WEBP").width == 0);
    assert(!pixel::metadata_bytes("RIFF\x04\x00\x00\x00WEBPVP8 ").ok);
    // A lossless header that claims 16384 x 16384 pixels and holds no data.
    var lie: u8[>..] = [];
    lie.append(ll[..30]);
    lie[4] = 0xff; lie[5] = 0xff; lie[6] = 0xff; lie[7] = 0x00;
    assert(pixel::decode(lie[..]).pixels.len == 0 || pixel::decode(lie[..]).width == 32);
    // The same file with a flipped dimension byte decodes to nothing or to a size
    // that matches the bytes.
    var bent: u8[>..] = [];
    bent.append(ll[..ll.len]);
    bent[21] = 0xff;
    bent[22] = 0xff;
    let bi = pixel::decode(bent[..]);
    assert(bi.pixels.len == bi.width * bi.height * 4);
    print("webp cases ok\n");
}

fn test_png16() {
    png16_cases::check_read16();
    png16_cases::check_exif_build();
    png16_cases::check_turn();

    // A round trip of 16 bits keeps every value, and the file is a PNG of depth 16.
    var px: u16[>..] = [];
    for i in 0..5 * 3 * 4 { px.push(((i * 4099 + 17) % 65536) as u16); }
    let img = pixel::Image16 { width: 5, height: 3, pixels: px[..] };
    let png = pixel::encode16(img);
    assert(png.len > 33 && png[24] == 16 && png[25] == 6);
    let back = pixel::decode16(png[..]);
    assert(back.width == 5 && back.height == 3 && back.pixels == img.pixels);
    assert(pixel::write16("test-image16.png", img));
    assert(pixel::load16("test-image16.png").pixels == img.pixels);
    // The 8-bit reader sees the high byte of a 16-bit file.
    let low = pixel::decode(png[..]);
    assert(low.width == 5 && low.pixels[0] == (img.pixels[0] >> 8) as u8);

    // The conversions: widen by 257, narrow with rounding, and a round trip.
    let e8 = pixel::new_image(2, 1, 0, 128, 255, 7);
    let e16 = pixel::to_image16(e8);
    assert(e16.pixels[0] == 0 && e16.pixels[1] == 32896 && e16.pixels[2] == 65535 && e16.pixels[3] == 1799);
    assert(pixel::to_image8(e16).pixels == e8.pixels);
    let ones = pixel::Image16 { width: 1, height: 1, pixels: [128, 129, 385, 65535] };
    let n8 = pixel::to_image8(ones);
    assert(n8.pixels[0] == 0 && n8.pixels[1] == 1 && n8.pixels[2] == 1 && n8.pixels[3] == 255);

    // Hostile input: nothing aborts and the answer is empty.
    assert(pixel::decode16([]).width == 0);
    assert(pixel::decode16(png[..20]).width == 0);
    let cutp = pixel::decode16(png[..png.len - 20]);
    assert(cutp.pixels.len == cutp.width * cutp.height * 4);
    var bad: u8[>..] = [];
    bad.append(png[..]);
    bad[40] = bad[40] ^ 255;
    let crc = pixel::decode16(bad[..]);
    assert(crc.pixels.len == crc.width * crc.height * 4);
    var big: u8[>..] = [];
    big.append(png[..33]);
    big[19] = 0x7f; big[20] = 0xff;
    assert(pixel::decode16(big[..]).width == 0);
    assert(pixel::load16("no-such-file.png").width == 0);
    let none = pixel::Image16 { width: 4, height: 4, pixels: [1, 2] };
    assert(pixel::encode16(none).len == 0);
    let short8 = pixel::Image { width: 4, height: 4, pixels: [1], icc: [], exif: [] };
    assert(pixel::to_image8(none).width == 0 && pixel::to_image16(short8).width == 0);
    let huge = pixel::Image16 { width: 2147483647, height: 2147483647, pixels: [1] };
    assert(pixel::encode16(huge).len == 0);

    // The orientation: none, out of range, a hostile block.
    let plain = pixel::new_image(2, 3, 1, 2, 3, 4);
    assert(pixel::orientation(plain) == 1);
    assert(pixel::apply_orientation(plain).pixels == plain.pixels);
    var wb = pixel::exif_new();
    pixel::exif_set_short(wb, 0x0112, 9);
    let odd = pixel::Image { width: 2, height: 3, pixels: copy(plain.pixels), icc: [], exif: pixel::exif_build(wb) };
    assert(pixel::orientation(odd) == 1);
    let junk = pixel::Image { width: 2, height: 3, pixels: copy(plain.pixels), icc: [], exif: [0x49, 0x49, 42, 0, 8, 0, 0, 0, 255, 255, 1, 2] };
    assert(pixel::apply_orientation(junk).pixels == plain.pixels);
    assert(pixel::exif_with_short([0x4d, 0x4d, 0, 42], 0x0112, 1).len == 4);
    var none_b = pixel::exif_new();
    assert(pixel::exif_build(none_b).len == 14);
    print("png16 cases ok\n");
}

// noisy makes an image of bytes that a coder cannot shrink much. It has so
// many different strings that LZW fills its table and clears it.
fn noisy(w: i32, h: i32) -> pixel::Image {
    var px: u8[>..] = [];
    var s: u32 = 12345;
    for i in 0..(w * h) {
        s = s * 1664525 + 1013904223;
        px.push(((s >> 24) & 255) as u8);
        px.push(((s >> 16) & 255) as u8);
        px.push(((s >> 8) & 255) as u8);
        px.push(if i % 3 == 0 { 255 } else { ((s >> 20) & 255) as u8 });
    }
    return pixel::Image { width: w, height: h, pixels: px[..], icc: [], exif: [] };
}

// test_tiff checks the codec: the files of Pillow, the files that the script
// built, the writer of the package and the hostile bytes.
fn test_tiff() {
    tiff_cases::check_decode();
    tiff_cases::check_pages();
    tiff_cases::check_hostile();

    // The constants. The old numbers keep their values.
    assert(pixel::FORMAT_TIFF == 6 && pixel::KIND_TIFF == 11);
    assert(pixel::FORMAT_WEBP == 5 && pixel::KIND_WEBP == 10);

    // Every compression keeps every pixel, also under a clear alpha.
    var img = make_busy();
    pixel::set_pixel(img, 3, 3, 12, 34, 56, 0);
    pixel::set_pixel(img, 4, 3, 99, 98, 97, 77);
    let comps: i32[3] = [pixel::TIFF_COMPRESSION_NONE, pixel::TIFF_COMPRESSION_LZW, pixel::TIFF_COMPRESSION_DEFLATE];
    for c in comps {
        let bytes = pixel::encode_tiff(img, c);
        assert(bytes.len > 8 && bytes[0] == 'I' && bytes[1] == 'I' && bytes[2] == 42 && bytes[3] == 0);
        let back = pixel::decode(bytes);
        assert(back.width == 32 && back.height == 32 && back.pixels == img.pixels);
        assert(pixel::decode_tiff_pages(bytes) == 1);
        let m = pixel::metadata_bytes(bytes);
        assert(m.ok && m.kind == pixel::KIND_TIFF && m.width == 32 && m.height == 32 && m.channels == 4);
        // The same bytes come out of a second write.
        assert(pixel::encode_tiff(img, c) == bytes);
    }

    // A big noisy image fills the table of LZW and the window of Deflate.
    let nz = noisy(150, 130);
    for c in comps {
        let back = pixel::decode(pixel::encode_tiff(nz, c));
        assert(back.width == 150 && back.height == 130 && back.pixels == nz.pixels);
    }
    // A flat image shrinks under LZW and Deflate.
    let flat = pixel::new_image(64, 64, 9, 9, 9, 255);
    let raw_len = pixel::encode_tiff(flat, pixel::TIFF_COMPRESSION_NONE).len;
    assert(pixel::encode_tiff(flat, pixel::TIFF_COMPRESSION_LZW).len < raw_len / 4);
    assert(pixel::encode_tiff(flat, pixel::TIFF_COMPRESSION_DEFLATE).len < raw_len / 4);
    // One pixel.
    let one = pixel::new_image(1, 1, 1, 2, 3, 4);
    for c in comps {
        let ob = pixel::decode(pixel::encode_tiff(one, c));
        assert(ob.width == 1 && ob.pixels == one.pixels);
    }

    // encode and write take the format. The param is the compression.
    assert(pixel::encode(img, pixel::FORMAT_TIFF, 0) == pixel::encode_tiff(img, pixel::TIFF_COMPRESSION_NONE));
    assert(pixel::encode(img, pixel::FORMAT_TIFF, 5) == pixel::encode_tiff(img, pixel::TIFF_COMPRESSION_LZW));
    assert(pixel::encode(img, pixel::FORMAT_TIFF, 3).len == 0);
    assert(pixel::encode_tiff(img, 3).len == 0);
    assert(pixel::encode_tiff(img, -1).len == 0);

    // The files that the Python check reads back with Pillow. They hold the
    // plain image, without the clear pixels of the test above.
    let plain = make_busy();
    assert(pixel::write_tiff_with("test-image-none.tif", plain, pixel::TIFF_COMPRESSION_NONE));
    assert(pixel::write_tiff_with("test-image-lzw.tif", plain, pixel::TIFF_COMPRESSION_LZW));
    assert(pixel::write_tiff_with("test-image-deflate.tif", plain, pixel::TIFF_COMPRESSION_DEFLATE));
    assert(pixel::write_tiff("test-image.tif", plain));
    assert(!pixel::write_tiff_with("test-image-bad.tif", plain, 9));
    let fl = pixel::load("test-image-lzw.tif");
    assert(fl.width == 32 && fl.height == 32 && fl.pixels == plain.pixels);
    let fm = pixel::metadata("test-image-deflate.tif");
    assert(fm.ok && fm.kind == pixel::KIND_TIFF && fm.width == 32 && fm.height == 32);

    // Bad input to the writer gives the empty result.
    let none = pixel::Image { width: 4, height: 4, pixels: [], icc: [], exif: [] };
    assert(pixel::encode_tiff(none, 1).len == 0);
    assert(!pixel::write_tiff("test-image-none2.tif", none));
    assert(pixel::decode_tiff_pages("not a tiff") == 0);
    assert(pixel::decode_tiff_pages([]) == 0);
    assert(pixel::decode("II*\x00").width == 0);
    assert(!pixel::metadata_bytes("MM\x00*\x00\x00\x00\x08").ok);

    // A cut file is a fault or the whole image. A cut that holds all of the
    // bytes of the strip is the whole image.
    for c in comps {
        let good = pixel::encode_tiff(img, c);
        for n in 0..good.len {
            if n % 13 != 0 { continue; }
            var cut: u8[>..] = [];
            cut.append(good[..n]);
            let ci = pixel::decode(cut[..]);
            assert(ci.pixels.len == 0 || ci.pixels.len == 32 * 32 * 4);
            pixel::metadata_bytes(cut[..]);
            pixel::decode_tiff_pages(cut[..]);
        }
    }
    // Every single flipped byte of the header and the directory ends fast.
    let hdr = pixel::encode_tiff(one, pixel::TIFF_COMPRESSION_NONE);
    for i in 0..hdr.len {
        for v in [0, 1, 255] {
            var bent: u8[>..] = [];
            bent.append(hdr[..]);
            bent[i] = v as u8;
            let bi = pixel::decode(bent[..]);
            assert(bi.pixels.len == bi.width * bi.height * 4);
        }
    }
    print("tiff cases ok\n");
}

fn main() {
    meta_cases();
    test_round_trip();
    test_info();
    test_load_failure();
    test_memory_round_trip();
    test_options();
    test_files();
    test_metadata();
    test_resize();
    test_geometry();
    test_hostile_size();
    gif_tests::test_gif_round_trip();
    gif_tests::test_gif_quant();
    gif_tests::test_gif_clear();
    gif_tests::test_gif_offsets();
    gif_tests::test_gif_hostile();
    gif_cases::check_gif();
    jpeg_cases::check_jpeg();
    jpeg_cases::check_jpeg_hostile();
    test_webp();
    avif_cases::check_avif();
    avif_enc_cases::check_avif_enc();
    test_png16();
    test_tiff();
    print("all tests passed");
    return 0;
}
