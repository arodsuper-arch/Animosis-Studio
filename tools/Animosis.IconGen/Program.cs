using SkiaSharp;

// Renders the Animosis mark to a multi-resolution .ico.
//
// SkiaSharp is the same renderer Avalonia draws the app with, so the icon and
// the in-app mark come out of one pipeline rather than drifting apart.
//
//   dotnet run --project tools/Animosis.IconGen -- <font.ttf> <out.ico>

const string PlateColor0 = "#585858";
const string PlateColor1 = "#2B2B2B";
const string PlateColor2 = "#434343";
const string PlateColor3 = "#1C1C1C";
const string PlateColor4 = "#0C0C0C";
const string LetterColor = "#C41E3A";   // dark red, matching the S
const string Letters     = "AS";

var fontPath = args.Length > 0 ? args[0] : "../../client/Animosis.Client/Assets/Fonts/SourceSans3.ttf";
var outPath  = args.Length > 1 ? args[1] : "../../brand/animosis.ico";

if (!File.Exists(fontPath))
{
    Console.Error.WriteLine($"font not found: {Path.GetFullPath(fontPath)}");
    return 1;
}

using var typeface = SKTypeface.FromFile(fontPath)
                     ?? throw new InvalidOperationException("could not load typeface");

Console.WriteLine($"font: {typeface.FamilyName}");

// Taskbar uses 32 at 100% DPI and scales up from there; 16 is the title bar
// and Alt-Tab. Windows picks the nearest, so ship the whole ladder.
int[] sizes = [256, 128, 64, 48, 40, 32, 24, 20, 16];

var pngs = new List<(int Size, byte[] Data)>();
foreach (var size in sizes)
{
    pngs.Add((size, Render(size, typeface)));
    Console.WriteLine($"  rendered {size}x{size}  ({pngs[^1].Data.Length:N0} B)");
}

WriteIco(outPath, pngs);
Console.WriteLine($"wrote {Path.GetFullPath(outPath)}  ({new FileInfo(outPath).Length:N0} B, {pngs.Count} sizes)");

// Also emit a 256 PNG for docs, README and store listings.
var pngPath = Path.ChangeExtension(outPath, ".png");
File.WriteAllBytes(pngPath, pngs[0].Data);
Console.WriteLine($"wrote {Path.GetFullPath(pngPath)}");

return 0;

static byte[] Render(int size, SKTypeface typeface)
{
    var info = new SKImageInfo(size, size, SKColorType.Rgba8888, SKAlphaType.Premul);
    using var surface = SKSurface.Create(info);
    var canvas = surface.Canvas;
    canvas.Clear(SKColors.Transparent);

    float s = size;
    float inset = s * (8f / 256f);          // matches the SVG master's 8/256 margin
    float radius = s * (54f / 256f);
    var plate = new SKRect(inset, inset, s - inset, s - inset);

    // Chromium plate: top-left lit, falling away to near-black bottom-right.
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

    // Specular top edge. Below ~32px it turns to a grey haze, so drop it.
    if (size >= 32)
    {
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

    // Letters. Smaller icons get proportionally larger type or "AS" closes up
    // into a smudge — standard icon hinting, not a scaled-down master.
    float ratio = size <= 20 ? 0.50f : size <= 32 ? 0.46f : 0.42f;
    using var font = new SKFont(typeface, s * ratio);
    font.Subpixel = true;
    font.Edging = SKFontEdging.SubpixelAntialias;

    using var text = new SKPaint { IsAntialias = true, Color = SKColor.Parse(LetterColor) };

    // The bundled Source Sans 3 is a variable font and Skia instantiates its
    // default (Regular) weight. Stroking the glyphs on top of the fill thickens
    // them to roughly SemiBold, which is what the mark wants.
    using var thicken = new SKPaint
    {
        IsAntialias = true, Color = SKColor.Parse(LetterColor),
        Style = SKPaintStyle.Stroke, StrokeWidth = s * 0.018f, StrokeJoin = SKStrokeJoin.Round,
    };

    font.MeasureText(Letters, out var bounds);
    float x = (s - bounds.Width) / 2f - bounds.Left;
    float y = (s - bounds.Height) / 2f - bounds.Top;

    canvas.DrawText(Letters, x, y, SKTextAlign.Left, font, text);
    canvas.DrawText(Letters, x, y, SKTextAlign.Left, font, thicken);

    using var image = surface.Snapshot();
    using var data = image.Encode(SKEncodedImageFormat.Png, 100);
    return data.ToArray();
}

// ICO container with PNG payloads (Vista+). Each directory entry is 16 bytes;
// a 256px image records its dimension as 0, which is how the format spells 256.
static void WriteIco(string path, List<(int Size, byte[] Data)> images)
{
    Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);

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
