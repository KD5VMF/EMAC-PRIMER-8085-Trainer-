using System;
using System.Drawing;
using System.IO;
using System.IO.Ports;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace EmacRtcSyncGUI;

public sealed class MainForm : Form
{
    private const int MaxSendAttempts = 5;
    private const int PacedCharGapMs = 8;
    private const int IdleQuietMs = 160;
    private const int IdleMaxWaitMs = 1800;
    private const int FallbackQuietWindowStartMs = 650;
    private const int FallbackQuietWindowLastStartMs = 820;

    private readonly ComboBox cboPort = new();
    private readonly TextBox txtBaud = new();
    private readonly TextBox txtTimeout = new();
    private readonly TextBox txtRepeat = new();
    private readonly CheckBox chkUtc = new();
    private readonly CheckBox chkAlign = new();
    private readonly CheckBox chkDtr = new();
    private readonly CheckBox chkRts = new();
    private readonly ComboBox cboEnding = new();
    private readonly Label lblPreview = new();
    private readonly Label lblStatus = new();
    private readonly TextBox txtLog = new();
    private readonly Button btnSave = new();
    private readonly Button btnSend = new();
    private readonly Button btnRepeat = new();
    private readonly Button btnClear = new();
    private readonly System.Windows.Forms.Timer repeatTimer = new();
    private readonly System.Windows.Forms.Timer previewTimer = new();

    private bool repeating = false;
    private bool busySending = false;
    private SerialPort? openSerial = null;

