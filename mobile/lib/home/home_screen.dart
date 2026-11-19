import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import '../users/avatar.dart';
import '../users/user_service.dart';

/// First screen: app name and a profile avatar at the top right. The body is empty on purpose.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UserProfile? _user;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final user = await UserService().me();
      if (mounted) setState(() => _user = user);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whiskr', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: user != null
                ? Tooltip(
                    message: user.fullName,
                    child: InkResponse(
                      radius: 24,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AccountScreen(user: user)),
                      ),
                      child: Avatar(initials: user.initials),
                    ),
                  )
                : _failed
                    ? IconButton(
                        tooltip: 'Retry loading profile',
                        icon: const Icon(Icons.refresh),
                        onPressed: () {
                          setState(() => _failed = false);
                          _loadUser();
                        },
                      )
                    : const SizedBox(
                        width: 36,
                        height: 36,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
          ),
        ],
      ),
      body: const SizedBox.expand(),
    );
  }
}
