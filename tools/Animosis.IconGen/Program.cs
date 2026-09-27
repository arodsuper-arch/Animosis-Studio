using SkiaSharp;

// Renders every Animosis brand asset from one definition.
//
// SkiaSharp is the same renderer Avalonia draws the client with, so the icons,
// the splash, the editor SVGs and the in-app mark come out of one pipeline
// rather than drifting apart.
//
//   dotnet run --project tools/Animosis.IconGen -- <font.ttf> <outDir>
//
// Emits:
//   animosis.ico / animosis_console.ico   multi-size, 16..256
//   animosis.png / app_icon.png           256 mark
//   splash.png                            640x360 boot splash
//   editor-icons/*.svg                    replacements for engine editor/icons

const string PlateColor0 = "#585858";
const string PlateColor1 = "#2B2B2B";
const string PlateColor2 = "#434343";
const string PlateColor3 = "#1C1C1C";
const string PlateColor4 = "#0C0C0C";
const string LetterColor = "#C41E3A";   // dark red, matching the S
const string WordColor   = "#EDEDED";
// Animosis Studio (the client) is AS; Animosis Engine (the forked editor) is AE.
// One generator, two products, identical construction.

var fontPath = args.Length > 0 ? args[0] : "client/Animosis.Client/Assets/Fonts/SourceSans3.ttf";
var outDir   = args.Length > 1 ? args[1] : "brand";
var Letters  = args.Length > 2 ? args[2] : "AS";
var Wordmark = args.Length > 3 ? args[3] : "ANIMOSIS";

if (!File.Exists(fontPath))
{
    Console.Error.WriteLine($"font not found: {Path.GetFullPath(fontPath)}");
    return 1;
}

Directory.CreateDirectory(outDir);

using var typeface = SKTypeface.FromFile(fontPath)
                     ?? throw new InvalidOperationException("could not load typeface");
Console.WriteLine($"font: {typeface.FamilyName}   letters: {Letters}   wordmark: {Wordmark}");

// Taskbar uses 32 at 100% DPI and scales up; 16 is the title bar and Alt-Tab.
// Windows picks the nearest, so ship the whole ladder.
int[] sizes = [256, 128, 64, 48, 40, 32, 24, 20, 16];

var pngs = new List<(int Size, byte[] Data)>();
foreach (var size in sizes)
{
    pngs.Add((size, RenderMark(size, typeface, Letters)));
}
Console.WriteLine($"rendered {sizes.Length} mark sizes\n");

WriteIco(Path.Combine(outDir, "animosis.ico"), pngs);
WriteIco(Path.Combine(outDir, "animosis_console.ico"), pngs);
Emit(Path.Combine(outDir, "animosis.png"), pngs[0].Data);
Emit(Path.Combine(outDir, "app_icon.png"), pngs[0].Data);
Emit(Path.Combine(outDir, "splash.png"), RenderSplash(640, 360, typeface, Letters, Wordmark));

EmitEditorIcons(Path.Combine(outDir, "editor-icons"), typeface);

Console.WriteLine($"\nwritten to {Path.GetFullPath(outDir)}");
return 0;

void Emit(string path, byte[] data)
{
    File.WriteAllBytes(path, data);
    Console.WriteLine($"  {Path.GetFileName(path),-26} {data.Length,8:N0} B");
}

// ================================================================ the mark ==

static void DrawPlate(SKCanvas canvas, SKRect plate, float s, bool withEdge)
{
    float radius = s * (54f / 256f);

    using var plateShader = SKShader.CreateLinearGradient(
        new SKPoint(plate.Left, plate.Top),
        new SKPoint(plate.Left + plate.Width * 0.6f, plate.Bottom),
        [
            SKColor.Parse(PlateColor0), SKColor.Parse(PlateColor1), SKColor.Parse(PlateColor2),
            SKColor.Parse(PlateColor3), SKColor.Parse(PlateColor4),
        ],
        [0f, 0.34f, 0.51f, 0.76f, 1f],
        SKShaderTileMode.Clamp);

    using (var paint = new SKPaint { IsAntialias = true, Shader = plateShader })
    {
        canvas.DrawRoundRect(plate, radius, radius, paint);
    }

    // Specular top edge. Below ~32px it turns into a grey haze, so it is dropped.
    if (!withEdge)
    {
        return;
    }

    using var edgeShader = SKShader.CreateLinearGradient(
        new SKPoint(0, plate.Top), new SKPoint(0, plate.Bottom),
        [new SKColor(255, 255, 255, 87), new SKColor(255, 255, 255, 13), new SKColor(255, 255, 255, 31)],
        [0f, 0.45f, 1f], SKShaderTileMode.Clamp);

    using var edge = new SKPaint
    {
        IsAntialias = true, Shader = edgeShader,
        Style = SKPaintStyle.Stroke, StrokeWidth = Math.Max(1f, s * (2f / 256f)),
    };
    canvas.DrawRoundRect(plate, radius, radius, edge);
}

