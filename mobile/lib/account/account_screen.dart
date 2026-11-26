import 'package:flutter/material.dart';

import '../auth/auth_service.dart';
import '../billing/billing_screen.dart';
import '../subscriptions/subscription_actions.dart';
import '../users/avatar.dart';
import '../users/edit_profile_screen.dart';
import '../users/user_service.dart';

/// Account page: big avatar, name, details card and the plan tile.
class AccountScreen extends StatefulWidget {
  final UserProfile user;

  /// Called after the profile is saved, so the screen below (home) can show the new name.
  final ValueChanged<UserProfile>? onChanged;
  const AccountScreen({super.key, required this.user, this.onChanged});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SubscriptionActions<AccountScreen> {
  late UserProfile _user = widget.user;

  @override
  void initState() {
    super.initState();
    loadInfo();
  }

  String get _planLabel {
    final i = info;
    if (i == null) return loadError != null ? 'Unavailable' : '...';
    return i.planId == 'pro' ? 'Pro' : 'Basic';
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(user: _user)),
    );
    if (updated == null || !mounted) return;
    setState(() => _user = updated);
    widget.onChanged?.call(updated);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final pro = info?.planId == 'pro';
    final blue = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Avatar(initials: user.initials, radius: 48),
                  const SizedBox(height: 16),
                  Text(user.displayName,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _InfoRow(icon: Icons.mail_outline, label: 'Email', value: user.email),
                        const Divider(height: 1),
                        _InfoRow(icon: Icons.phone_outlined, label: 'Phone number', value: user.phone ?? 'Not added'),
                        const Divider(height: 1),
                        _InfoRow(icon: Icons.workspace_premium_outlined, label: 'Subscription', value: _planLabel),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: const Icon(Icons.edit_outlined),
                          title: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w500)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _editProfile,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          leading: Icon(Icons.auto_awesome, color: blue),
                          title: Text(pro ? 'Manage billing' : 'Upgrade to Pro',
                              style: TextStyle(color: blue, fontWeight: FontWeight.w500)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: info == null
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const BillingScreen()),
                                  ).then((_) => loadInfo()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                      title: Text('Log out',
                          style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w500)),
                      // The AuthGate closes this page and shows the login screen once the status changes.
                      onTap: () => AuthService.instance.logout(),
                    ),
                  ),
                  if (loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        children: [
                          Text(loadError!, textAlign: TextAlign.center),
                          TextButton(onPressed: loadInfo, child: const Text('Retry')),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600)),
          ),
        ],
      ),
    );
  }
}
