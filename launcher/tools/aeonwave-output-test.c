#include <aax/aax.h>
#include <stdio.h>
#include <stdlib.h>

static void list_devices(void)
{
    unsigned i;
    const enum aaxRenderMode mode = AAX_MODE_WRITE_SPATIAL;

    printf("AeonWave drivers/devices for spatial output:\n");
    for (i = 0; i < aaxDriverGetCount(mode); ++i) {
        aaxConfig driver = aaxDriverGetByPos(i, mode);
        unsigned j;
        const char *name;

        if (!driver)
            continue;
        name = aaxDriverGetSetup(driver, AAX_NAME_STRING);
        printf("  driver: %s\n", name ? name : "(unnamed)");
        for (j = 0; j < aaxDriverGetDeviceCount(driver, mode); ++j) {
            const char *device = aaxDriverGetDeviceNameByPos(driver, j, mode);
            printf("    device: %s\n", device ? device : "(unnamed)");
        }
        aaxDriverDestroy(driver);
    }
}

int main(int argc, char **argv)
{
    const char *device = argc > 1 ? argv[1] : "PulseAudio on default";
    enum aaxErrorType error;
    const char *error_text;
    int ok;

    printf("AeonWave output test\n");
    printf("requested device: %s\n", device);
    list_devices();
    fflush(stdout);

    printf("playing AeonWave logo for about 3 seconds...\n");
    fflush(stdout);
    ok = aaxPlaySoundLogo(device) ? 1 : 0;
    error = aaxGetErrorNo();
    error_text = aaxGetErrorString(error);
    printf("result: %s\n", ok ? "PASS" : "FAIL");
    printf("error: %d %s\n", (int)error, error_text ? error_text : "(none)");
    return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
