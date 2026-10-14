/* 32-bit fkernel.dll UnCode wrapper; fcc_workspace.py compiles it on demand. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__GNUC__)
#  define THISCALL __attribute__((thiscall))
#else
#  define THISCALL __thiscall
#endif

typedef struct NMemFile {
    void    *data;      /* +0x00 */
    uint32_t capacity;  /* +0x04 */
    uint32_t size;      /* +0x08 */
    uint32_t position;  /* +0x0c */
    uint32_t grow;      /* +0x10 */
} NMemFile;

typedef NMemFile * (THISCALL *nmem_ctor_t)(NMemFile *self);
typedef void       (THISCALL *nmem_dtor_t)(NMemFile *self);
typedef uint32_t   (THISCALL *nmem_write_t)(NMemFile *self, const void *src, uint32_t len);
typedef int        (THISCALL *nmem_uncode_t)(NMemFile *self, const char *key);

static void die_win32(const char *what) {
    DWORD e = GetLastError();
    fprintf(stderr, "%s failed (GetLastError=%lu)\n", what, (unsigned long)e);
    exit(1);
}

static unsigned char *read_entire_file(const char *path, uint32_t *out_size) {
    FILE *f = fopen(path, "rb");
    long n;
    unsigned char *buf;

    if (!f) {
        fprintf(stderr, "cannot open input: %s\n", path);
        exit(1);
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        fprintf(stderr, "fseek failed: %s\n", path);
        exit(1);
    }
    n = ftell(f);
    if (n < 0 || (unsigned long)n > 0xffffffffUL) {
        fclose(f);
        fprintf(stderr, "input too large or ftell failed\n");
        exit(1);
    }
    rewind(f);

    buf = (unsigned char *)malloc((size_t)n);
    if (!buf) {
        fclose(f);
        fprintf(stderr, "malloc failed\n");
        exit(1);
    }

    if ((long)fread(buf, 1, (size_t)n, f) != n) {
        fclose(f);
        free(buf);
        fprintf(stderr, "short read: %s\n", path);
        exit(1);
    }

    fclose(f);
    *out_size = (uint32_t)n;
    return buf;
}

static void write_entire_file(const char *path, const void *data, uint32_t size) {
    FILE *f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "cannot open output: %s\n", path);
        exit(1);
    }
    if (fwrite(data, 1, size, f) != size) {
        fclose(f);
        fprintf(stderr, "short write: %s\n", path);
        exit(1);
    }
    fclose(f);
}

static void print_magic(const void *p, uint32_t n) {
    const unsigned char *b = (const unsigned char *)p;
    uint32_t i, lim = n < 16 ? n : 16;

    fprintf(stderr, "first %lu bytes:", (unsigned long)lim);
    for (i = 0; i < lim; ++i)
        fprintf(stderr, " %02x", b[i]);
    fprintf(stderr, "  |");
    for (i = 0; i < lim; ++i) {
        unsigned char c = b[i];
        fputc((c >= 32 && c <= 126) ? c : '.', stderr);
    }
    fprintf(stderr, "|\n");
}

int main(int argc, char **argv) {
    const char *dll_path;
    const char *input_path;
    const char *output_path;
    const char *key = "0003";

    HMODULE dll;
    nmem_ctor_t ctor;
    nmem_dtor_t dtor;
    nmem_write_t write_fn;
    nmem_uncode_t uncode_fn;

    unsigned char *input;
    uint32_t input_size;
    NMemFile mf;
    uint32_t written;
    int ok;

    if (argc < 4 || argc > 5) {
        fprintf(stderr,
            "usage: %s <fkernel.dll> <input.dz/fch> <output.bin> [key]\n"
            "example: %s fkernel.dll files_dir.dz files_dir.decoded 0003\n",
            argv[0], argv[0]);
        return 2;
    }

    dll_path = argv[1];
    input_path = argv[2];
    output_path = argv[3];
    if (argc == 5)
        key = argv[4];

    if (sizeof(NMemFile) != 20) {
        fprintf(stderr, "unexpected NMemFile size: %lu (need 20)\n",
                (unsigned long)sizeof(NMemFile));
        return 1;
    }

    dll = LoadLibraryA(dll_path);
    if (!dll)
        die_win32("LoadLibraryA");

    ctor = (nmem_ctor_t)GetProcAddress(dll, "??0nmemfile@FTGameOS@@QAE@XZ");
    dtor = (nmem_dtor_t)GetProcAddress(dll, "??1nmemfile@FTGameOS@@QAE@XZ");
    write_fn = (nmem_write_t)GetProcAddress(dll, "?Write@nmemfile@FTGameOS@@QAEIPBXI@Z");
    uncode_fn = (nmem_uncode_t)GetProcAddress(dll, "?UnCode@nmemfile@FTGameOS@@QAEHPBD@Z");

    if (!ctor) die_win32("GetProcAddress(nmemfile ctor)");
    if (!dtor) die_win32("GetProcAddress(nmemfile dtor)");
    if (!write_fn) die_win32("GetProcAddress(nmemfile::Write)");
    if (!uncode_fn) die_win32("GetProcAddress(nmemfile::UnCode)");

    input = read_entire_file(input_path, &input_size);

    memset(&mf, 0xcc, sizeof(mf));
    ctor(&mf);

    fprintf(stderr,
        "after ctor: data=%p capacity=%lu size=%lu position=%lu grow=%lu\n",
        mf.data,
        (unsigned long)mf.capacity,
        (unsigned long)mf.size,
        (unsigned long)mf.position,
        (unsigned long)mf.grow);

    fprintf(stderr, "input: %s (%lu bytes)\n",
            input_path, (unsigned long)input_size);
    print_magic(input, input_size);

    written = write_fn(&mf, input, input_size);
    free(input);
    input = NULL;

    fprintf(stderr,
        "after Write: returned=%lu data=%p capacity=%lu size=%lu position=%lu grow=%lu\n",
        (unsigned long)written,
        mf.data,
        (unsigned long)mf.capacity,
        (unsigned long)mf.size,
        (unsigned long)mf.position,
        (unsigned long)mf.grow);

    if (written != input_size) {
        fprintf(stderr, "Write returned unexpected length\n");
        dtor(&mf);
        FreeLibrary(dll);
        return 1;
    }

    ok = uncode_fn(&mf, key);

    fprintf(stderr,
        "after UnCode(\"%s\"): ok=%d data=%p capacity=%lu size=%lu position=%lu grow=%lu\n",
        key, ok,
        mf.data,
        (unsigned long)mf.capacity,
        (unsigned long)mf.size,
        (unsigned long)mf.position,
        (unsigned long)mf.grow);

    if (!ok) {
        fprintf(stderr, "UnCode failed\n");
        dtor(&mf);
        FreeLibrary(dll);
        return 1;
    }

    if (!mf.data || mf.size == 0) {
        fprintf(stderr, "UnCode succeeded but output is empty\n");
        dtor(&mf);
        FreeLibrary(dll);
        return 1;
    }

    print_magic(mf.data, mf.size);
    write_entire_file(output_path, mf.data, mf.size);
    fprintf(stderr, "wrote: %s (%lu bytes)\n",
            output_path, (unsigned long)mf.size);

    if (mf.size >= 4 && memcmp(mf.data, "MSCF", 4) == 0) {
        fprintf(stderr, "output magic is MSCF: this is a Microsoft CAB archive.\n");
    }

    dtor(&mf);
    FreeLibrary(dll);
    return 0;
}
