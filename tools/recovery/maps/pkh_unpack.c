#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * FTGameOS::nzip::lzw_img_unpack is an exported cdecl function in the
 * matching 32-bit fkernel.dll.  Its first two parameters are destination and
 * source buffers; the third is the destination capacity and the fourth is the
 * source length.  The function returns the number of decoded bytes.
 */
typedef int (__cdecl *lzw_img_unpack_t)(unsigned char *, unsigned char *, int, int);

static unsigned char *read_file(const char *path, size_t *size) {
    FILE *stream = fopen(path, "rb");
    long length;
    unsigned char *buffer;
    if (!stream) { perror(path); exit(1); }
    if (fseek(stream, 0, SEEK_END) != 0 || (length = ftell(stream)) < 0) {
        fprintf(stderr, "cannot determine input size: %s\n", path);
        fclose(stream); exit(1);
    }
    rewind(stream);
    buffer = (unsigned char *)malloc((size_t)length);
    if (!buffer || fread(buffer, 1, (size_t)length, stream) != (size_t)length) {
        fprintf(stderr, "cannot read input: %s\n", path);
        fclose(stream); free(buffer); exit(1);
    }
    fclose(stream);
    *size = (size_t)length;
    return buffer;
}

static void write_file(const char *path, const unsigned char *data, size_t size) {
    FILE *stream = fopen(path, "wb");
    if (!stream) { perror(path); exit(1); }
    if (fwrite(data, 1, size, stream) != size) {
        fprintf(stderr, "cannot write output: %s\n", path);
        fclose(stream); exit(1);
    }
    fclose(stream);
}

int main(int argc, char **argv) {
    HMODULE dll;
    lzw_img_unpack_t unpack;
    unsigned char *packed, *raw;
    size_t packed_size;
    size_t capacity;
    int decoded;

    if (argc != 4) {
        fprintf(stderr, "usage: %s <fkernel.dll> <packed.pkh> <raw.bin>\n", argv[0]);
        return 2;
    }
    dll = LoadLibraryA(argv[1]);
    if (!dll) { fprintf(stderr, "LoadLibraryA failed: %lu\n", GetLastError()); return 1; }
    unpack = (lzw_img_unpack_t)GetProcAddress(
        dll, "?lzw_img_unpack@nzip@FTGameOS@@SAHPAE0HH@Z");
    if (!unpack) {
        fprintf(stderr, "lzw_img_unpack export not found: %lu\n", GetLastError());
        FreeLibrary(dll); return 1;
    }
    packed = read_file(argv[2], &packed_size);
    /* PKH navigation grids are small; retain a hard cap against malformed input. */
    capacity = packed_size > (128u * 1024u * 1024u) / 64u
        ? 128u * 1024u * 1024u : packed_size * 64u;
    if (capacity == 0 || capacity > 0x7fffffffu) {
        fprintf(stderr, "invalid output capacity\n");
        free(packed); FreeLibrary(dll); return 1;
    }
    raw = (unsigned char *)malloc(capacity);
    if (!raw) { fprintf(stderr, "output allocation failed\n"); free(packed); FreeLibrary(dll); return 1; }
    decoded = unpack(raw, packed, (int)capacity, (int)packed_size);
    fprintf(stderr, "lzw_img_unpack decoded=%d capacity=%lu input=%lu\n",
            decoded, (unsigned long)capacity, (unsigned long)packed_size);
    if (decoded <= 0 || (size_t)decoded > capacity) {
        fprintf(stderr, "lzw_img_unpack failed\n");
        free(raw); free(packed); FreeLibrary(dll); return 1;
    }
    write_file(argv[3], raw, (size_t)decoded);
    free(raw); free(packed); FreeLibrary(dll);
    return 0;
}
