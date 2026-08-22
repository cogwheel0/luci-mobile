class GlInetRadio {
  final int? channel;
  final String? band;

  const GlInetRadio({this.channel, this.band});
}

class GlInetClient {
  final bool? online;
  final String? wifiBand;
  final String? deviceClass;
  final String? name;
  final String? alias;

  const GlInetClient({
    this.online,
    this.wifiBand,
    this.deviceClass,
    this.name,
    this.alias,
  });
}

class GlInetData {
  final Map<String, GlInetRadio> radios;
  final Map<String, GlInetClient> clients;
  final double? cpuTemperature;
  final int? fanSpeed;
  final bool? fanActive;
  final String? tailscaleIp;
  final String? tailscaleLogin;
  final int? tailscaleStatus;
  final int? cpuCores;

  const GlInetData({
    this.radios = const {},
    this.clients = const {},
    this.cpuTemperature,
    this.fanSpeed,
    this.fanActive,
    this.tailscaleIp,
    this.tailscaleLogin,
    this.tailscaleStatus,
    this.cpuCores,
  });

  GlInetData withCpuCores(int cores) => GlInetData(
    radios: radios,
    clients: clients,
    cpuTemperature: cpuTemperature,
    fanSpeed: fanSpeed,
    fanActive: fanActive,
    tailscaleIp: tailscaleIp,
    tailscaleLogin: tailscaleLogin,
    tailscaleStatus: tailscaleStatus,
    cpuCores: cores,
  );
}