static void DrawLetters(SKCanvas canvas, SKRect box, float s, SKTypeface typeface, float ratio, string letters)
{
    using var font = new SKFont(typeface, s * ratio) { Subpixel = true, Edging = SKFontEdging.SubpixelAntialias };
    using var fill = new SKPaint { IsAntialias = true, Color = SKColor.Parse(LetterColor) };

    // Source Sans 3 is a variable font and Skia instantiates its default
    // (Regular) weight. Stroking over the fill thickens it to roughly SemiBold.
    using var thicken = new SKPaint
    {
        IsAntialias = true, Color = SKColor.Parse(LetterColor),
        Style = SKPaintStyle.Stroke, StrokeWidth = s * 0.018f, StrokeJoin = SKStrokeJoin.Round,
    };

    font.MeasureText(letters, out var bounds);
    float x = box.Left + (box.Width - bounds.Width) / 2f - bounds.Left;
    float y = box.Top + (box.Height - bounds.Height) / 2f - bounds.Top;

    canvas.DrawText(letters, x, y, SKTextAlign.Left, font, fill);
    canvas.DrawText(letters, x, y, SKTextAlign.Left, font, thicken);
}

static byte[] RenderMark(int size, SKTypeface typeface, string letters)
{
    using var surface = SKSurface.Create(new SKImageInfo(size, size, SKColorType.Rgba8888, SKAlphaType.Premul));
    var canvas = surface.Canvas;
    canvas.Clear(SKColors.Transparent);

    float s = size;
    float inset = s * (8f / 256f);   // matches the SVG master's 8/256 margin
    var plate = new SKRect(inset, inset, s - inset, s - inset);

    DrawPlate(canvas, plate, s, withEdge: size >= 32);

    // Smaller icons get proportionally larger type or "AS" closes into a smudge.
    float ratio = size <= 20 ? 0.50f : size <= 32 ? 0.46f : 0.42f;
    DrawLetters(canvas, new SKRect(0, 0, s, s), s, typeface, ratio, letters);

    using var image = surface.Snapshot();
    using var data = image.Encode(SKEncodedImageFormat.Png, 100);
    return data.ToArray();
}

static byte[] RenderSplash(int width, int height, SKTypeface typeface, string letters, string wordmark)
{
    using var surface = SKSurface.Create(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Premul));
    var canvas = surface.Canvas;
    // Transparent: the engine's splash background colour shows through, so the
    // splash stays correct if that colour is retuned later.
    canvas.Clear(SKColors.Transparent);

    float plateSize = height * 0.42f;
    float plateX = (width - plateSize) / 2f;
    float plateY = height * 0.20f;
    var plate = new SKRect(plateX, plateY, plateX + plateSize, plateY + plateSize);

    DrawPlate(canvas, plate, plateSize, withEdge: true);
    DrawLetters(canvas, plate, plateSize, typeface, 0.42f, letters);

    using var wordFont = new SKFont(typeface, height * 0.085f) { Subpixel = true, Edging = SKFontEdging.SubpixelAntialias };
    using var wordPaint = new SKPaint { IsAntialias = true, Color = SKColor.Parse(WordColor) };

    wordFont.MeasureText(wordmark, out var wb);
    canvas.DrawText(wordmark, (width - wb.Width) / 2f - wb.Left, plate.Bottom + height * 0.155f,
                    SKTextAlign.Left, wordFont, wordPaint);

    using var image = surface.Snapshot();
    using var data = image.Encode(SKEncodedImageFormat.Png, 100);
    return data.ToArray();
}

// ======================================================== editor icon SVGs ==
//
// Replacements for editor/icons/*.svg in the engine fork. The upstream
// FILENAMES are kept deliberately: the engine looks these up by name
// (SNAME("Godot"), "TitleBarLogo"), so renaming would mean editing C++ for
// nothing a user ever sees.
//
// Godot rasterises these with ThorVG, which has NO <text> support, so every
// glyph is emitted as outline path data. Attributes use single quotes, which
// XML permits, to keep the C# free of escaping.

void EmitEditorIcons(string dir, SKTypeface tf)
{
    Directory.CreateDirectory(dir);
    Console.WriteLine();

    Write("Godot.svg", MarkSvg(16, tf, LetterColor, plate: true));
    Write("GodotMonochrome.svg", MarkSvg(16, tf, "#ffffff", plate: false));
    Write("GodotFile.svg", MarkSvg(64, tf, LetterColor, plate: true));
    Write("Logo.svg", WordmarkSvg(187, 69, tf));
    Write("TitleBarLogo.svg", WordmarkSvg(100, 24, tf));

    void Write(string name, string svg)
    {
        File.WriteAllText(Path.Combine(dir, name), svg);
        Console.WriteLine($"  editor-icons/{name,-24} {svg.Length,7:N0} B");
    }
}

