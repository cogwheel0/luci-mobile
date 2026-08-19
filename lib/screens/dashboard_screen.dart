import 'dart:ui';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('LuCI Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Gradient
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
                _buildGlassCard(
                  title: 'System Status',
                  subtitle: 'OpenWrt 23.05 / KeeneticOS',
                  icon: Icons.router,
                  value: 'Online',
                  statusColor: Colors.greenAccent,
                ),
                const SizedBox(height: 16),
                _buildGlassCard(
                  title: 'CPU Load',
                  subtitle: '2.00 GHz - 4 Cores',
                  icon: Icons.memory,
                  value: '18%',
                  statusColor: Colors.cyanAccent,
                ),
                const SizedBox(height: 16),
                _buildGlassCard(
                  title: 'RAM Usage',
                  subtitle: '512 MB / 1024 MB',
                  icon: Icons.developer_board,
                  value: '50%',
                  statusColor: Colors.orangeAccent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required Color statusColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.15),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
                  ],
                ),
              ),
              Text(
                value,
                style: TextStyle(color: statusColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
