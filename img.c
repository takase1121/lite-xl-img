#include <stdio.h>

#define QOI_IMPLEMENTATION
#include "./qoi.h"

#define STB_IMAGE_IMPLEMENTATION
#include "./stb_image.h"

int main(int argc, char **argv) {
    int w, h, channels;
    if (argc < 2) {
        fprintf(stderr, "error: no file specified\n");
        return 1;
    }
    unsigned char *img = stbi_load(argv[1], &w, &h, &channels, 4);
    if (img == NULL) {
        fprintf(stderr, "error: cannot load image\n");
        return 1;
    }

    int output_size = 0;
    qoi_desc desc = { 
        .width = w,
        .height = h,
        .channels = 4,
        .colorspace = QOI_LINEAR
    };
    unsigned char *output = qoi_encode(img, &desc, &output_size);
    if (output == NULL) {
        fprintf(stderr, "error: cannot convert image to qoi\n");
        return 1;
    }

    fwrite(output, sizeof(unsigned char), output_size, stdout);

    return 0;
}
