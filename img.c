#include <stdio.h>

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

    printf("img;%d;%d;%d;", w, h, 4);
    fwrite(img, sizeof(unsigned char), w * h * 4, stdout);

    return 0;
}
