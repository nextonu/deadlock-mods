// Deadlock modide lüliti joonistatud osad: ümarad kaardid, nupud ja otsingukast.
// DeadlockModToggle.ps1 laeb selle Add-Type'iga (C# 5, .NET Framework).
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DlUi
{
    public static class G
    {
        public static GraphicsPath Round(RectangleF r, float rad)
        {
            var p = new GraphicsPath();
            float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
            if (d <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        public static Color Mix(Color a, Color b, float t)
        {
            if (t < 0) t = 0; if (t > 1) t = 1;
            return Color.FromArgb((int)(a.A + (b.A - a.A) * t), (int)(a.R + (b.R - a.R) * t),
                                  (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
        }
        public static Color Hex(string h) { return ColorTranslator.FromHtml(h); }

        public static Color Bg = Hex("#181818"), Panel = Hex("#1F1F1F"), PanelHover = Hex("#272729"),
            Raised = Hex("#252526"), Line = Hex("#2B2B2B"), Line2 = Hex("#3C3C3C"), LineHover = Hex("#4A4A4F"),
            Text = Hex("#CCCCCC"), Bright = Hex("#FFFFFF"), Muted = Hex("#9D9D9D"), Hover = Hex("#303033"),
            Brand = Hex("#EAB308"), BrandHover = Hex("#F5C518"), OnFill = Hex("#4A3F17"), OnHover = Hex("#5C4E1B"),
            OnLine = Hex("#9A7A0C"), Ink = Hex("#111111");
        // PageBg = kaartide ala taust; HeadText/HeadMuted = tekst tumedal päisel/ribadel
        public static Color PageBg = Hex("#181818"), HeadText = Hex("#CCCCCC"), HeadBright = Hex("#FFFFFF"), HeadMuted = Hex("#9D9D9D");
        // Vahelehtede riba ja tumedad ("Quick Buy") nupud
        public static Color TabBg = Hex("#181818"), TabSel = Hex("#FFFFFF"), TabIdle = Hex("#9D9D9D"), TabHover = Hex("#CCCCCC"),
            TabLine = Hex("#EAB308"), TabEdge = Hex("#2B2B2B"), TabNew = Hex("#EAB308"),
            DarkFill = Hex("#252526"), DarkHover = Hex("#303033"), DarkLine = Hex("#3C3C3C"),
            SearchFill = Hex("#252526"), SearchText = Hex("#FFFFFF");

        // --- Teemad: "deadlock" (vaikimisi, poe stiil) ja "ajukas" (eelmine must-kollane) ---
        // "dark" = sama poe stiil, aga tume (öine pärgament, tumedad kaardid, hele kiri)
        public static string Theme = "ajukas";
        public static bool Deco { get { return Theme != "ajukas"; } }
        public static bool Night { get { return Theme == "dark"; } }

        // Heledal paberil loetav tume tekstivärv (punane/roheline/pruun rida) -> tumedas teemas sama tooni hele variant
        public static Color Fg(string hex)
        {
            Color c = Hex(hex);
            if (!Night) return c;
            float h = c.GetHue(), s = Math.Min(1f, c.GetSaturation() * 0.85f), l = 0.70f;
            float q = l < 0.5f ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
            Func<float, int> ch = tt =>
            {
                if (tt < 0) tt += 1; if (tt > 1) tt -= 1;
                float v = tt < 1f / 6 ? p + (q - p) * 6 * tt : tt < 0.5f ? q : tt < 2f / 3 ? p + (q - p) * (2f / 3 - tt) * 6 : p;
                return (int)Math.Round(Math.Max(0, Math.Min(1, v)) * 255);
            };
            return Color.FromArgb(ch(h / 360 + 1f / 3), ch(h / 360), ch(h / 360 - 1f / 3));
        }

        public static void Apply(string theme)
        {
            Theme = theme == "ajukas" ? "ajukas" : theme == "dark" ? "dark" : "deadlock";
            if (!Deco) return;
            // Nagu mängu pood: tume raam (päis, ribad), kulunud paberleht, kreemikad esemekaardid tumeda tekstiga
            Bg = Hex("#16161A"); PageBg = Hex("#B8AA8E");
            Panel = Hex("#E0D4BB"); PanelHover = Hex("#E9DEC8"); Raised = Hex("#CFC1A5"); Hover = Hex("#C4B598");
            Line = Hex("#9C8D70"); Line2 = Hex("#8C7D61"); LineHover = Hex("#665944");
            Text = Hex("#2E2822"); Bright = Hex("#14110D"); Muted = Hex("#463C30");   // (oli #6B5F4E: liiga hele beežil taustal)
            HeadText = Hex("#E6DECF"); HeadBright = Hex("#FFFFFF"); HeadMuted = Hex("#9C9384");
            Brand = Hex("#E2B456"); BrandHover = Hex("#F0C46A"); OnFill = Hex("#E9C77A"); OnHover = Hex("#F0D08A");
            OnLine = Hex("#B98A2A"); Ink = Hex("#15100A");
            // poe ülemine kategooriariba: tumedam pärgament, tume kiri
            TabBg = Hex("#B5A78B"); TabSel = Hex("#14110D"); TabIdle = Hex("#3A3128"); TabHover = Hex("#14110D"); TabNew = Hex("#6E3008");   // (oli #5B5043 #A3957A-l: liiga hele)
            TabLine = Hex("#C0661F"); TabEdge = Hex("#8E8169");
            // "Quick Buy" kastid: tumepruun, kuldne äär
            DarkFill = Hex("#3A332C"); DarkHover = Hex("#4A4138"); DarkLine = Hex("#7A6440");
            SearchFill = Hex("#2A2520"); SearchText = Hex("#E6DECF");
            if (!Night) return;
            // Tume poe stiil: söemust-pruun leht, tumedad esemekaardid, kreemjas kiri, samad kategooriavärvid
            Bg = Hex("#121014"); PageBg = Hex("#211D18");
            Panel = Hex("#2F2922"); PanelHover = Hex("#3A3229"); Raised = Hex("#28231D"); Hover = Hex("#433A2F");
            Line = Hex("#4A4033"); Line2 = Hex("#5A4D3C"); LineHover = Hex("#8C7756");
            Text = Hex("#DDD3C1"); Bright = Hex("#FFF6E6"); Muted = Hex("#ADA08A");
            OnFill = Hex("#6A5326"); OnHover = Hex("#7A612D");
            TabBg = Hex("#1A1714"); TabSel = Hex("#FFF6E6"); TabIdle = Hex("#A3967F"); TabHover = Hex("#DDD3C1");
            TabLine = Hex("#E07A2B"); TabEdge = Hex("#3A3229"); TabNew = Hex("#F08A3B");
        }

        // Poe kategooriate värvid: relv (oranž), vaim (lilla), elujõud (roheline), hinged (türkiis)
        public static Color CatColor(string cat)
        {
            if (!Deco) return Brand;
            cat = cat ?? "";
            // poe kategooriad: Weapon oranž, Spirit lilla, Vitality roheline; kaart sinine, kasulik türkiis
            if (cat.StartsWith("Skin")) return Hex("#D9772B");
            if (cat.StartsWith("Map") || cat.StartsWith("Kaart")) return Hex("#3F86C9");
            if (cat.StartsWith("Visual") || cat.StartsWith("Muu")) return Hex("#8A63BF");
            if (cat.StartsWith("Sound") || cat.StartsWith("Helid")) return Hex("#6FA531");
            return Hex("#2FA493");
        }

        // Embleem (logo ja ikoon): art-deco päikesekiirtega ring, keskel lukuauk.
        public static void DrawEmblem(Graphics g, RectangleF r, bool iconBg)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2, R = Math.Min(r.Width, r.Height) / 2;
            Color gold = Hex("#E2B456"), goldDark = Hex("#8C6420"), soul = Hex("#4FD3BE");
            if (iconBg)
            {
                using (var b = new LinearGradientBrush(r, Hex("#2A2118"), Hex("#0F0D0A"), 90f)) g.FillEllipse(b, r);
            }
            // päikesekiired
            using (var pen = new Pen(Color.FromArgb(150, gold), Math.Max(1f, R * 0.045f)))
            {
                for (int i = 0; i < 16; i++)
                {
                    double a = i * Math.PI / 8;
                    float r1 = R * 0.62f, r2 = R * (i % 2 == 0 ? 0.92f : 0.80f);
                    g.DrawLine(pen, cx + (float)Math.Cos(a) * r1, cy + (float)Math.Sin(a) * r1, cx + (float)Math.Cos(a) * r2, cy + (float)Math.Sin(a) * r2);
                }
            }
            // välimine ja sisemine ring
            using (var pen = new Pen(gold, Math.Max(1.2f, R * 0.08f))) g.DrawEllipse(pen, cx - R * 0.93f, cy - R * 0.93f, R * 1.86f, R * 1.86f);
            var inner = new RectangleF(cx - R * 0.55f, cy - R * 0.55f, R * 1.1f, R * 1.1f);
            using (var b = new LinearGradientBrush(inner, gold, goldDark, 90f)) g.FillEllipse(b, inner);
            // lukuauk hingede (türkiis) kumaga
            using (var path = new GraphicsPath())
            {
                float kr = R * 0.17f;
                path.AddEllipse(cx - kr, cy - R * 0.30f, kr * 2, kr * 2);
                path.AddPolygon(new[] { new PointF(cx - kr * 0.55f, cy - R * 0.06f), new PointF(cx + kr * 0.55f, cy - R * 0.06f),
                                         new PointF(cx + kr * 1.05f, cy + R * 0.36f), new PointF(cx - kr * 1.05f, cy + R * 0.36f) });
                using (var b = new SolidBrush(Hex("#120E09"))) g.FillPath(b, path);
                using (var pen = new Pen(Color.FromArgb(200, soul), Math.Max(1f, R * 0.035f))) g.DrawPath(pen, path);
            }
        }

        // ---------- Paberi tekstuur ("roughed up"): tera, kiud, plekid ----------
        static Bitmap grain;
        public static Bitmap Grain { get { if (grain == null) grain = MakeGrain(256, 7); return grain; } }

        static Bitmap MakeGrain(int s, int seed)
        {
            var rnd = new Random(seed);
            var bmp = new Bitmap(s, s, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Transparent);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                // suured hägused plekid (kulunud paber)
                for (int i = 0; i < 26; i++)
                {
                    float r = 14 + (float)rnd.NextDouble() * 46, x = (float)rnd.NextDouble() * s, y = (float)rnd.NextDouble() * s;
                    bool dark = rnd.Next(3) > 0;
                    using (var b = new SolidBrush(Color.FromArgb(dark ? 10 : 9, dark ? Color.FromArgb(70, 50, 25) : Color.White)))
                        foreach (var dx in new[] { -s, 0, s }) foreach (var dy in new[] { -s, 0, s })
                            g.FillEllipse(b, x - r + dx, y - r * 0.7f + dy, r * 2, r * 1.4f);
                }
                // paberikiud
                for (int i = 0; i < 70; i++)
                {
                    float x = (float)rnd.NextDouble() * s, y = (float)rnd.NextDouble() * s, a = (float)(rnd.NextDouble() * Math.PI);
                    float len = 4 + (float)rnd.NextDouble() * 14;
                    using (var pen = new Pen(Color.FromArgb(18 + rnd.Next(18), 80, 60, 35), 0.8f))
                        g.DrawLine(pen, x, y, x + (float)Math.Cos(a) * len, y + (float)Math.Sin(a) * len);
                }
            }
            // peen tera piksli kaupa
            for (int y = 0; y < s; y++)
                for (int x = 0; x < s; x++)
                {
                    double r = rnd.NextDouble();
                    if (r < 0.16)
                    {
                        var c = bmp.GetPixel(x, y);
                        int a = 14 + rnd.Next(24);
                        bmp.SetPixel(x, y, Color.FromArgb(Math.Min(255, c.A + a), 55, 40, 22));
                    }
                    else if (r < 0.22) bmp.SetPixel(x, y, Color.FromArgb(10 + rnd.Next(16), 255, 250, 235));
                }
            return bmp;
        }

        public static void PaintGrain(Graphics g, GraphicsPath p) { using (var tb = new TextureBrush(Grain)) g.FillPath(tb, p); }
        public static void PaintGrain(Graphics g, Rectangle r) { using (var tb = new TextureBrush(Grain)) g.FillRectangle(tb, r); }

        // Paberleht: põhivärv + tera + tumedamad servad (vinjett)
        public static void PaintPaper(Graphics g, Rectangle r, Color baseCol, bool vignette)
        {
            using (var b = new SolidBrush(baseCol)) g.FillRectangle(b, r);
            PaintGrain(g, r);
            if (!vignette || r.Width < 4 || r.Height < 4) return;
            int w = Math.Min(70, r.Width / 4);
            using (var lb = new LinearGradientBrush(new Rectangle(r.X, r.Y, w, r.Height), Color.FromArgb(55, 40, 28, 12), Color.FromArgb(0, 40, 28, 12), 0f))
                g.FillRectangle(lb, r.X, r.Y, w, r.Height);
            using (var rb = new LinearGradientBrush(new Rectangle(r.Right - w, r.Y, w, r.Height), Color.FromArgb(0, 40, 28, 12), Color.FromArgb(55, 40, 28, 12), 0f))
                g.FillRectangle(rb, r.Right - w, r.Y, w, r.Height);
            using (var tb = new LinearGradientBrush(new Rectangle(r.X, r.Y, r.Width, 24), Color.FromArgb(45, 30, 20, 8), Color.FromArgb(0, 30, 20, 8), 90f))
                g.FillRectangle(tb, r.X, r.Y, r.Width, 24);
        }

        public static void DoubleBuffer(Control c)
        {
            typeof(Control).GetProperty("DoubleBuffered", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)
                .SetValue(c, true, null);
        }
    }

    // Kaartide ala. Kerimine:
    //  * paberi tekstuur on lehe küljes (liigub koos sisuga), nii saab Windows kerimisel lihtsalt pilti
    //    nihutada ja joonistab uuesti ainult tekkinud riba -> kiire;
    //  * sujuv animatsioon käib "idle loopis": kaader tehakse ainult siis, kui sõnumijärjekord on tühi,
    //    nii et hiire ratas läheb alati ette (varem BeginInvoke-tsükkel blokeeris ratta -> jõnksud);
    //  * liikumine on ajapõhine, seega ühtlane igal kaadrisagedusel.
    public class SmoothFlow : FlowLayoutPanel
    {
        static readonly List<SmoothFlow> flows = new List<SmoothFlow>();
        static bool hooked;
        static readonly System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        double target, pos, lastT; bool animating;
        static Bitmap tile;      // pärgamendi plaat (värv + tera), kordub
        Bitmap edges; Size edgesSize;

        const double WheelPx = 1.3, Speed = 26.0;
        public static int Frames;   // mõõtmiseks: mitu kaadrit on joonistatud

        [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
        struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public Point pt; }
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool PeekMessage(out MSG msg, IntPtr hwnd, uint min, uint max, uint remove);

        public SmoothFlow()
        {
            DoubleBuffered = true;
            flows.Add(this);
            if (!hooked) { Application.AddMessageFilter(new WheelFilter()); Application.Idle += OnIdle; hooked = true; prewarm = new Timer(); prewarm.Interval = 25; prewarm.Tick += PrewarmTick; prewarm.Start(); }
        }
        protected override void Dispose(bool disposing)
        {
            flows.Remove(this); animating = false;
            if (disposing && edges != null) edges.Dispose();
            base.Dispose(disposing);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            if (!G.Deco) { base.OnPaintBackground(e); return; }
            if (tile == null)
            {
                tile = new Bitmap(256, 256);
                using (var g = Graphics.FromImage(tile)) G.PaintPaper(g, new Rectangle(0, 0, 256, 256), G.PageBg, false);
            }
            // tekstuur nihkub koos sisuga (AutoScrollPosition), seega Windowsi pildinihutus jääb õigeks
            using (var tb = new TextureBrush(tile))
            {
                tb.TranslateTransform(0, AutoScrollPosition.Y % 256);
                e.Graphics.FillRectangle(tb, e.ClipRectangle);
            }
            // tumedad küljeservad (püstsuunas ühtlased, kerimine neid ei muuda)
            if (edges == null || edgesSize.Width != ClientSize.Width)
            {
                if (edges != null) edges.Dispose();
                edgesSize = new Size(Math.Max(1, ClientSize.Width), 8);
                edges = new Bitmap(edgesSize.Width, edgesSize.Height);
                using (var g = Graphics.FromImage(edges))
                {
                    int w = Math.Min(70, edgesSize.Width / 4);
                    using (var lb = new LinearGradientBrush(new Rectangle(0, 0, w + 1, 8), Color.FromArgb(55, 40, 28, 12), Color.FromArgb(0, 40, 28, 12), 0f))
                        g.FillRectangle(lb, 0, 0, w, 8);
                    using (var rb = new LinearGradientBrush(new Rectangle(edgesSize.Width - w - 1, 0, w + 1, 8), Color.FromArgb(0, 40, 28, 12), Color.FromArgb(55, 40, 28, 12), 0f))
                        g.FillRectangle(rb, edgesSize.Width - w, 0, w, 8);
                }
            }
            using (var eb = new TextureBrush(edges)) e.Graphics.FillRectangle(eb, e.ClipRectangle);
        }

        int MaxScroll { get { return Math.Max(0, DisplayRectangle.Height - ClientSize.Height); } }
        int CurScroll { get { return -AutoScrollPosition.Y; } }

        // ---------- Hetktõmmis (snapshot) ----------
        // Kogu lehe sisu on üks suur pilt. Kerimise ajal näitab SnapView ainult selle pildi lõiku (üks
        // joonistus, <1 ms), päris kaardid (228 eraldi akent) jäävad paigale. 180 ms pärast kerimise lõppu
        // tõstetakse päris kaardid uude kohta ühe korraga (WS_EX_COMPOSITED hetkeks) ja SnapView peidetakse.
        // Muutunud kaardid joonistatakse pildil uuesti järgmise kerimise alguses.
        SnapView view; Bitmap snap; bool snapAll = true, usingSnap, inScroll;
        readonly HashSet<Control> dirty = new HashSet<Control>();
        Timer syncTimer;
        public Bitmap Snap { get { return snap; } }
        public int VisualScroll { get { return usingSnap ? (int)Math.Round(pos) : CurScroll; } }
        public void AttachView(SnapView v)
        {
            view = v; v.Owner = this;
            if (syncTimer == null) { syncTimer = new Timer(); syncTimer.Interval = 180; syncTimer.Tick += (s, e) => SyncNow(); }
        }

        protected override void OnControlAdded(ControlEventArgs e) { base.OnControlAdded(e); Hook(e.Control, e.Control); snapAll = true; }
        void Hook(Control top, Control c)
        {
            c.Invalidated += (s, a) => { if (top.Parent == this) dirty.Add(top); };
            c.ControlAdded += (s, a) => Hook(top, a.Control);
            if (c == top) c.VisibleChanged += (s, a) => { snapAll = true; };
            foreach (Control ch in c.Controls) Hook(top, ch);
        }
        protected override void OnLayout(LayoutEventArgs e) { base.OnLayout(e); if (!inScroll) snapAll = true; }
        protected override void OnResize(EventArgs e) { base.OnResize(e); snapAll = true; }

        void EnsureTiles()
        {
            if (tile == null)
            {
                tile = new Bitmap(256, 256);
                using (var g = Graphics.FromImage(tile)) G.PaintPaper(g, new Rectangle(0, 0, 256, 256), G.PageBg, false);
            }
            if (edges == null || edgesSize.Width != ClientSize.Width)
            {
                if (edges != null) edges.Dispose();
                edgesSize = new Size(Math.Max(1, ClientSize.Width), 8);
                edges = new Bitmap(edgesSize.Width, edgesSize.Height);
                using (var g = Graphics.FromImage(edges))
                {
                    int w = Math.Min(70, edgesSize.Width / 4);
                    using (var lb = new LinearGradientBrush(new Rectangle(0, 0, w + 1, 8), Color.FromArgb(55, 40, 28, 12), Color.FromArgb(0, 40, 28, 12), 0f))
                        g.FillRectangle(lb, 0, 0, w, 8);
                    using (var rb = new LinearGradientBrush(new Rectangle(edgesSize.Width - w - 1, 0, w + 1, 8), Color.FromArgb(0, 40, 28, 12), Color.FromArgb(55, 40, 28, 12), 0f))
                        g.FillRectangle(rb, edgesSize.Width - w, 0, w, 8);
                }
            }
        }
        void PaintBg(Graphics g, Rectangle r)   // sisu koordinaatides (0 = lehe ülaserv)
        {
            if (!G.Deco) { using (var b = new SolidBrush(BackColor)) g.FillRectangle(b, r); return; }
            EnsureTiles();
            using (var tb = new TextureBrush(tile)) g.FillRectangle(tb, r);
            using (var eb = new TextureBrush(edges)) g.FillRectangle(eb, r);
        }

        public static int SnapRenders;   // mõõtmiseks
        public bool HasPending { get { return snapAll || dirty.Count > 0 || snap == null; } }
        public void EnsureSnapshot() { EnsureSnapshot(int.MaxValue, true); }
        // max = mitu kaarti korraga (taustal 2); force = joonista ka hetkel tõusnud (hiire all) kaart
        public void EnsureSnapshot(int max, bool force)
        {
            if (!IsHandleCreated || IsDisposed) return;
            int W = Math.Max(1, ClientSize.Width), H = Math.Max(Math.Max(1, ClientSize.Height), DisplayRectangle.Height);
            if (snap == null || snap.Width != W || snap.Height != H)
            {
                if (snap != null) snap.Dispose();
                snap = new Bitmap(W, H, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                snapAll = true;
            }
            if (snapAll)
            {
                using (var g = Graphics.FromImage(snap)) PaintBg(g, new Rectangle(0, 0, W, H));
                dirty.Clear(); foreach (Control cc in Controls) dirty.Add(cc);
                snapAll = false;
            }
            if (dirty.Count == 0) return;
            int oy = CurScroll, done = 0;
            var todo = new List<Control>(dirty);
            foreach (var c in todo)
            {
                if (done >= max) break;
                var cardC = c as Card; if (!force && cardC != null && cardC.Lift > 0.01f) continue;   // hiire all: hiljem
                dirty.Remove(c);
                if (c.Parent != this || !c.Visible || c.Width <= 0 || c.Height <= 0) continue;
                var r = new Rectangle(c.Left, c.Top + oy, c.Width, c.Height);
                if (r.Bottom <= 0 || r.Top >= H) continue;
                using (var tmp = new Bitmap(c.Width, c.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
                {
                    // taust plaadi järgi samas kohas kui lehel
                    using (var tg = Graphics.FromImage(tmp))
                    {
                        if (G.Deco)
                        {
                            EnsureTiles();
                            using (var tb = new TextureBrush(tile)) { tb.TranslateTransform(-r.X, -r.Y); tg.FillRectangle(tb, 0, 0, c.Width, c.Height); }
                            using (var eb = new TextureBrush(edges)) { eb.TranslateTransform(-r.X, -r.Y); tg.FillRectangle(eb, 0, 0, c.Width, c.Height); }
                        }
                    }
                    c.DrawToBitmap(tmp, new Rectangle(0, 0, c.Width, c.Height));
                    using (var g = Graphics.FromImage(snap)) { g.CompositingMode = CompositingMode.SourceCopy; g.DrawImageUnscaled(tmp, r.X, r.Y); }
                }
                SnapRenders++; done++;
            }
        }

        // Taustal valmistamine: kui keegi ei keri, joonista paar kaarti korraga (aken jääb kiireks)
        static Timer prewarm;
        static void PrewarmTick(object s, EventArgs e)
        {
            var pw = System.Diagnostics.Stopwatch.StartNew();
            try { PrewarmInner(); } finally { Perf.Add("prewarm", pw); }
        }
        static void PrewarmInner()
        {
            foreach (var f in flows) if (f.animating || f.usingSnap) return;
            foreach (var f in flows.ToArray())
                if (!f.IsDisposed && f.IsHandleCreated && f.view != null && f.HasPending) { f.EnsureSnapshot(2, false); return; }
        }

        void BeginSnap()
        {
            if (view == null || usingSnap) return;
            EnsureSnapshot();
            if (snap == null) return;
            usingSnap = true;
            view.Offset = CurScroll;
            view.Visible = true; view.BringToFront(); view.Refresh();
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [System.Runtime.InteropServices.DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);

        // Päris kaardid uude kohta ja hetktõmmis peitu. Kogu ala joonistatakse ühe puhvrina (komponeeritult),
        // nii et vahetuse ajal ei paista poolikut pilti; ekraanil on samal ajal identne hetktõmmis.
        public void SyncNow()
        {
            if (syncTimer != null) syncTimer.Stop();
            if (!usingSnap) return;
            animating = false;
            int y = Math.Max(0, Math.Min(MaxScroll, (int)Math.Round(pos)));
            var host = Parent;
            int ex = 0;
            if (host != null && host.IsHandleCreated) { ex = GetWindowLong(host.Handle, -20); SetWindowLong(host.Handle, -20, ex | 0x02000000); }
            inScroll = true; AutoScrollPosition = new Point(0, y); inScroll = false;
            usingSnap = false;
            view.Visible = false;
            if (host != null && host.IsHandleCreated)
            {
                RedrawWindow(host.Handle, IntPtr.Zero, IntPtr.Zero, RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_UPDATENOW);
                SetWindowLong(host.Handle, -20, ex);
            }
            if (Scrolled != null) Scrolled(this, EventArgs.Empty);
        }

        public void WheelBy(int delta)
        {
            if (!animating) { if (!usingSnap) pos = CurScroll; target = pos; lastT = clock.Elapsed.TotalSeconds; }
            target = Math.Max(0, Math.Min(MaxScroll, target - delta * WheelPx));
            if (syncTimer != null) syncTimer.Stop();
            BeginSnap();
            animating = true;
        }

        static bool QueueEmpty { get { MSG m; return !PeekMessage(out m, IntPtr.Zero, 0, 0, 0); } }

        // Idle loop: senikaua kui keegi animeerib ja Windowsil muud teha pole, tee kaadreid
        static void OnIdle(object s, EventArgs e)
        {
            while (QueueEmpty)
            {
                bool any = false;
                foreach (var f in flows.ToArray()) if (f.animating) { any = true; f.Frame(); }
                if (!any) return;
                System.Threading.Thread.Sleep(1);
            }
        }

        void Frame()
        {
            if (IsDisposed || !IsHandleCreated) { animating = false; return; }
            double now = clock.Elapsed.TotalSeconds, dt = Math.Min(now - lastT, 0.05); lastT = now;
            if (dt <= 0) return;
            pos += (target - pos) * (1 - Math.Exp(-dt * Speed));
            if (Math.Abs(target - pos) < 0.5) { pos = target; animating = false; }
            ShowAt((int)Math.Round(pos)); Frames++;
            if (!animating && usingSnap && syncTimer != null) syncTimer.Start();
        }
        void ShowAt(int y)
        {
            if (usingSnap) { view.Offset = y; view.Invalidate(); view.Update(); if (Scrolled != null) Scrolled(this, EventArgs.Empty); }
            else SetScroll(y);
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool RedrawWindow(IntPtr hwnd, IntPtr rect, IntPtr rgn, uint flags);
        const uint RDW_INVALIDATE = 0x1, RDW_ALLCHILDREN = 0x80, RDW_UPDATENOW = 0x100;

        void SetScroll(int y)
        {
            if (y == CurScroll) return;
            inScroll = true; AutoScrollPosition = new Point(0, y); inScroll = false;
            RedrawWindow(Handle, IntPtr.Zero, IntPtr.Zero, RDW_ALLCHILDREN | RDW_UPDATENOW);
            if (Scrolled != null) Scrolled(this, EventArgs.Empty);
        }
        public event EventHandler Scrolled;

        protected override CreateParams CreateParams { get { return base.CreateParams; } }

        public void JumpTo(int y)
        {
            y = Math.Max(0, Math.Min(MaxScroll, y));
            if (!usingSnap) { pos = CurScroll; BeginSnap(); }
            animating = false; pos = target = y;
            ShowAt(y);
            if (usingSnap && syncTimer != null) { syncTimer.Stop(); syncTimer.Start(); }
        }

        // Püüab rattasündmused enne, kui need lähevad kaardi/nupu kätte, ja suunab hiire all olevale lehele
        class WheelFilter : IMessageFilter
        {
            public bool PreFilterMessage(ref Message m)
            {
                if (m.Msg != 0x020A) return false;
                int delta = (short)((long)m.WParam >> 16);
                Point p = Cursor.Position;
                foreach (var f in flows)
                {
                    if (f.IsDisposed || !f.IsHandleCreated || f.Parent == null || !f.Parent.Visible || !f.Visible) continue;
                    var form = f.FindForm(); if (form == null || form != Form.ActiveForm) continue;
                    Rectangle r = f.Parent.RectangleToScreen(f.Parent.ClientRectangle);
                    if (r.Contains(p)) { f.WheelBy(delta); return true; }
                }
                return false;
            }
        }
    }

    // Kangelase kaart. Hiir peal: kaart tõuseb paar pikslit, servad helenevad, ümber kerge kuma, pilt suumib veidi.
    public class Card : Panel
    {
        public const int Inset = 7;      // ruum kuma ja tõusu jaoks
        public const int LiftPx = 0;     // kaart ei liigu füüsiliselt (laste akende nihutamine tegi värelust); "ette tulek" = vari + kuma + suum
        public Image Picture;
        public Rectangle PicRect;        // kaardi sees, ilma tõusuta
        public bool On;
        public int Radius = 12;
        public float Lift;
        int applied;                     // mitu pikslit lapsi on üles nihutatud
        int bob;                         // valikurežiimi hüpe (pildi nihe üles, px)

        public static Card DebugHover;   // testimiseks: teeskle, et hiir on selle kaardi peal
        static Timer timer;
        static readonly List<Card> all = new List<Card>();
        public static List<Card> All { get { return all; } }

        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = G.Deco ? Color.Transparent : G.PageBg;   // nurkade taga paistab leht (paber)
            all.Add(this);
            if (timer == null) { timer = new Timer(); timer.Interval = 15; timer.Tick += Tick; timer.Start(); }
        }

        // kaart ja tema lapsed (sildid, nupud) joonistatakse korraga -> tõusmisel ei vilgu
        public static bool CompositedCards = false;   // välja: tegi akna lohistamise aeglaseks (Windows joonistas kogu akna iga liigutusega); vilkumist hoiab ära CardFlow + LiftPx=0
        protected override CreateParams CreateParams { get { var cp = base.CreateParams; if (CompositedCards) cp.ExStyle |= 0x02000000; return cp; } }

        protected override void Dispose(bool disposing)
        {
            all.Remove(this);
            base.Dispose(disposing);
        }

        public Rectangle Body
        {
            get { return new Rectangle(Inset, Inset - applied, Width - 2 * Inset - 1, Height - 2 * Inset - 1); }
        }

        static void Tick(object s, EventArgs e)
        {
            var pw = System.Diagnostics.Stopwatch.StartNew();
            try { TickInner(); } finally { Perf.Add("cardTick", pw); }
        }
        static void TickInner()
        {
            Point c = Cursor.Position;
            foreach (var k in all)
            {
                if (k.IsDisposed || !k.IsHandleCreated) continue;
                float target = 0;
                if (k == DebugHover) target = 1;
                else if (k.Visible && k.Parent != null && k.FindForm() == Form.ActiveForm)
                {
                    Rectangle r = k.RectangleToScreen(new Rectangle(Inset, Inset, k.Width - 2 * Inset, k.Height - 2 * Inset));
                    Rectangle view = k.Parent.RectangleToScreen(k.Parent.ClientRectangle);
                    if (r.Contains(c) && view.Contains(c)) target = 1;
                }
                // valikurežiimis (Delete / Check / Updates ...) hiire all oleva kaardi kangelane hüpleb üles-alla
                int bob = (Chip.DeleteMode && target > 0.5f && k.Lift > 0.5f && k.Picture != null) ? Chip.BobPx(4) : 0;
                if (bob != k.bob)
                {
                    var pr = k.PicRect; pr.Inflate(2, 7); k.bob = bob; k.Invalidate(pr, false);
                }
                if (Math.Abs(k.Lift - target) < 0.001f) continue;
                k.Lift += (target - k.Lift) * 0.28f;
                if (Math.Abs(k.Lift - target) < 0.03f) k.Lift = target;
                k.ApplyLift();
            }
        }

        void ApplyLift()
        {
            int want = (int)Math.Round(Lift * LiftPx);
            if (want != applied)
            {
                int d = want - applied; applied = want;
                SuspendLayout();
                foreach (Control ch in Controls) ch.Top -= d;
                ResumeLayout(false);
            }
            Invalidate(true);
        }

        // Valmis pilt: kaart joonistatakse üks kord bitmapiks ja kerimisel ainult kopeeritakse.
        // Elav joonistamine ainult siis, kui kaart tõuseb (hiir peal).
        Bitmap cache; string cacheKey;
        string Key { get { return (On ? "1" : "0") + Width + "x" + Height + "|" + Accent.ToArgb() + "|" + (Picture == null ? 0 : Picture.GetHashCode()) + "|" + PicRect; } }
        public void Prewarm() { if (Width > 0 && Height > 0 && (cache == null || cacheKey != Key)) BuildCache(); }
        void BuildCache()
        {
            if (cache != null) cache.Dispose();
            cache = new Bitmap(Math.Max(1, Width), Math.Max(1, Height), System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (var g = Graphics.FromImage(cache)) { g.Clear(Color.Transparent); PaintCard(g); }
            cacheKey = Key;
        }
        protected override void OnPaint(PaintEventArgs e) { var pw = System.Diagnostics.Stopwatch.StartNew(); PaintBackdrop(e.Graphics); Perf.Add("cardPaint", pw); }
        // Kaardi pilt (vahemälust või elavalt). Kaardi sees olev nuppude paneel (CardFlow) joonistab oma tausta
        // siit, mitte Windowsi "läbipaistva" tausta kaudu - see andis hoveri ajal vahel halli ristküliku.
        public void PaintBackdrop(Graphics g)
        {
            if (Lift < 0.01f && applied == 0)
            {
                if (cache == null || cacheKey != Key) BuildCache();
                g.DrawImageUnscaled(cache, 0, 0);
                return;
            }
            PaintCard(g);
        }

        void PaintCard(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            float t = Lift;
            RectangleF body = Body;

            Color acc = A;
            // kuma ja vari
            if (t > 0.01f)
            {
                Color glow = On ? acc : (G.Deco ? acc : Color.White);
                for (int i = 1; i <= 4; i++)
                {
                    var r = body; r.Inflate(i, i);
                    using (var p = G.Round(r, Radius + i))
                    using (var pen = new Pen(Color.FromArgb((int)((On ? 34 : 14) * t / i), glow), 1.5f))
                        g.DrawPath(pen, p);
                }
                var sh = body; sh.Offset(0, 2 + 4 * t); sh.Inflate(1 + 2 * t, 1 + 2 * t);   // vari kasvab: kaart tundub tõusvat
                using (var p = G.Round(sh, Radius))
                using (var b = new SolidBrush(Color.FromArgb((int)(150 * t), 0, 0, 0)))
                    g.FillPath(b, p);
            }

            using (var p = G.Round(body, Radius))
            {
                Color fill = G.Mix(G.Panel, G.PanelHover, t);
                if (On) fill = G.Mix(fill, acc, 0.07f);
                if (G.Deco)
                {
                    // poe eseme kaart: kreemjas paber teraga, ülevalt kategooria värvi kerge kuma alla
                    using (var b = new SolidBrush(fill)) g.FillPath(b, p);
                    G.PaintGrain(g, p);
                    using (var b = new LinearGradientBrush(new RectangleF(body.X, body.Y, body.Width, body.Height + 1),
                        Color.FromArgb(On ? 70 : (int)(22 + 20 * t), acc), Color.FromArgb(0, acc), 90f)) g.FillPath(b, p);
                }
                else using (var b = new SolidBrush(fill)) g.FillPath(b, p);
                Color line = On ? G.Mix(G.Mix(G.Panel, acc, 0.65f), acc, t) : G.Mix(G.Line, G.Deco ? G.Mix(G.Line, acc, 0.6f) : G.LineHover, t);
                using (var pen = new Pen(line, On ? 1.5f : 1f)) g.DrawPath(pen, p);
            }
            if (G.Deco)
            {
                // ülaserva värviline riba nagu poe esemetel
                var state0 = g.Save();
                using (var clip = G.Round(body, Radius)) g.SetClip(clip);
                using (var b = new SolidBrush(Color.FromArgb(On ? 255 : (int)(110 + 100 * t), acc)))
                    g.FillRectangle(b, body.X, body.Y, body.Width, 3.5f);
                g.Restore(state0);
            }

            if (Picture != null)
            {
                RectangleF pr = PicRect; pr.Offset(0, -applied - bob);
                using (var clip = G.Round(pr, 9))
                {
                    var state = g.Save();
                    g.SetClip(clip);
                    using (var b = new SolidBrush(G.Raised)) g.FillPath(b, clip);
                    float zoom = 1f + 0.10f * t;
                    float sx = pr.Width / Picture.Width, sy = pr.Height / Picture.Height;
                    float s = Math.Max(sx, sy) * zoom;
                    float w = Picture.Width * s, h = Picture.Height * s;
                    g.DrawImage(Picture, pr.X + (pr.Width - w) / 2, pr.Y + (pr.Height - h) * 0.25f, w, h);
                    g.Restore(state);
                }
                using (var p = G.Round(pr, 9))
                using (var pen = new Pen(Color.FromArgb(On ? 150 : 40, On ? acc : Color.White), 1f))
                    g.DrawPath(pen, p);
            }
        }

        // Kategooria värv (Deadlocki teemas); tühi = teema põhivärv
        public Color Accent = Color.Empty;
        Color A { get { return Accent.IsEmpty ? G.Brand : Accent; } }
    }

    // Näitab SmoothFlow hetktõmmise lõiku kerimise ajal (vt SmoothFlow.BeginSnap). Klõps lõpetab hetktõmmise.
    // Kaardi sees olev nuppude paneel: taust tuleb otse kaardi pildist (kaardi koordinaatides),
    // nii on paneel ja tema nupud alati sama pildiga kui kaart, ka hoveri animatsiooni ajal.
    public class CardFlow : FlowLayoutPanel
    {
        public CardFlow()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            var card = Parent as Card;
            if (card == null) { base.OnPaintBackground(e); return; }
            var st = e.Graphics.Save();
            e.Graphics.TranslateTransform(-Left, -Top);
            card.PaintBackdrop(e.Graphics);
            e.Graphics.Restore(st);
        }
    }

    public class SnapView : Control
    {
        public SmoothFlow Owner;
        public int Offset;
        public SnapView()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Opaque, true);
            Visible = false;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (Owner == null || Owner.Snap == null) return;
            var g = e.Graphics;
            g.CompositingMode = CompositingMode.SourceCopy;
            g.InterpolationMode = InterpolationMode.NearestNeighbor;
            int h = Math.Min(Height, Owner.Snap.Height - Offset);
            if (h > 0) g.DrawImage(Owner.Snap, new Rectangle(0, 0, Math.Min(Width, Owner.Snap.Width), h), new Rectangle(0, Offset, Math.Min(Width, Owner.Snap.Width), h), GraphicsUnit.Pixel);
            // pildist välja jääv osa: lehe värv, mitte vana ekraanisisu
            using (var b = new SolidBrush(G.PageBg))
            {
                if (h < Height) g.FillRectangle(b, 0, Math.Max(0, h), Width, Height - Math.Max(0, h));
                if (Owner.Snap.Width < Width) g.FillRectangle(b, Owner.Snap.Width, 0, Width - Owner.Snap.Width, Height);
            }
        }
        protected override void OnMouseDown(MouseEventArgs e) { if (Owner != null) Owner.SyncNow(); base.OnMouseDown(e); }
    }

    // Ilus kerimisriba: kitsas rada ja ümar pronksist liugur. Windowsi oma peidetakse (vt Add-Tab: flow on
    // 17 px laiem kui teda ümbritsev "clip" paneel). Target = keritav paneel; seis loetakse taimeriga.
    public class ScrollBarLite : Control
    {
        ScrollableControl target;
        public ScrollableControl Target
        {
            get { return target; }
            set
            {
                var old = target as SmoothFlow; if (old != null) old.Scrolled -= OnTargetScrolled;
                target = value;
                var sf = target as SmoothFlow; if (sf != null) sf.Scrolled += OnTargetScrolled;
                Invalidate();
            }
        }
        void OnTargetScrolled(object s, EventArgs e) { lastPos = Pos; Invalidate(); Update(); }
        public int Paints;
        Timer tm; bool drag, hover; int grab; int lastPos = -1, lastMax = -1, lastH = -1;

        public ScrollBarLite()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw, true);
            Width = 16;
            tm = new Timer(); tm.Interval = 30;
            tm.Tick += (s, e) => { var pw = System.Diagnostics.Stopwatch.StartNew(); int p = Pos, m = Max; if (p != lastPos || m != lastMax || Height != lastH) { lastPos = p; lastMax = m; lastH = Height; Invalidate(); } Perf.Add("scrollbar", pw); };
            tm.Start();
        }
        protected override void Dispose(bool disposing) { if (disposing && tm != null) { tm.Stop(); tm.Dispose(); } base.Dispose(disposing); }

        int Content { get { return Target == null || Target.IsDisposed ? 0 : Target.DisplayRectangle.Height; } }
        int View { get { return Target == null || Target.IsDisposed ? 0 : Target.ClientSize.Height; } }
        int Max { get { return Math.Max(0, Content - View); } }
        int Pos { get { if (Target == null || Target.IsDisposed) return 0; var sf = Target as SmoothFlow; return sf != null ? sf.VisualScroll : -Target.AutoScrollPosition.Y; } }

        Rectangle Thumb
        {
            get
            {
                int max = Max; if (max <= 0) return Rectangle.Empty;
                int track = Height - 8;
                int th = Math.Max(36, (int)((long)track * View / Math.Max(1, Content)));
                int y = 4 + (int)((long)(track - th) * Pos / max);
                return new Rectangle(3, y, Width - 6, th);
            }
        }

        void ScrollTo(int pos)
        {
            if (Target == null) return;
            pos = Math.Max(0, Math.Min(Max, pos));
            var sf = Target as SmoothFlow;
            if (sf != null) sf.JumpTo(pos); else Target.AutoScrollPosition = new Point(0, pos);
            Invalidate();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            var t = Thumb; if (t.IsEmpty) return;
            if (t.Contains(e.Location)) { drag = true; grab = e.Y - t.Y; Capture = true; }
            else ScrollTo(Pos + (e.Y < t.Y ? -View : View) * 9 / 10);
            base.OnMouseDown(e);
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            bool h = !Thumb.IsEmpty && Thumb.Contains(e.Location);
            if (h != hover) { hover = h; Invalidate(); }
            if (drag)
            {
                int track = Height - 8, th = Thumb.Height;
                if (track - th > 0) ScrollTo((int)((long)(e.Y - grab - 4) * Max / (track - th)));
            }
            base.OnMouseMove(e);
        }
        protected override void OnMouseUp(MouseEventArgs e) { drag = false; Capture = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseWheel(MouseEventArgs e)
        {
            var sf = Target as SmoothFlow;
            if (sf != null) sf.WheelBy(e.Delta); else ScrollTo(Pos - e.Delta);
            base.OnMouseWheel(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Paints++;   // mõõtmiseks
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            if (G.Deco) G.PaintPaper(g, ClientRectangle, G.Mix(G.PageBg, Color.Black, 0.12f), false);
            else using (var b = new SolidBrush(G.PageBg)) g.FillRectangle(b, ClientRectangle);
            // rada
            using (var p = G.Round(new RectangleF(Width / 2f - 2, 4, 4, Height - 8), 2))
            using (var b = new SolidBrush(Color.FromArgb(G.Deco ? 70 : 90, G.Deco ? Color.FromArgb(60, 45, 25) : G.Line2))) g.FillPath(b, p);
            var t = Thumb; if (t.IsEmpty) return;
            Color c = G.Deco ? (drag ? G.Hex("#C08A45") : hover ? G.Hex("#A9773A") : G.Hex("#8A6232")) : (drag || hover ? G.LineHover : G.Line2);
            using (var p = G.Round(t, t.Width / 2f))
            {
                if (G.Deco)
                {
                    // pronksist liugur: valgus vasakult, vari paremalt
                    using (var b = new LinearGradientBrush(t, G.Mix(c, Color.White, 0.25f), G.Mix(c, Color.Black, 0.30f), 0f)) g.FillPath(b, p);
                    using (var pen = new Pen(G.Hex("#4E3718"), 1f)) g.DrawPath(pen, p);
                    // keskel soon
                    float cx = t.X + t.Width / 2f;
                    if (t.Height > 40)
                        using (var pen = new Pen(Color.FromArgb(120, 40, 26, 10), 1.4f)) g.DrawLine(pen, cx, t.Y + 14, cx, t.Bottom - 14);
                    // needid mõlemas otsas (mutrid)
                    foreach (float ry in new[] { t.Y + 7f, t.Bottom - 7f })
                    {
                        var rv = new RectangleF(cx - 3f, ry - 3f, 6f, 6f);
                        using (var b = new LinearGradientBrush(rv, G.Hex("#F3D49A"), G.Hex("#6B4A1E"), 45f)) g.FillEllipse(b, rv);
                        using (var pen = new Pen(G.Hex("#3A2810"), 0.8f)) g.DrawEllipse(pen, rv);
                        using (var hl = new SolidBrush(Color.FromArgb(200, 255, 245, 220))) g.FillEllipse(hl, cx - 1.6f, ry - 1.8f, 1.6f, 1.6f);
                    }
                }
                else using (var b = new SolidBrush(c)) g.FillPath(b, p);
            }
            if (G.Deco)
            {
                // raja otsad: väikesed needid
                foreach (float ry in new[] { 3f, Height - 3f })
                {
                    float cx = Width / 2f; var rv = new RectangleF(cx - 2.5f, ry - 2.5f, 5f, 5f);
                    using (var b = new LinearGradientBrush(rv, G.Hex("#D8B070"), G.Hex("#5A3E18"), 45f)) g.FillEllipse(b, rv);
                }
            }
        }
    }

    // Logo päises: embleem + "DEADLOCK" + "MODID" (Deadlocki teemas)
    public class Logo : Control
    {
        public Logo()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Size = new Size(190, 66);   // ainult nii lai kui logo ise, muidu katab päise nuppe
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            G.DrawEmblem(g, new RectangleF(2, 3, 58, 58), false);
            using (var small = new Font("Bahnschrift SemiBold SemiConden", 10f))
            using (var b = new SolidBrush(G.HeadMuted))
                g.DrawString("D E A D L O C K", small, b, 70, 6);
            using (var big = new Font("Bahnschrift SemiBold Condensed", 27f))
            using (var b = new LinearGradientBrush(new RectangleF(68, 20, 200, 40), G.Hex("#F6D27C"), G.Hex("#B07A26"), 90f))
                g.DrawString("MODS", big, b, 66, 20);
        }
    }

    // Lüliti-nupp ("chip"): ümar, hiirega helenev, vajutades veidi väiksem.
    public class Chip : Control
    {
        bool chk, hover, down;
        public bool OnOff;
        public event EventHandler CheckedChanged;

        public Chip()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
            if (bobTimer == null) { bobTimer = new Timer(); bobTimer.Interval = 30; bobTimer.Tick += BobTick; bobTimer.Start(); }
        }

        public bool Checked
        {
            get { return chk; }
            set { if (chk != value) { chk = value; Invalidate(); if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty); } }
        }

        public string Shown
        {
            get
            {
                if (Marked) return OnOff ? MarkSymbol + "  " + MarkWord : MarkSymbol + "  " + Text;
                return OnOff ? (chk ? "✓  On" : "Off") : (chk ? "✓  " + Text : Text);
            }
        }

        // Paremasse ülanurka joonistatav märk (nt "n" = uus lisa). Tühi = märki pole.
        public string Badge = "";
        public bool Small;
        const int BadgeR = 7, BadgeTop = 5;

        public void FitWidth(int max)
        {
            int w = TextRenderer.MeasureText(OnOff ? "✓  Off " : "✓  " + Text, Font).Width + (Small ? 22 : 30);
            int h = Small ? 24 : 30;
            Size = new Size(Math.Min(w, max) + BadgeR, h + BadgeTop);   // ruum märgi jaoks on alati olemas
        }

        // Alt nurgamärgina: ülanurgas "n", mida vajutades lülitub alt (mitte see nupp ise).
        public Color Accent = Color.Empty;   // kategooria värv (Deadlocki teemas)

        // Kustutamisrežiim: hiire all olev nupp läheb punaseks (kõigil nuppudel korraga).
        public static bool DeleteMode;   // valikurežiim (kustuta / kontrolli / uuenda / vahelehele) on sees
        public bool Marked;   // märgitud (režiimi värviga)
        // Valikurežiimi välimus: kustutamine punane "✕", kontroll sinine "✓", uuendused roheline, vaheleht lilla "+"
        public static Color MarkColor = G.Hex("#B83224");
        public static string MarkSymbol = "✕", MarkWord = "Delete";
        public string AltBadge = "";
        public bool AltOn;
        public bool NoPic;    // modil pole oma pilti -> väike joon nupu all
        public event EventHandler AltClicked;
        bool hoverBadge;

        RectangleF BadgeRect { get { return new RectangleF(Width - 2 * BadgeR - 1, 0.5f, 2 * BadgeR, 2 * BadgeR); } }
        bool OnBadge(Point p)
        {
            if (string.IsNullOrEmpty(AltBadge)) return false;
            var r = BadgeRect; r.Inflate(4, 4);
            return r.Contains(p);
        }
        public bool IsOnBadge(Point p) { return OnBadge(p); }   // paremklõps "n"-il: menüü on aldi jaoks

        protected override void OnMouseEnter(EventArgs e) { hover = true; hot = this; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; hoverBadge = false; down = false; if (hot == this) hot = null; Invalidate(); base.OnMouseLeave(e); }

        // Valikurežiimis hüpleb hiire all olev nupp üles-alla (nagu kaardi kangelane): 0..max px, ~1.5 korda sekundis
        public static int BobPx(int max) { double t = Environment.TickCount / 1000.0; return (int)Math.Round((1 - Math.Cos(t * Math.PI * 2 * 1.5)) / 2 * max); }
        static Chip hot; static Timer bobTimer; int bobShown;
        static void BobTick(object s, EventArgs e)
        {
            var c = hot;
            if (c == null || c.IsDisposed || !DeleteMode) { if (c != null && c.bobShown != 0) c.Invalidate(); return; }
            if (BobPx(3) != c.bobShown) c.Invalidate();
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            bool b = OnBadge(e.Location);
            if (b != hoverBadge) { hoverBadge = b; Invalidate(); }
            base.OnMouseMove(e);
        }
        protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left && !OnBadge(e.Location)) { down = true; Invalidate(); } base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnMouseClick(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                if (OnBadge(e.Location)) { if (AltClicked != null) AltClicked(this, EventArgs.Empty); }
                else Checked = !Checked;
            }
            base.OnMouseClick(e);
        }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

        // Valmis pilt tavaoleku jaoks (hiir pole peal); hiire all/vajutatult joonistatakse elavalt.
        Bitmap cache; string cacheKey;
        string Key { get { return string.Join("|", chk, Marked, Badge, AltBadge, AltOn, Text, Accent.ToArgb(), Width, Height, DeleteMode, Font.Size, OnOff, Small); } }
        static readonly bool UseCache = false;   // vaikimisi väljas: GDI tekst läbipaistval bitmapil saab musta ääre
        public void Prewarm() { if (UseCache && Width > 0 && Height > 0 && (cache == null || cacheKey != Key)) BuildCache(); }
        void BuildCache()
        {
            if (cache != null) cache.Dispose();
            cache = new Bitmap(Math.Max(1, Width), Math.Max(1, Height), System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            bool h = hover, d = down, hb = hoverBadge; hover = false; down = false; hoverBadge = false;
            using (var g = Graphics.FromImage(cache)) { g.Clear(Color.Transparent); PaintChip(g); }
            hover = h; down = d; hoverBadge = hb;
            cacheKey = Key;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            if (UseCache && !hover && !down)   // vaikimisi väljas: GDI tekst läbipaistval bitmapil saab musta ääre
            {
                if (cache == null || cacheKey != Key) BuildCache();
                e.Graphics.DrawImageUnscaled(cache, 0, 0);
                return;
            }
            PaintChip(e.Graphics);
        }

        void PaintChip(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, BadgeTop + 0.5f, Width - BadgeR - 1.5f, Height - BadgeTop - 1.5f);
            if (down) r.Inflate(-1.2f, -1.2f);
            bobShown = (DeleteMode && hover && !down) ? BobPx(3) : 0;
            if (bobShown != 0) g.TranslateTransform(0, -bobShown);
            Color fill = chk ? (hover ? G.OnHover : G.OnFill) : (hover ? G.Hover : G.Raised);
            Color line = chk ? G.Brand : (hover ? G.LineHover : G.Line2);
            Color textCol = chk || hover ? G.Bright : G.Text;
            if (!Accent.IsEmpty)
            {
                if (chk) { fill = hover ? G.Mix(Accent, Color.White, 0.12f) : Accent; line = G.Mix(Accent, Color.Black, 0.25f); textCol = Color.White; }
                else if (hover) line = G.Mix(G.Line2, Accent, 0.7f);
            }
            if (DeleteMode && hover) { line = MarkColor; fill = G.Deco ? G.Mix(G.Panel, MarkColor, 0.25f) : G.Mix(G.Raised, MarkColor, 0.3f); }
            if (Marked) { fill = hover ? G.Mix(MarkColor, Color.White, 0.12f) : MarkColor; line = G.Mix(MarkColor, Color.Black, 0.35f); textCol = Color.White; }
            using (var p = G.Round(r, r.Height / 2))
            {
                using (var b = new SolidBrush(fill)) g.FillPath(b, p);
                using (var pen = new Pen(line, 1f)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Shown, Font, Rectangle.Round(r), textCol,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            // väike joon all: sellel modil pole veel oma pilti (paremklõps -> Picture…)
            if (NoPic)
            {
                float lw = Math.Min(28f, r.Width * 0.3f), ly = r.Bottom - 3f;
                using (var pen = new Pen(Color.FromArgb(150, textCol), 1.6f)) { pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; g.DrawLine(pen, r.Left + (r.Width - lw) / 2, ly, r.Left + (r.Width + lw) / 2, ly); }
            }
            if (!string.IsNullOrEmpty(AltBadge))
            {
                var br = BadgeRect;
                Color bf = AltOn ? (hoverBadge ? G.BrandHover : G.Brand) : (hoverBadge ? G.Hover : G.Raised);
                using (var b = new SolidBrush(bf)) g.FillEllipse(b, br);
                using (var pen = new Pen(AltOn ? G.Bg : (hoverBadge ? G.Brand : G.LineHover), 1.2f)) g.DrawEllipse(pen, br);
                using (var f = new Font("Segoe UI", 7f, FontStyle.Bold))
                    TextRenderer.DrawText(g, AltBadge, f, Rectangle.Round(br), AltOn ? G.Ink : (hoverBadge ? G.Bright : G.Muted),
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            }
            else if (!string.IsNullOrEmpty(Badge))
            {
                var br = BadgeRect;
                using (var b = new SolidBrush(G.Brand)) g.FillEllipse(b, br);
                using (var pen = new Pen(G.Bg, 1.5f)) g.DrawEllipse(pen, br);
                using (var f = new Font("Segoe UI", 7f, FontStyle.Bold))
                    TextRenderer.DrawText(g, Badge, f, Rectangle.Round(br), G.Ink,
                        TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            }
        }
    }

    // Ümmargune "n" nupp (nagu modi nupu nurgas olev "n"): On = n-versioonid sees. Klõps = Click sündmus.
    public class NBadge : Control
    {
        bool hover;
        public bool On;
        public NBadge()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent; Size = new Size(30, 30); Cursor = Cursors.Hand;
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            var br = new RectangleF(2f, 2f, Width - 5f, Height - 5f);
            Color bf = On ? (hover ? G.BrandHover : G.Brand) : (hover ? G.Hover : G.Raised);
            using (var b = new SolidBrush(bf)) g.FillEllipse(b, br);
            using (var pen = new Pen(On ? G.Bg : (hover ? G.Brand : G.LineHover), 1.6f)) g.DrawEllipse(pen, br);
            using (var f = new Font("Segoe UI", 10f, FontStyle.Bold))
                TextRenderer.DrawText(g, "n", f, Rectangle.Round(br), On ? G.Ink : (hover ? G.Bright : G.Muted),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
        }
    }

    // Tavaline nupp (Salvesta, Lülita kõik ...), ümarate nurkadega.
    public class Pill : Control
    {
        bool hover, down;
        public bool Primary;
        public bool Danger;   // punane (kustutamisrežiim)
        public bool Dark;     // tume "Quick Buy" kast (päises ja alumisel ribal)
        public Color Fill = Color.Empty;   // oma värv (valikurežiimi värv); Outline = ainult värviline äär
        public bool Outline;
        public int Radius = 8;
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }

        public Pill()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            Cursor = Cursors.Hand;
        }

        public void FitWidth(int pad, int height)
        {
            Size = new Size(TextRenderer.MeasureText(Text, Font).Width + pad * 2, height);
        }

        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            RectangleF r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            if (down) r.Inflate(-1.2f, -1.2f);
            Color fill, line, text;
            if (Danger) { fill = hover ? G.Hex("#E0412F") : G.Hex("#C42B1C"); line = fill; text = G.Bright; }
            else if (Primary) { fill = hover ? G.BrandHover : G.Brand; line = fill; text = G.Ink; }
            else if (Dark) { fill = hover ? G.DarkHover : G.DarkFill; line = hover ? G.Brand : G.DarkLine; text = hover ? G.HeadBright : G.HeadText; }
            else { fill = hover ? G.Hover : G.Raised; line = hover ? G.LineHover : G.Line2; text = hover ? G.Bright : G.Text; }
            if (!Fill.IsEmpty)
            {
                // valikurežiimi nupud alumisel ribal: režiimi värvi (täidetud või värvilise äärega), et silma paistaks
                if (Outline) { fill = hover ? G.Mix(G.DarkFill, Fill, 0.35f) : G.Mix(G.DarkFill, Fill, 0.18f); line = G.Mix(Fill, Color.White, 0.25f); text = Color.White; }
                else { fill = hover ? G.Mix(Fill, Color.White, 0.15f) : Fill; line = G.Mix(Fill, Color.White, 0.35f); text = Color.White; }
                if (!Enabled) { fill = G.Mix(fill, G.DarkFill, 0.55f); line = G.Mix(line, G.DarkFill, 0.5f); text = G.Mix(text, G.DarkFill, 0.45f); }
            }
            using (var p = G.Round(r, Radius))
            {
                using (var b = new SolidBrush(fill)) g.FillPath(b, p);
                using (var pen = new Pen(line, 1f)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Text, Font, Rectangle.Round(r), text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix);
        }
    }

    // Ümar raam otsingukastile; muutub kollaseks, kui kastis on fookus.
    // Progressiriba (Windowsi roheline asemel): ümar rada, kuldne täide. Value/Maximum nagu ProgressBar.
    public class Bar : Control
    {
        int val, max = 100;
        public int Value { get { return val; } set { val = Math.Max(0, Math.Min(max, value)); Invalidate(); } }
        public int Maximum { get { return max; } set { max = Math.Max(1, value); if (val > max) val = max; Invalidate(); } }
        public Bar()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent; Height = 8;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
            using (var p = G.Round(r, Height / 2f)) using (var b = new SolidBrush(G.Mix(G.Raised, Color.Black, 0.12f))) g.FillPath(b, p);
            float w = (Width - 1) * (float)val / max;
            if (w >= Height)
                using (var p = G.Round(new RectangleF(0.5f, 0.5f, w, Height - 1), Height / 2f))
                using (var b = new LinearGradientBrush(new RectangleF(0, 0, Math.Max(1, w), Height), G.Mix(G.Brand, Color.White, 0.15f), G.Mix(G.Brand, Color.Black, 0.12f), 90f))
                    g.FillPath(b, p);
        }
    }

    // Teatekast akna ülaosas: Kind 0 = töötab (kuld), 1 = korras (roheline), 2 = hoiatus (oranž), 3 = viga (punane)
    public class Banner : Control
    {
        int kind;
        public int Kind { get { return kind; } set { kind = value; Invalidate(); } }
        public Banner()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent; Height = 44;
        }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        Color KindColor { get { return kind == 1 ? G.Hex("#3F8F3A") : kind == 2 ? G.Hex("#C27A1A") : kind == 3 ? G.Hex("#B03A2E") : G.Brand; } }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            Color c = KindColor;
            var r = new RectangleF(0.5f, 0.5f, Width - 1, Height - 1);
            using (var p = G.Round(r, 10))
            {
                using (var b = new SolidBrush(G.Mix(G.Panel, c, 0.16f))) g.FillPath(b, p);
                using (var pen = new Pen(G.Mix(G.Panel, c, 0.7f), 1.2f)) g.DrawPath(pen, p);
            }
            // vasakul värviline ring ikooniga
            float d = Height - 18; var cr = new RectangleF(10, 9, d, d);
            using (var b = new SolidBrush(c)) g.FillEllipse(b, cr);
            string icon = kind == 1 ? "✓" : kind == 2 ? "!" : kind == 3 ? "✕" : "…";
            using (var f = new Font("Segoe UI", d * 0.5f, FontStyle.Bold, GraphicsUnit.Pixel))
                TextRenderer.DrawText(g, icon, f, Rectangle.Round(cr), Color.White, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding);
            var tr = new Rectangle((int)(cr.Right + 10), 2, Width - (int)cr.Right - 18, Height - 4);
            TextRenderer.DrawText(g, Text, Font, tr, G.Bright, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    // Nimekiri teema värvides: päis kaardi tooniga, kõrgemad read (ruumi), ülejäänu joonistab Windows ise.
    public static class ListStyle
    {
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] static extern int SetWindowTheme(IntPtr h, string app, string idList);
        public static void Apply(ListView lv, int rowHeight)
        {
            lv.OwnerDraw = true;
            if (G.Night)   // tumedas teemas ka tume kerimisriba
            {
                EventHandler dark = (s, e) => SetWindowTheme(((Control)s).Handle, "DarkMode_Explorer", null);
                if (lv.IsHandleCreated) dark(lv, EventArgs.Empty); else lv.HandleCreated += dark;
            }
            var il = new ImageList(); il.ImageSize = new Size(1, rowHeight); lv.SmallImageList = il;
            lv.DrawColumnHeader += (s, e) =>
            {
                using (var b = new SolidBrush(G.Mix(G.Raised, Color.Black, 0.06f))) e.Graphics.FillRectangle(b, e.Bounds);
                using (var p = new Pen(G.Line)) { e.Graphics.DrawLine(p, e.Bounds.Left, e.Bounds.Bottom - 1, e.Bounds.Right, e.Bounds.Bottom - 1); e.Graphics.DrawLine(p, e.Bounds.Right - 1, e.Bounds.Top + 5, e.Bounds.Right - 1, e.Bounds.Bottom - 6); }
                var r = e.Bounds; r.Inflate(-6, 0);
                using (var f = new Font(lv.Font, FontStyle.Bold))
                    TextRenderer.DrawText(e.Graphics, e.Header.Text, f, r, G.Bright, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
            };
            lv.DrawItem += (s, e) => { e.DrawDefault = true; };
            lv.DrawSubItem += (s, e) => { e.DrawDefault = true; };
            // rühmade pealkirjad: Windows joonistab need tumesinisena (tumedal taustal ei näe) -> ise
            if (lv.IsHandleCreated) new GroupPainter(lv); else lv.HandleCreated += (s, e) => new GroupPainter((ListView)s);
        }
    }

    // Kuulab ListView NM_CUSTOMDRAW teateid; rühma pealkirja (LVCDI_GROUP) joonistab ise, kontrastse värviga.
    class GroupPainter : NativeWindow
    {
        [StructLayout(LayoutKind.Sequential)] struct NMHDR { public IntPtr hwndFrom; public UIntPtr idFrom; public int code; }
        [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
        [StructLayout(LayoutKind.Sequential)] struct NMLVCUSTOMDRAW
        {
            public NMHDR hdr; public int dwDrawStage; public IntPtr hdc; public RECT rc; public UIntPtr dwItemSpec; public uint uItemState; public IntPtr lItemlParam;
            public uint clrText, clrTextBk; public int iSubItem; public uint dwItemType;
        }
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, ref RECT r);
        static readonly System.Reflection.PropertyInfo IdProp = typeof(ListViewGroup).GetProperty("ID", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        readonly ListView lv;
        public GroupPainter(ListView lv)
        {
            this.lv = lv; AssignHandle(lv.Handle);
            lv.HandleDestroyed += (s, e) => ReleaseHandle();
        }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x204E && m.LParam != IntPtr.Zero)   // WM_REFLECT + WM_NOTIFY
            {
                var h = (NMHDR)Marshal.PtrToStructure(m.LParam, typeof(NMHDR));
                if (h.code == -12)   // NM_CUSTOMDRAW
                {
                    var cd = (NMLVCUSTOMDRAW)Marshal.PtrToStructure(m.LParam, typeof(NMLVCUSTOMDRAW));
                    if (cd.dwItemType == 1 && cd.dwDrawStage == 1)   // LVCDI_GROUP, CDDS_PREPAINT
                    {
                        try { Paint(cd.hdc, (int)cd.dwItemSpec.ToUInt32()); m.Result = (IntPtr)4; return; }   // CDRF_SKIPDEFAULT
                        catch { }
                    }
                }
            }
            base.WndProc(ref m);
        }
        void Paint(IntPtr hdc, int gid)
        {
            string text = null;
            foreach (ListViewGroup g in lv.Groups) { if (IdProp != null && (int)IdProp.GetValue(g, null) == gid) { text = g.Header; break; } }
            if (text == null) throw new InvalidOperationException();
            var r = new RECT { T = 1 };   // LVGGR_HEADER
            SendMessage(lv.Handle, 0x1062, (IntPtr)gid, ref r);   // LVM_GETGROUPRECT
            var rect = Rectangle.FromLTRB(r.L, r.T, r.R, r.B);
            Color bg = lv.BackColor;
            bool dark = bg.GetBrightness() < 0.5f;
            Color fg = dark ? ColorTranslator.FromHtml("#E8C06A") : ColorTranslator.FromHtml("#5A3A0A");
            using (var gr = Graphics.FromHdc(hdc))
            {
                using (var b = new SolidBrush(bg)) gr.FillRectangle(b, rect);
                var tr = new Rectangle(rect.Left + 10, rect.Top, rect.Width - 14, rect.Height);
                using (var f = new Font(lv.Font, FontStyle.Bold))
                {
                    TextRenderer.DrawText(gr, text, f, tr, fg, TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
                    int w = TextRenderer.MeasureText(gr, text, f, tr.Size, TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding).Width;
                    int y = rect.Top + rect.Height / 2, x0 = Math.Min(tr.Left + w + 12, rect.Right);
                    using (var p = new Pen(Color.FromArgb(110, fg))) if (x0 < rect.Right - 10) gr.DrawLine(p, x0, y, rect.Right - 10, y);
                }
            }
        }
    }

    // Failivalija, mis ei lukusta rakendust: oma lõimes, ilma omanikuta (oma nupp tegumiribal), minimeerimise nupuga.
    // Rakendus töötab samal ajal edasi; valija võib kõrvale jääda. Tagastab valitud failid või null.
    public static class FreePicker
    {
        delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] static extern bool EnumThreadWindows(uint tid, EnumProc f, IntPtr l);
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, System.Text.StringBuilder sb, int n);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        public static bool Busy;

        public static string[] Open(string title, string filter, string dir, bool multi)
        {
            if (Busy) return null;
            Busy = true;
            string[] result = null; uint tid = 0;
            var t = new System.Threading.Thread(() =>
            {
                tid = GetCurrentThreadId();
                using (var dlg = new OpenFileDialog())
                {
                    dlg.Title = title; dlg.Filter = filter; dlg.Multiselect = multi;
                    if (!string.IsNullOrEmpty(dir)) dlg.InitialDirectory = dir;
                    if (dlg.ShowDialog() == DialogResult.OK) result = dlg.FileNames;
                }
            });
            t.SetApartmentState(System.Threading.ApartmentState.STA); t.IsBackground = true; t.Start();
            bool styled = false;
            try
            {
                while (t.IsAlive)
                {
                    Application.DoEvents(); System.Threading.Thread.Sleep(15);
                    if (Application.OpenForms.Count == 0) return null;   // rakendus suleti
                    if (!styled && tid != 0)
                    {
                        EnumThreadWindows(tid, (h, l) =>
                        {
                            var sb = new System.Text.StringBuilder(64); GetClassName(h, sb, 64);
                            if (sb.ToString() == "#32770" && IsWindowVisible(h))
                            {
                                SetWindowLong(h, -16, GetWindowLong(h, -16) | 0x00020000 | 0x00080000);   // WS_MINIMIZEBOX | WS_SYSMENU
                                SetWindowLong(h, -20, GetWindowLong(h, -20) | 0x00040000);                // WS_EX_APPWINDOW: oma nupp tegumiribal
                                ShowWindow(h, 0); ShowWindow(h, 5);                                        // tegumiriba märkab muutust
                                SetWindowPos(h, IntPtr.Zero, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0004 | 0x0020);   // NOSIZE|NOMOVE|NOZORDER|FRAMECHANGED
                                styled = true;
                            }
                            return true;
                        }, IntPtr.Zero);
                    }
                }
                return result;
            }
            finally { Busy = false; }
        }
    }

    // Lõpu teade: heli + tegumiriba vilkumine, kui rakendus pole ees (nt minimeeritud)
    public static class Notify
    {
        [StructLayout(LayoutKind.Sequential)] struct FLASHWINFO { public uint cbSize; public IntPtr hwnd; public uint dwFlags; public uint uCount; public uint dwTimeout; }
        [DllImport("user32.dll")] static extern bool FlashWindowEx(ref FLASHWINFO f);
        public static void Done(Form f, bool problems)
        {
            try { if (problems) System.Media.SystemSounds.Exclamation.Play(); else System.Media.SystemSounds.Asterisk.Play(); } catch { }
            if (f == null || !f.IsHandleCreated) return;
            if (Form.ActiveForm == null || f.WindowState == FormWindowState.Minimized)
            {
                var w = new FLASHWINFO(); w.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO)); w.hwnd = f.Handle;
                w.dwFlags = 3 | 12; w.uCount = 0; w.dwTimeout = 0;   // pealkiri + tegumiriba, kuni aken ette tuuakse
                FlashWindowEx(ref w);
            }
        }
    }

    // Akna lohistamine / suuruse muutmine: kaartide WS_EX_COMPOSITED sunnib iga liigutuse ajal kogu akent
    // uuesti joonistama ja aken "lohiseb" kursorile järele. Liigutamise ajaks lülitatakse see välja.
    public class MoveWatcher : NativeWindow
    {
        [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int i, int v);
        public static int Moves;
        public static void Attach(Form f) { var w = new MoveWatcher(); w.AssignHandle(f.Handle); f.HandleDestroyed += (s, e) => w.ReleaseHandle(); }
        public static void SetComposited(bool on)
        {
            foreach (var c in Card.All)
            {
                if (c.IsDisposed || !c.IsHandleCreated) continue;
                int ex = GetWindowLong(c.Handle, -20);
                int nx = on ? (ex | 0x02000000) : (ex & ~0x02000000);
                if (nx != ex) SetWindowLong(c.Handle, -20, nx);
            }
        }
        // Mõõtmine: lohistamise ajal WM_MOVING teadete vahed (kui suured -> rakendus on vahepeal kinni) -> %TEMP%\dlmods_move.log
        static System.Diagnostics.Stopwatch sw = new System.Diagnostics.Stopwatch();
        static double lastMs, maxGap, sumGap; static int nMoving, slow;
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x231)        // WM_ENTERSIZEMOVE
            {
                Moves++; SetComposited(false);
                sw.Restart(); lastMs = 0; maxGap = 0; sumGap = 0; nMoving = 0; slow = 0; Perf.Reset();
            }
            else if (m.Msg == 0x216 || m.Msg == 0x214)   // WM_MOVING / WM_SIZING
            {
                double t = sw.Elapsed.TotalMilliseconds, gap = t - lastMs; lastMs = t;
                if (nMoving > 0) { sumGap += gap; if (gap > maxGap) maxGap = gap; if (gap > 33) slow++; }
                nMoving++;
            }
            else if (m.Msg == 0x232)   // WM_EXITSIZEMOVE
            {
                SetComposited(Card.CompositedCards);
                try
                {
                    string line = string.Format("{0:HH:mm:ss} drag {1:0} ms: {2} moves, avg gap {3:0.0} ms, max gap {4:0.0} ms, gaps>33ms: {5}; timers: {6}{7}",
                        DateTime.Now, sw.Elapsed.TotalMilliseconds, nMoving, nMoving > 1 ? sumGap / (nMoving - 1) : 0, maxGap, slow, Perf.Report(), Environment.NewLine);
                    System.IO.File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "dlmods_move.log"), line);
                }
                catch { }
            }
            base.WndProc(ref m);
        }
    }

    // Automaatne kärbe: kus pildil on "tegelane"? Väikesel koopial detailsus (servad) + värvikus; aken (kaardi kujuga)
    // pannakse kohta, kus seda on kõige rohkem (kerge eelistus keskele ja ülemisele osale - nägu).
    // Tagastab kärpe keskpunkti 0..1 pildi laiuse/kõrguse suhtes.
    public static class AutoCrop
    {
        public static PointF Find(Image src, float aspect, float zoom)
        {
            int W = 96, H = Math.Max(8, (int)Math.Round(src.Height * 96.0 / src.Width));
            var e = new double[W, H];
            using (var b = new Bitmap(W, H))
            {
                using (var g = Graphics.FromImage(b)) { g.InterpolationMode = InterpolationMode.HighQualityBilinear; g.DrawImage(src, 0, 0, W, H); }
                var lum = new double[W, H]; var sat = new double[W, H];
                for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
                {
                    var c = b.GetPixel(x, y);
                    lum[x, y] = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B;
                    int mx = Math.Max(c.R, Math.Max(c.G, c.B)), mn = Math.Min(c.R, Math.Min(c.G, c.B));
                    sat[x, y] = mx == 0 ? 0 : (mx - mn) * 255.0 / mx;
                }
                for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++)
                    e[x, y] = Math.Abs(lum[x + 1, y] - lum[x - 1, y]) + Math.Abs(lum[x, y + 1] - lum[x, y - 1]) + 0.35 * sat[x, y];
            }
            // integraalpilt
            var I = new double[W + 1, H + 1];
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) I[x + 1, y + 1] = e[x, y] + I[x, y + 1] + I[x + 1, y] - I[x, y];
            double cw, ch;
            if ((double)W / H > aspect) { ch = H; cw = H * aspect; } else { cw = W; ch = W / aspect; }
            cw /= Math.Max(1, zoom); ch /= Math.Max(1, zoom);
            int iw = Math.Max(1, (int)cw), ih = Math.Max(1, (int)ch);
            double best = double.MinValue; int bx = (W - iw) / 2, by = (H - ih) / 2;
            double total = I[W, H] + 1;
            for (int y = 0; y + ih <= H; y++) for (int x = 0; x + iw <= W; x++)
            {
                double s = (I[x + iw, y + ih] - I[x, y + ih] - I[x + iw, y] + I[x, y]) / total;
                double dx = (x + iw / 2.0) / W - 0.5, dy = (y + ih / 2.0) / H - 0.42;
                s -= 0.08 * Math.Abs(dx) + 0.05 * Math.Abs(dy);
                if (s > best) { best = s; bx = x; by = y; }
            }
            return new PointF((float)((bx + iw / 2.0) / W), (float)((by + ih / 2.0) / H));
        }
    }

    // Mõõtmine (testideks): taimerite kestus. Perf.Report() -> "nimi: n korda, kokku ms, max ms"
    public static class Perf
    {
        static readonly Dictionary<string, double[]> d = new Dictionary<string, double[]>();
        public static void Add(string k, System.Diagnostics.Stopwatch w)
        {
            double ms = w.Elapsed.TotalMilliseconds; double[] v;
            if (!d.TryGetValue(k, out v)) { v = new double[3]; d[k] = v; }
            v[0]++; v[1] += ms; if (ms > v[2]) v[2] = ms;
        }
        public static void Reset() { d.Clear(); }
        public static string Report() { var sb = new System.Text.StringBuilder(); foreach (var kv in d) sb.AppendFormat("{0}: {1} x, total {2:0.0} ms, max {3:0.0} ms; ", kv.Key, kv.Value[0], kv.Value[1], kv.Value[2]); return sb.ToString(); }
    }

    public class Frame : Panel
    {
        public bool Focused2;
        public Frame()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true);
            BackColor = G.Deco ? Color.Transparent : G.Bg;   // Deadlocki teemas paistab päise tekstuur nurkades
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var p = G.Round(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 8))
            {
                using (var b = new SolidBrush(G.SearchFill)) g.FillPath(b, p);
                using (var pen = new Pen(Focused2 ? G.Brand : (G.Deco ? G.DarkLine : G.Line2), 1f)) g.DrawPath(pen, p);
            }
        }
    }
}

// Windowsi funktsioonid rakenduse skriptidele (enne eraldi Add-Type: iga käivitus kompileeris selle uuesti)
namespace DlToggle
{
    public static class Native
    {
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string idList);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
        [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
        // mitu ms pole hiirt ega klaviatuuri liigutatud (taustal ehitamine ainult siis, kui kasutaja ei tee midagi)
        public static int IdleMs()
        {
            var i = new LASTINPUTINFO(); i.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref i)) return 0;
            return (int)((uint)Environment.TickCount - i.dwTime);
        }
    }
}