static (string D, float W, float H) Glyphs(string text, SKTypeface tf, float size)
{
    using var f = new SKFont(tf, size);
    f.MeasureText(text, out var b);
    using var path = f.GetTextPath(text, new SKPoint(-b.Left, -b.Top));
    return (path.ToSvgPathData(), b.Width, b.Height);
}

static string PlateGradient() =>
    "<defs><linearGradient id='p' x1='0' y1='0' x2='0.6' y2='1'>"
    + $"<stop offset='0' stop-color='{PlateColor0}'/>"
    + $"<stop offset='0.34' stop-color='{PlateColor1}'/>"
    + $"<stop offset='0.51' stop-color='{PlateColor2}'/>"
    + $"<stop offset='1' stop-color='{PlateColor4}'/>"
    + "</linearGradient></defs>";

string MarkSvg(int size, SKTypeface tf, string letterFill, bool plate)
{
    var (d, w, h) = Glyphs(Letters, tf, 110f);
    float scale = plate ? 1f : 1.1f;
    float tx = (256f - w * scale) / 2f;
    float ty = (256f - h * scale) / 2f;

    string body = plate
        ? PlateGradient() + "\n  <rect x='8' y='8' width='240' height='240' rx='54' fill='url(#p)'/>"
        : "<rect x='14' y='14' width='228' height='228' rx='50' fill='none' stroke='#ffffff' stroke-width='16'/>";

    return $"<svg xmlns='http://www.w3.org/2000/svg' width='{size}' height='{size}' viewBox='0 0 256 256'>\n"
         + $"  {body}\n"
         + $"  <g transform='translate({tx:F2},{ty:F2}) scale({scale:F3})'><path fill='{letterFill}' d='{d}'/></g>\n"
         + "</svg>\n";
}

string WordmarkSvg(int width, int height, SKTypeface tf)
{
    float pad = height * 0.10f;
    float plateSize = height - pad * 2f;
    float gap = height * 0.20f;

    var (markD, mw, mh) = Glyphs(Letters, tf, 110f);
    float markScale = plateSize * 0.44f / mh;
    float markTx = pad + (plateSize - mw * markScale) / 2f;
    float markTy = pad + (plateSize - mh * markScale) / 2f;

    var (wordD, _, wh) = Glyphs(Wordmark, tf, 110f);
    float wordScale = height * 0.32f / wh;
    float wordTx = pad + plateSize + gap;
    float wordTy = (height - wh * wordScale) / 2f;

    return $"<svg xmlns='http://www.w3.org/2000/svg' width='{width}' height='{height}' viewBox='0 0 {width} {height}'>\n"
         + $"  {PlateGradient()}\n"
         + $"  <rect x='{pad:F2}' y='{pad:F2}' width='{plateSize:F2}' height='{plateSize:F2}' rx='{plateSize * 0.211f:F2}' fill='url(#p)'/>\n"
         + $"  <g transform='translate({markTx:F2},{markTy:F2}) scale({markScale:F4})'><path fill='{LetterColor}' d='{markD}'/></g>\n"
         + $"  <g transform='translate({wordTx:F2},{wordTy:F2}) scale({wordScale:F4})'><path fill='{WordColor}' d='{wordD}'/></g>\n"
         + "</svg>\n";
}

// ================================================================= the ico ==

// ICO container with PNG payloads (Vista+). Each directory entry is 16 bytes;
// a 256px image records its dimension as 0, which is how the format spells 256.
static void WriteIco(string path, List<(int Size, byte[] Data)> images)
{
    using var fs = File.Create(path);
    using var w = new BinaryWriter(fs);

    w.Write((ushort)0);                    // reserved
    w.Write((ushort)1);                    // type: icon
    w.Write((ushort)images.Count);

    int offset = 6 + 16 * images.Count;
    foreach (var (size, data) in images)
    {
        w.Write((byte)(size >= 256 ? 0 : size));   // width
        w.Write((byte)(size >= 256 ? 0 : size));   // height
        w.Write((byte)0);                          // palette count
        w.Write((byte)0);                          // reserved
        w.Write((ushort)1);                        // colour planes
        w.Write((ushort)32);                       // bits per pixel
        w.Write(data.Length);
        w.Write(offset);
        offset += data.Length;
    }

    foreach (var (_, data) in images)
    {
        w.Write(data);
    }
}
