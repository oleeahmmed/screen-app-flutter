// dashboard_page.dart - Dashboard Page with Company Timezone & Activity Tracking

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/screenshot_service.dart';
import '../services/user_data_service.dart';

class DashboardPage extends StatefulWidget {
  final ApiService apiService;
  final String username;
  final ScreenshotService? screenshotService;

  const DashboardPage({
    required this.apiService,
    required this.username,
    this.screenshotService,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isClockedIn = false;
  Duration _workDuration = Duration.zero;
  Duration _todayWorkDuration = Duration.zero;
  late DateTime _clockInTime;
  late DateTime _now;
  String _companyTimezone = 'UTC';
  String _companyName = '';
  String _fullName = '';
  String _designation = '';
  String _department = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _loadUserData();
    _startClock();
  }
  
  Future<void> _loadUserData() async {
    final userData = await UserDataService.getUserData();
    setState(() {
      _companyName = userData['company_name'] ?? '';
      _fullName = userData['full_name'] ?? widget.username;
      _designation = userData['designation'] ?? '';
      _department = userData['department'] ?? '';
    });
    
    print('👤 Dashboard loaded for: $_fullName');
    print('🏢 Company: $_companyName');
    print('💼 Designation: $_designation');
  }

  void _startClock() {
    Future.delayed(Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
        _startClock();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _recordUserActivity();
  }

  void _recordUserActivity() {
    widget.screenshotService?.recordActivity();
  }

  Future<void> _toggleClock() async {
    if (_isProcessing) return;
    
    _recordUserActivity();
    setState(() => _isProcessing = true);
    
    try {
      if (_isClockedIn) {
        print('🔄 Attempting checkout...');
        final result = await widget.apiService.checkOut();
        print('📊 Checkout result: ${result['success']}');
        print('📝 Response: ${result['data'] ?? result['error']}');
        
        if (result['success']) {
          setState(() {
            _isClockedIn = false;
            _todayWorkDuration += _workDuration;
            _workDuration = Duration.zero;
          });
          
          // Stop screenshot capture on checkout (silently)
          widget.screenshotService?.stopCapture();
          
          _showSnackBar('✓ Checked out successfully', Colors.green);
        } else {
          // Show detailed error message
          final errorMsg = result['error'] ?? 'Check-out failed';
          _showErrorDialog('Check-out Error', errorMsg);
        }
      } else {
        print('🔄 Attempting checkin...');
        final result = await widget.apiService.checkIn();
        print('📊 Checkin result: ${result['success']}');
        print('📝 Response: ${result['data'] ?? result['error']}');
        
        if (result['success']) {
          setState(() {
            _isClockedIn = true;
            _clockInTime = DateTime.now();
          });
          
          // Start screenshot capture on checkin (silently)
          widget.screenshotService?.startCapture();
          
          _showSnackBar('✓ Checked in successfully', Colors.green);
        } else {
          // Show detailed error message
          final errorMsg = result['error'] ?? 'Check-in failed';
          _showErrorDialog('Check-in Error', errorMsg);
        }
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isClockedIn) {
      _workDuration = _now.difference(_clockInTime);
    }

    return GestureDetector(
      onTap: _recordUserActivity,
      onPanDown: (_) => _recordUserActivity(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(int.parse('0xFF2563eb')),
              Color(int.parse('0xFF1e40af')),
              Color(int.parse('0xFF1e3a5f')),
              Color(int.parse('0xFF0f172a')),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hi, ${_fullName.isNotEmpty ? _fullName : widget.username}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                fontStyle: FontStyle.italic,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 2),
                            if (_designation.isNotEmpty)
                              Text(
                                _designation + (_department.isNotEmpty ? ' • $_department' : ''),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (_companyName.isNotEmpty)
                              Text(
                                _companyName,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white54,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.menu, color: Colors.white, size: 24),
                    ],
                  ),
                  SizedBox(height: 16),
                  Column(
                    children: [
                      Text(
                        DateFormat('EEEE').format(_now).toUpperCase(),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        DateFormat('dd MMMM yyyy').format(_now),
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(int.parse('0xFF8899aa')),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTimeCard(
                          'COMPANY',
                          _getCompanyTime(),
                          'UTC',
                          Color(int.parse('0xFF4CD964')),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: _buildTimeCard(
                          'YOUR TIME',
                          DateFormat('HH:mm').format(_now),
                          'Local',
                          Color(int.parse('0xFF2196F3')),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Column(
                    children: [
                      Text(
                        _formatDuration(_workDuration),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                          fontFamily: 'monospace',
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Current Session',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(int.parse('0xFF4CD964')),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today\'s Work',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _formatDuration(_todayWorkDuration),
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(int.parse('0xFF4CD964')),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _toggleClock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isClockedIn
                            ? Color(int.parse('0xFFE74C3C'))
                            : Color(int.parse('0xFF4CD964')),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: Colors.grey,
                      ),
                      child: _isProcessing
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _isClockedIn ? 'Clock Out' : 'Clock In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: 16),
                  
                  // Screenshot Service Status
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.monitor,
                              color: Color(int.parse('0xFF3B82F6')),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Multi-Monitor Capture',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                            ),
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (widget.screenshotService?.isRunning ?? false)
                                    ? Color(int.parse('0xFF4CD964')).withOpacity(0.2)
                                    : Color(int.parse('0xFFE74C3C')).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (widget.screenshotService?.isRunning ?? false) ? 'ACTIVE' : 'STOPPED',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: (widget.screenshotService?.isRunning ?? false)
                                      ? Color(int.parse('0xFF4CD964'))
                                      : Color(int.parse('0xFFE74C3C')),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Displays: ${widget.screenshotService?.displayCount ?? 0}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white54,
                              ),
                            ),
                            Text(
                              'Activity: ${(widget.screenshotService?.isUserActive ?? false) ? 'Active' : 'Idle'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: (widget.screenshotService?.isUserActive ?? false)
                                    ? Color(int.parse('0xFF4CD964'))
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeCard(String label, String time, String tz, Color color) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 4),
          Text(
            time,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
              fontFamily: 'monospace',
            ),
          ),
          SizedBox(height: 2),
          Text(
            tz,
            style: TextStyle(
              fontSize: 8,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _getCompanyTime() {
    return DateFormat('HH:mm').format(_now.toUtc());
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
  }
}
