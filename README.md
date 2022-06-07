# lite-xl-img

Because you can.

This plugin overrides `renderer.draw_rect` and `renderer.set_clip_rect` to check if any draw calls occlude the `ImgView`. If it is occluded, the image will be rerendered. As you expect, this is **slow** and it **will slow down your editor even when not in use.**

The image is rendered pixel-by-pixel with `renderer.draw_rect`. The renderer doesn't attempt to be smart by merging adjacent pixels, so it will be **very slow**.

This is actually a [QOI] viewer. However, it does support other common image formats like PNG and JPGs with a converter.

This repo also contains a QOI decoder modified from [SloppyQOI]. This modified decoder can decode image on-the-fly with an iterator based API.

### Screenshot

![screenshot]

### Install

Grab the plugin from [Releases] and extract it in `USERDIR/plugins/img`. `USERDIR` is usually `~/.config/lite-xl`.

### Build

```sh
$ gcc -o img img.c -lm
```

### Wontfixes

- resize images
- moving image around
- animation
- actually display image (without hacks)


[QOI]: https://qoiformat.org/
[SloppyQOI]: https://github.com/ReFreezed/SloppyQOI
[screenshot]: https://user-images.githubusercontent.com/20792268/172350531-79730323-8dd3-491c-8ce3-e9bc0651e0d2.png
[Releases]: https://github.com/takase1121/lite-xl-img/releases/latest
