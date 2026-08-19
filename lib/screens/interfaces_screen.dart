import 'dart:ui';
import 'package:flutter/material.dart';

class InterfacesScreen extends StatelessWidget {
  const InterfacesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Network Interfaces', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildInterfaceTile('LAN (br-lan)', '192.168.1.1', 'Up', Colors.greenAccent),
                const SizedBox(height: 12),
                _buildInterfaceTile('WAN (eth0)', '10.0.0.2', 'Up', Colors.greenAccent),
                const SizedBox(height: 12),
                _buildInterfaceTile('WWAN (wlan0)', '192.168.0.50', 'Down', Colors.redAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInterfaceTile(String name, String ip, String status, Color statusColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(ip, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor),
                ),
                child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
