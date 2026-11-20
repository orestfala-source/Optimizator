using System;
using System.Collections.Generic;
using System.Linq;
using LibreHardwareMonitor.Hardware;

namespace Optimizator.Core;

public sealed class FanChannel
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required ISensor ControlSensor { get; init; }
    public ISensor? RpmSensor { get; init; }
    public IControl Control => ControlSensor.Control;
    public float? Rpm => RpmSensor?.Value;
    public float? CurrentPercent => ControlSensor.Value;
    public float MinPercent => Control.MinSoftwareValue;
    public float MaxPercent => Control.MaxSoftwareValue;
}

/// <summary>
/// Керування вентиляторами через LibreHardwareMonitor: материнські плати (Super I/O),
/// відеокарти NVIDIA/AMD, деякі контролери. На багатьох ноутбуках виробник блокує керування —
/// тоді показуємо лише оберти і температуру.
/// </summary>
public sealed class FanService : IDisposable
{
    readonly Computer _pc = new()
    {
        IsCpuEnabled = true, IsGpuEnabled = true, IsMotherboardEnabled = true, IsControllerEnabled = true
    };

    public List<FanChannel> Channels { get; } = new();
    public List<ISensor> RpmOnly { get; } = new();
    public string? Error { get; private set; }
    public float? CpuTemp { get; private set; }
    public float? GpuTemp { get; private set; }
    bool _open;

    public void Open()
    {
        try
        {
            _pc.Open();
            _open = true;
            Update();
            Scan();
        }
        catch (Exception e) { Error = e.Message; }
    }

    void Scan()
    {
        Channels.Clear(); RpmOnly.Clear();
        foreach (var hw in AllHardware())
        {
            var fans = hw.Sensors.Where(s => s.SensorType == SensorType.Fan).ToList();
            foreach (var c in hw.Sensors.Where(s => s.SensorType == SensorType.Control && s.Control != null))
            {
                var rpm = fans.FirstOrDefault(f => f.Index == c.Index) ?? (fans.Count == 1 ? fans[0] : null);
                Channels.Add(new FanChannel
                {
                    Id = c.Identifier.ToString(),
                    Name = $"{hw.Name} · {c.Name}",
                    ControlSensor = c,
                    RpmSensor = rpm
                });
            }
            foreach (var f in fans)
                if (!Channels.Any(ch => ch.RpmSensor == f)) RpmOnly.Add(f);
        }
    }

    IEnumerable<IHardware> AllHardware()
    {
        foreach (var h in _pc.Hardware)
        {
            yield return h;
            foreach (var s in h.SubHardware) yield return s;
        }
    }

    public void Update()
    {
        if (!_open) return;
        float? cpu = null, gpu = null;
        foreach (var h in AllHardware())
        {
            try { h.Update(); } catch { }
            foreach (var s in h.Sensors.Where(s => s.SensorType == SensorType.Temperature && s.Value is > 0 and < 130))
            {
                if (h.HardwareType == HardwareType.Cpu) cpu = Math.Max(cpu ?? 0, s.Value!.Value);
                else if (h.HardwareType is HardwareType.GpuNvidia or HardwareType.GpuAmd or HardwareType.GpuIntel)
                    gpu = Math.Max(gpu ?? 0, s.Value!.Value);
            }
        }
        CpuTemp = cpu; GpuTemp = gpu;
    }

    public void SetPercent(FanChannel ch, float percent)
    {
        try { ch.Control.SetSoftware(Math.Clamp(percent, ch.MinPercent, ch.MaxPercent)); }
        catch (Exception e) { Error = e.Message; }
    }

    public void SetAuto(FanChannel ch)
    {
        try { ch.Control.SetDefault(); } catch { }
    }

    public void AllAuto()
    {
        foreach (var c in Channels) SetAuto(c);
    }

    public void Dispose()
    {
        if (!_open) return;
        AllAuto();
        try { _pc.Close(); } catch { }
        _open = false;
    }
}
