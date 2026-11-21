/*
 * Hello World for PocketBook (InkView SDK).
 *
 * InkView apps are event driven: InkViewMain() runs the event loop and calls
 * main_handler() for lifecycle, key and touch events.
 */
#include <inkview.h>

static ifont *title_font;
static ifont *body_font;
static int taps;

static void draw(void)
{
    const int w = ScreenWidth();
    const int h = ScreenHeight();
    const int margin = w / 12;

    ClearScreen();

    SetFont(title_font, BLACK);
    DrawTextRect(0, h / 3, w, 80, "Hello, PocketBook!", ALIGN_CENTER | VALIGN_MIDDLE);

    char line[64];
    snprintf(line, sizeof line, "Screen %dx%d  -  taps: %d", w, h, taps);
    SetFont(body_font, DGRAY);
    DrawTextRect(0, h / 3 + 100, w, 50, line, ALIGN_CENTER | VALIGN_MIDDLE);

    DrawTextRect(margin, h - 160, w - 2 * margin, 50, "Tap anywhere to count, press Back / Home to exit",
                 ALIGN_CENTER | VALIGN_MIDDLE);
    DrawRect(margin, h / 3 - 30, w - 2 * margin, 220, BLACK);

    FullUpdate();
}

static int main_handler(int type, int par1, int par2)
{
    (void)par2;

    switch (type) {
    case EVT_INIT:
        title_font = OpenFont(DEFAULTFONTB, 48, 1);
        body_font = OpenFont(DEFAULTFONT, 28, 1);
        break;

    case EVT_SHOW:
        draw();
        break;

    case EVT_POINTERUP:
        taps++;
        draw();
        break;

    case EVT_KEYPRESS:
        if (par1 == IV_KEY_BACK || par1 == IV_KEY_HOME || par1 == IV_KEY_PREV) {
            CloseApp();
        }
        break;

    case EVT_EXIT:
        CloseFont(title_font);
        CloseFont(body_font);
        break;
    }
    return 0;
}

int main(void)
{
    InkViewMain(main_handler);
    return 0;
}