    private static readonly string SettingsDir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "EmacRtcSyncGUI");

    private static readonly string SettingsFile = Path.Combine(SettingsDir, "settings.json");

    public MainForm()
    {
        Text = "EMAC RTC Sync";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1040, 650);
        Size = new Size(1220, 760);
        BackColor = Color.FromArgb(13, 18, 26);
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 10F, FontStyle.Regular);

        txtBaud.Text = "9600";
        txtTimeout.Text = "1.0";
        txtRepeat.Text = "60";
        chkAlign.Checked = true;
        chkDtr.Checked = true;
        chkRts.Checked = true;
        cboEnding.Items.AddRange(new object[] { "CR", "CRLF", "LF" });
        cboEnding.SelectedItem = "CR";

        BuildUi();
        WireEvents();
        RefreshPorts(false);
        LoadSettings();
        UpdatePreview();

        previewTimer.Interval = 500;
        previewTimer.Tick += (_, _) => UpdatePreview();
        previewTimer.Start();
    }

    private void BuildUi()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            Padding = new Padding(16),
            BackColor = Color.FromArgb(13, 18, 26)
        };

        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 52));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 166));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 96));
        root.RowStyles.Add(new RowStyle(SizeType.Absolute, 58));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        Controls.Add(root);

        var title = new Label
        {
            Text = "EMAC RTC Sync",
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleCenter,
            ForeColor = Color.FromArgb(105, 220, 255),
            Font = new Font("Segoe UI", 18F, FontStyle.Bold)
        };
        root.Controls.Add(title, 0, 0);

        var topBox = new GroupBox
        {
            Text = "Settings",
            ForeColor = Color.White,
            Dock = DockStyle.Fill,
            Padding = new Padding(16, 24, 16, 12)
        };
        root.Controls.Add(topBox, 0, 1);

        var settings = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 10,
            RowCount = 3,
            Padding = new Padding(2),
            GrowStyle = TableLayoutPanelGrowStyle.FixedSize
        };

        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150)); // COM
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100)); // baud
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 100)); // ending
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105)); // timeout
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 105)); // repeat
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145)); // safe timing
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145)); // utc
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));  // dtr
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 78));  // rts
        settings.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));  // save / filler
        settings.RowStyles.Add(new RowStyle(SizeType.Absolute, 28));
        settings.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
        settings.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        topBox.Controls.Add(settings);

        cboPort.DropDownStyle = ComboBoxStyle.DropDownList;
        cboEnding.DropDownStyle = ComboBoxStyle.DropDownList;
        AddField(settings, "COM Port", cboPort, 0);
        AddField(settings, "Baud", txtBaud, 1);
        AddField(settings, "Ending", cboEnding, 2);
        AddField(settings, "Timeout", txtTimeout, 3);
        AddField(settings, "Repeat", txtRepeat, 4);

        PrepareCheck(chkAlign, "ON");
        AddField(settings, "Safe Timing", chkAlign, 5);

        PrepareCheck(chkUtc, "UTC");
        AddField(settings, "Time Mode", chkUtc, 6);

        PrepareCheck(chkDtr, "ON");
        AddField(settings, "DTR", chkDtr, 7);

        PrepareCheck(chkRts, "ON");
        AddField(settings, "RTS", chkRts, 8);

        StyleButton(btnSave, "Save + Connect", Color.FromArgb(30, 105, 140), 150);
        btnSave.Dock = DockStyle.Top;
        btnSave.Height = 34;
        btnSave.Margin = new Padding(8, 0, 0, 4);
        settings.Controls.Add(MakeHeader(""), 9, 0);
        settings.Controls.Add(btnSave, 9, 1);

        var note = new Label
        {
            Text = "Recommended: COM6, 9600, CR, DTR ON, RTS ON, LOCAL time. Safe Timing waits for the 8085 screen update to finish, then sends the short sync frame while the 8085 is idle.",
            Dock = DockStyle.Fill,
            ForeColor = Color.FromArgb(185, 205, 225),
            TextAlign = ContentAlignment.MiddleLeft,
            AutoEllipsis = true,
            Margin = new Padding(0, 8, 0, 0)
        };
        settings.Controls.Add(note, 0, 2);
        settings.SetColumnSpan(note, 10);

        var previewBox = new GroupBox
        {
            Text = "Command Preview",
            ForeColor = Color.White,
            Dock = DockStyle.Fill,
            Padding = new Padding(16, 18, 16, 10)
        };
        root.Controls.Add(previewBox, 0, 2);

        var previewLayout = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            RowCount = 2,
            ColumnCount = 1
        };
        previewLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 58));
        previewLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 42));
        previewBox.Controls.Add(previewLayout);

        lblPreview.Dock = DockStyle.Fill;
        lblPreview.Font = new Font("Consolas", 14F, FontStyle.Bold);
        lblPreview.ForeColor = Color.FromArgb(255, 230, 70);
        lblPreview.TextAlign = ContentAlignment.MiddleLeft;
        previewLayout.Controls.Add(lblPreview, 0, 0);

        lblStatus.Text = "Ready.";
        lblStatus.Dock = DockStyle.Fill;
        lblStatus.Font = new Font("Consolas", 10F, FontStyle.Bold);
        lblStatus.ForeColor = Color.FromArgb(120, 255, 170);
        lblStatus.TextAlign = ContentAlignment.MiddleLeft;
        previewLayout.Controls.Add(lblStatus, 0, 1);

        var buttonRow = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 5, 0, 0),
            BackColor = Color.FromArgb(13, 18, 26)
        };
        root.Controls.Add(buttonRow, 0, 3);

        StyleButton(btnSend, "Send Once", Color.FromArgb(25, 135, 90), 180);
        StyleButton(btnRepeat, "Start Repeating", Color.FromArgb(170, 95, 15), 205);
        StyleButton(btnClear, "Clear Log", Color.FromArgb(70, 82, 100), 160);
        buttonRow.Controls.Add(btnSend);
        buttonRow.Controls.Add(btnRepeat);
        buttonRow.Controls.Add(btnClear);

        txtLog.Dock = DockStyle.Fill;
        txtLog.Multiline = true;
        txtLog.ScrollBars = ScrollBars.Vertical;
        txtLog.ReadOnly = true;
        txtLog.BackColor = Color.Black;
        txtLog.ForeColor = Color.White;
        txtLog.Font = new Font("Consolas", 10F);
        txtLog.Margin = new Padding(0);
        txtLog.WordWrap = false;
        root.Controls.Add(txtLog, 0, 4);
    }

    private static Label MakeHeader(string text) => new()
    {
        Text = text,
        Dock = DockStyle.Fill,
        ForeColor = Color.White,
        TextAlign = ContentAlignment.BottomLeft,
        AutoEllipsis = true,
        Margin = new Padding(0, 0, 12, 0)
    };

    private static void AddField(TableLayoutPanel parent, string label, Control control, int column)
    {
        parent.Controls.Add(MakeHeader(label), column, 0);
        control.Dock = DockStyle.Fill;
        control.Margin = new Padding(0, 0, 12, 4);
        parent.Controls.Add(control, column, 1);
    }

    private static void PrepareCheck(CheckBox c, string text)
    {
        c.Text = text;
        c.Dock = DockStyle.Fill;
        c.AutoSize = false;
        c.TextAlign = ContentAlignment.MiddleLeft;
        c.ForeColor = Color.White;
        c.BackColor = Color.FromArgb(13, 18, 26);
    }

    private static void StyleButton(Button b, string text, Color color, int width)
    {
        b.Text = text;
        b.Width = width;
        b.Height = 46;
        b.Margin = new Padding(0, 0, 12, 0);
        b.BackColor = color;
        b.ForeColor = Color.White;
        b.Font = new Font("Segoe UI", 10F, FontStyle.Bold);
        b.FlatStyle = FlatStyle.Flat;
        b.FlatAppearance.BorderColor = Color.FromArgb(210, 225, 240);
        b.FlatAppearance.BorderSize = 1;
    }

    private void WireEvents()
    {
        btnSave.Click += (_, _) => SaveSettings();
        btnSend.Click += async (_, _) => await SendOnceAsync();
        btnRepeat.Click += (_, _) => ToggleRepeat();
        btnClear.Click += (_, _) => txtLog.Clear();

        txtBaud.TextChanged += (_, _) => UpdatePreview();
        txtTimeout.TextChanged += (_, _) => UpdatePreview();
        txtRepeat.TextChanged += (_, _) => UpdatePreview();
        chkUtc.CheckedChanged += (_, _) => UpdatePreview();
        chkAlign.CheckedChanged += (_, _) => UpdatePreview();
        chkDtr.CheckedChanged += (_, _) => CloseOpenSerial();
        chkRts.CheckedChanged += (_, _) => CloseOpenSerial();
        cboEnding.SelectedIndexChanged += (_, _) => UpdatePreview();

        repeatTimer.Tick += async (_, _) => await SendOnceAsync();
        FormClosing += (_, _) =>
        {
            previewTimer.Stop();
            repeatTimer.Stop();
            CloseOpenSerial();
        };
    }

    private void RefreshPorts(bool log)
    {
        string? old = cboPort.SelectedItem as string;
        cboPort.Items.Clear();

        foreach (var p in SerialPort.GetPortNames().OrderBy(NaturalComOrderKey))
            cboPort.Items.Add(p);

        if (old != null && cboPort.Items.Contains(old))
            cboPort.SelectedItem = old;
        else if (cboPort.Items.Count > 0)
            cboPort.SelectedIndex = 0;

        if (log)
            Log($"Found {cboPort.Items.Count} COM port(s). Selected {(cboPort.SelectedItem as string ?? "none")}.");
    }

    private static string NaturalComOrderKey(string s)
    {
        var m = Regex.Match(s, @"^(COM)(\d+)$", RegexOptions.IgnoreCase);
        if (m.Success && int.TryParse(m.Groups[2].Value, out int n))
            return $"COM{n:00000}";
        return s;
    }

    private void CloseOpenSerial()
    {
        try
        {
            if (openSerial != null)
            {
                if (openSerial.IsOpen)
                    openSerial.Close();
                openSerial.Dispose();
                openSerial = null;
            }
        }
        catch
        {
            openSerial = null;
        }
    }

    private SerialPort GetOrOpenSerial(string port, int baud, double timeoutSec)
    {
        int timeoutMs = Math.Max(100, (int)(timeoutSec * 1000));

        if (openSerial != null &&
            openSerial.IsOpen &&
            openSerial.PortName.Equals(port, StringComparison.OrdinalIgnoreCase) &&
            openSerial.BaudRate == baud &&
            openSerial.DtrEnable == chkDtr.Checked &&
            openSerial.RtsEnable == chkRts.Checked)
        {
            openSerial.ReadTimeout = timeoutMs;
            openSerial.WriteTimeout = timeoutMs;
            return openSerial;
        }

        CloseOpenSerial();

        openSerial = new SerialPort(port, baud, Parity.None, 8, StopBits.One)
        {
            ReadTimeout = timeoutMs,
            WriteTimeout = timeoutMs,
            Encoding = Encoding.ASCII,
            NewLine = "\n",
            Handshake = Handshake.None,
            DtrEnable = chkDtr.Checked,
            RtsEnable = chkRts.Checked
        };

        openSerial.Open();
        Log($"SERIAL: Opened {port} at {baud} baud. DTR={(chkDtr.Checked ? "ON" : "OFF")}, RTS={(chkRts.Checked ? "ON" : "OFF")}. Keeping it open.");
        return openSerial;
    }

    private void SaveSettings()
    {
        RefreshPorts(false);
        Directory.CreateDirectory(SettingsDir);

        var data = new AppSettings
        {
            Port = cboPort.SelectedItem as string ?? "",
            Baud = txtBaud.Text.Trim(),
            Timeout = txtTimeout.Text.Trim(),
            Repeat = txtRepeat.Text.Trim(),
            Utc = chkUtc.Checked,
            Align = chkAlign.Checked,
            Dtr = chkDtr.Checked,
            Rts = chkRts.Checked,
            Ending = cboEnding.SelectedItem as string ?? "CR"
        };

        File.WriteAllText(SettingsFile, JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
        Log("Settings saved to Documents\\EmacRtcSyncGUI\\settings.json");
        Log("Safety: UTC is saved in the file, but startup always comes up LOCAL unless you check UTC again.");
        TryOpenSerialAfterSave();
    }

    private void TryOpenSerialAfterSave()
    {
        try
        {
            RefreshPorts(false);

            if (cboPort.SelectedItem is not string port || string.IsNullOrWhiteSpace(port))
            {
                SetStatus("Saved, but no COM port is selected.", true);
                Log("CONNECT: Settings saved, but no COM port is selected.");
                return;
            }

            if (!int.TryParse(txtBaud.Text.Trim(), out int baud) || baud <= 0)
            {
                SetStatus("Saved, but baud is bad.", true);
                Log("CONNECT ERROR: Baud must be a number, for example 9600.");
                return;
            }

            if (!double.TryParse(txtTimeout.Text.Trim(), out double timeoutSec) || timeoutSec <= 0)
            {
                SetStatus("Saved, but timeout is bad.", true);
                Log("CONNECT ERROR: Timeout must be a number, for example 1.0.");
                return;
            }

            SerialPort ser = GetOrOpenSerial(port, baud, timeoutSec);

            try
            {
                ser.DiscardOutBuffer();
                string drained = ser.ReadExisting();
                if (!string.IsNullOrWhiteSpace(drained))
                    Log("CONNECT DRAINED: " + Shorten(CleanSerialText(drained), 160));
            }
            catch
            {
                // Some USB serial drivers do not like buffer discard calls. The port is still usable.
            }

            SetStatus($"Saved + connected to {port}. Ready.", false);
            Log($"READY: Serial is open on {port}. Sends will reuse this open connection.");
        }
        catch (Exception ex)
        {
            CloseOpenSerial();
            SetStatus("Saved, but serial connect failed.", true);
            Log("CONNECT ERROR: " + ex.Message);
        }
    }

    private void LoadSettings()
    {
        try
        {
            if (!File.Exists(SettingsFile))
            {
                Log($"Found {cboPort.Items.Count} COM port(s). Selected {(cboPort.SelectedItem as string ?? "none")}.");
                return;
            }

            var data = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsFile));
            if (data == null)
                return;

            txtBaud.Text = string.IsNullOrWhiteSpace(data.Baud) ? "9600" : data.Baud;
            txtTimeout.Text = string.IsNullOrWhiteSpace(data.Timeout) ? "1.0" : data.Timeout;
            txtRepeat.Text = string.IsNullOrWhiteSpace(data.Repeat) ? "60" : data.Repeat;

            // Safe default: local time on every startup. You can still check UTC manually for a UTC send.
            chkUtc.Checked = false;
            chkAlign.Checked = data.Align;
            chkDtr.Checked = data.Dtr;
            chkRts.Checked = data.Rts;

            if (!string.IsNullOrWhiteSpace(data.Ending) && cboEnding.Items.Contains(data.Ending))
                cboEnding.SelectedItem = data.Ending;

            if (!string.IsNullOrWhiteSpace(data.Port) && cboPort.Items.Contains(data.Port))
                cboPort.SelectedItem = data.Port;

            Log($"Loaded saved settings. Selected {(cboPort.SelectedItem as string ?? "none")}.");
        }
        catch (Exception ex)
        {
            Log("Could not load settings: " + ex.Message);
        }
    }

    private static int Dow1Sun7Sat(DateTime t) => ((int)t.DayOfWeek) + 1;

    private string BuildCommand(DateTime t)
    {
        int yy = t.Year % 100;
        int w = Dow1Sun7Sat(t);
        return $"!U{yy:00}{t.Month:00}{t.Day:00}{w}{t.Hour:00}{t.Minute:00}{t.Second:00}" + GetLineEnding();
    }

    private string GetLineEnding()
    {
        string ending = cboEnding.SelectedItem as string ?? "CR";
        return ending switch
        {
            "CRLF" => "\r\n",
            "LF" => "\n",
            _ => "\r"
        };
    }

    private string EndingDisplay()
    {
        string ending = cboEnding.SelectedItem as string ?? "CR";
        return ending switch
        {
            "CRLF" => "<CR><LF>",
            "LF" => "<LF>",
            _ => "<CR>"
        };
    }

    private void UpdatePreview()
    {
        DateTime t = chkUtc.Checked ? DateTime.UtcNow : DateTime.Now;
        string cmd = BuildCommand(t);
        lblPreview.Text = cmd.TrimEnd('\r', '\n') + EndingDisplay() + (chkUtc.Checked ? "   UTC" : "   LOCAL");
    }

    private static async Task WaitForFallbackQuietPartOfSecondAsync()
    {
        int ms = DateTime.Now.Millisecond;
        int waitMs;

        if (ms < FallbackQuietWindowStartMs)
            waitMs = FallbackQuietWindowStartMs - ms;
        else if (ms > FallbackQuietWindowLastStartMs)
            waitMs = 1000 - ms + FallbackQuietWindowStartMs;
        else
            waitMs = 0;

        if (waitMs > 0)
            await Task.Delay(waitMs);
    }

    private static async Task<string> WaitFor8085IdleAsync(SerialPort ser)
    {
        // The 8085 program prints a live terminal update once per second.
        // While it is printing, it is not polling RX.  This waits for that
        // print burst to finish, then returns during the quiet part.
        var seen = new StringBuilder();
        bool sawTraffic = false;
        DateTime start = DateTime.UtcNow;
        DateTime lastRx = start;

        while ((DateTime.UtcNow - start).TotalMilliseconds < IdleMaxWaitMs)
        {
            try
            {
                string chunk = ser.ReadExisting();
                if (!string.IsNullOrEmpty(chunk))
                {
                    sawTraffic = true;
                    lastRx = DateTime.UtcNow;
                    if (seen.Length < 600)
                        seen.Append(chunk);
                }
            }
            catch
            {
                break;
            }

            if (sawTraffic && (DateTime.UtcNow - lastRx).TotalMilliseconds >= IdleQuietMs)
                return seen.ToString();

            await Task.Delay(12);
        }

        // Fallback if no screen burst was seen.  This still avoids the usual
        // top-of-second terminal redraw window.
        await WaitForFallbackQuietPartOfSecondAsync();
        return seen.ToString();
    }

    private static async Task WritePacedAsync(SerialPort ser, string text)
    {
        foreach (char ch in text)
        {
            ser.Write(new[] { ch }, 0, 1);
            await Task.Delay(PacedCharGapMs);
        }

        ser.BaseStream.Flush();
    }

    private async Task SendOnceAsync()
    {
        if (busySending)
        {
            Log("Skipped send: previous send still waiting.");
            return;
        }

        busySending = true;
        try
        {
            RefreshPorts(false);

            if (cboPort.SelectedItem is not string port || string.IsNullOrWhiteSpace(port))
            {
                SetStatus("No COM port selected.", true);
                Log("ERROR: No COM port selected.");
                return;
            }

            if (!int.TryParse(txtBaud.Text.Trim(), out int baud) || baud <= 0)
            {
                SetStatus("Bad baud rate.", true);
                Log("ERROR: Baud must be a number, for example 9600.");
                return;
            }

            if (!double.TryParse(txtTimeout.Text.Trim(), out double timeoutSec) || timeoutSec <= 0)
            {
                SetStatus("Bad timeout.", true);
                Log("ERROR: Timeout must be a number, for example 1.0.");
                return;
            }

            var ser = GetOrOpenSerial(port, baud, timeoutSec);
            await Task.Delay(80);

            for (int attempt = 1; attempt <= MaxSendAttempts; attempt++)
            {
                string idleDrain = "";
                if (chkAlign.Checked)
                {
                    idleDrain = await WaitFor8085IdleAsync(ser);
                    if (attempt == 1 && !string.IsNullOrWhiteSpace(idleDrain))
                        Log("IDLE LOCK: 8085 screen update finished. Sending while parser is quiet.");
                }

                DateTime t = chkUtc.Checked ? DateTime.UtcNow : DateTime.Now;
                string cmd = BuildCommand(t);
                string txText = cmd.TrimEnd('\r', '\n');
                UpdatePreview();

                string drained = ser.ReadExisting();
                if (attempt == 1)
                {
                    string allDrain = (idleDrain ?? "") + drained;
                    if (!string.IsNullOrWhiteSpace(allDrain))
                        Log("DRAINED: " + Shorten(CleanSerialText(allDrain), 140));
                }

                Log($"TX attempt {attempt}/{MaxSendAttempts}: " + txText + EndingDisplay());
                Log("TX DECODE: " + DecodeCommand(txText) + (chkUtc.Checked ? "  [UTC MODE]" : "  [LOCAL MODE]"));

                if (chkUtc.Checked)
                    Log("UTC NOTICE: Sending UTC time because UTC mode is checked. Uncheck UTC mode for normal local clock sync.");

                await WritePacedAsync(ser, cmd);

                int responseWindow = Math.Max(900, (int)(timeoutSec * 1000));
                string raw = ReadAllForWindow(ser, responseWindow);
                string clean = CleanSerialText(raw);
                string result = ExtractOkErr(clean);

                if (result == "OK")
                {
                    Log("RX: OK");
                    SetStatus($"OK received on attempt {attempt}.", false);
                    return;
                }

                if (result == "ERR")
                {
                    Log("RX: ERR");
                    if (attempt < MaxSendAttempts)
                    {
                        Log("Retrying after ERR. Idle-lock and paced send stay enabled.");
                        await Task.Delay(350);
                        continue;
                    }

                    Log("ERR DETAIL: The 8085 rejected the command after retries.");
                    Log("ERR HELP: Use LOCAL time, 9600 baud, CR ending, DTR ON, RTS ON.");
                    Log("RX CLEAN: " + (string.IsNullOrWhiteSpace(clean) ? "(empty)" : Shorten(clean, 220)));
                    Log("RX HEX: " + ToHex(raw, 160));
                    SetStatus("ERR received from 8085.", true);
                    return;
                }

                if (attempt < MaxSendAttempts)
                {
                    Log(string.IsNullOrWhiteSpace(clean)
                        ? "RX: no OK/ERR yet. Retrying."
                        : "RX noise/no ACK: " + Shorten(clean, 140));
                    await Task.Delay(350);
                    continue;
                }

                if (string.IsNullOrWhiteSpace(clean))
                {
                    Log("RX: (no response after retries)");
                    SetStatus("No response after retries.", true);
                }
                else
                {
                    Log("RX SCREEN/NOISE: " + Shorten(clean, 220));
                    Log("NO ACK: I did not see OK or ERR after paced attempts.");
                    Log("CHECK: Make sure the 8085 is running the live clock screen, not sitting in the manual SET prompt, and keep Ending=CR.");
                    SetStatus("No OK/ERR after retries.", true);
                }
            }
        }
        catch (Exception ex)
        {
            SetStatus("Serial error.", true);
            Log("ERROR: " + ex.Message);
        }
        finally
        {
            busySending = false;
        }
    }

    private static string ReadAllForWindow(SerialPort ser, int totalMs)
    {
        var sb = new StringBuilder();
        var deadline = DateTime.UtcNow.AddMilliseconds(totalMs);

        while (DateTime.UtcNow < deadline)
        {
            try
            {
                string chunk = ser.ReadExisting();
                if (!string.IsNullOrEmpty(chunk))
                {
                    sb.Append(chunk);
                    string cleaned = CleanSerialText(sb.ToString());
                    string result = ExtractOkErr(cleaned);
                    if (result == "OK" || result == "ERR")
                        break;
                }
            }
            catch
            {
                break;
            }

            System.Threading.Thread.Sleep(30);
        }

        return sb.ToString();
    }

    private static string CleanSerialText(string s)
    {
        if (string.IsNullOrEmpty(s))
            return "";

        s = Regex.Replace(s, @"\x1B\[[0-9;?]*[A-Za-z]", " ");

        var sb = new StringBuilder();

        foreach (char c in s)
        {
            if (c == '\r' || c == '\n' || c == '\t')
                sb.Append(' ');
            else if (c >= 32 && c <= 126)
                sb.Append(c);
        }

        return string.Join(" ", sb.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries));
    }

    private static string ExtractOkErr(string s)
    {
        if (string.IsNullOrWhiteSpace(s))
            return "";

        var parts = s.Split(new[] { ' ', '\r', '\n', '\t', ':', ';', '[', ']', '|', '<', '>', '.', ',', '_', '-' },
            StringSplitOptions.RemoveEmptyEntries);

        foreach (var p in parts)
        {
            if (p.Equals("OK", StringComparison.OrdinalIgnoreCase))
                return "OK";
            if (p.Equals("ERR", StringComparison.OrdinalIgnoreCase))
                return "ERR";
        }

        if (Regex.IsMatch(s, @"(^|[^A-Z])OK([^A-Z]|$)", RegexOptions.IgnoreCase))
            return "OK";
        if (Regex.IsMatch(s, @"(^|[^A-Z])ERR([^A-Z]|$)", RegexOptions.IgnoreCase))
            return "ERR";

        return "";
    }

    private static string DecodeCommand(string tx)
    {
        try
        {
            if (tx.Length != 15 || !tx.StartsWith("!U"))
                return "BAD COMMAND FORMAT";

            string yy = tx.Substring(2, 2);
            string mo = tx.Substring(4, 2);
            string dd = tx.Substring(6, 2);
            string w = tx.Substring(8, 1);
            string hh = tx.Substring(9, 2);
            string mm = tx.Substring(11, 2);
            string ss = tx.Substring(13, 2);

            return $"20{yy}-{mo}-{dd}, W={w} (1=Sun), {hh}:{mm}:{ss}";
        }
        catch
        {
            return "Could not decode TX command.";
        }
    }

    private static string ToHex(string s, int maxBytes)
    {
        if (string.IsNullOrEmpty(s))
            return "(empty)";

        var bytes = Encoding.ASCII.GetBytes(s);
        int take = Math.Min(bytes.Length, maxBytes);
        var sb = new StringBuilder();

        for (int i = 0; i < take; i++)
        {
            if (i > 0) sb.Append(' ');
            sb.Append(bytes[i].ToString("X2"));
        }

        if (bytes.Length > take)
            sb.Append(" ...");

        return sb.ToString();
    }

    private static string Shorten(string s, int max)
    {
        if (s.Length <= max)
            return s;
        return s.Substring(0, max) + "...";
    }

    private void ToggleRepeat()
    {
        if (!repeating)
        {
            if (!double.TryParse(txtRepeat.Text.Trim(), out double repeatSec) || repeatSec <= 0)
            {
                SetStatus("Bad repeat time.", true);
                Log("ERROR: Repeat must be a number, for example 60.");
                return;
            }

            repeatTimer.Interval = Math.Max(1000, (int)(repeatSec * 1000));
            repeatTimer.Start();
            repeating = true;
            btnRepeat.Text = "Stop Repeating";
            btnRepeat.BackColor = Color.FromArgb(145, 35, 35);
            Log($"Repeating every {repeatSec:g} seconds.");
        }
        else
        {
            repeatTimer.Stop();
            repeating = false;
            btnRepeat.Text = "Start Repeating";
            btnRepeat.BackColor = Color.FromArgb(170, 95, 15);
            Log("Repeating stopped. Serial port left open and ready.");
        }
    }

    private void SetStatus(string s, bool error)
    {
        lblStatus.Text = s;
        lblStatus.ForeColor = error ? Color.FromArgb(255, 120, 120) : Color.FromArgb(120, 255, 170);
    }

    private void Log(string s) => txtLog.AppendText(s + Environment.NewLine);

    private sealed class AppSettings
    {
        public string Port { get; set; } = "";
        public string Baud { get; set; } = "9600";
        public string Timeout { get; set; } = "1.0";
        public string Repeat { get; set; } = "60";
        public bool Utc { get; set; }
        public bool Align { get; set; } = true;
        public bool Dtr { get; set; } = true;
        public bool Rts { get; set; } = true;
        public string Ending { get; set; } = "CR";
    }
}
