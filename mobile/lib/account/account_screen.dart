import 'package:flutter/material.dart';

import '../billing/billing_screen.dart';
import '../subscriptions/subscription_actions.dart';
import '../users/avatar.dart';
import '../users/user_service.dart';

/// Account page: big avatar, name, details card and the plan tile.
class AccountScreen extends StatefulWidget {
  final UserProfile user;
  const AccountScreen({super.key, required this.user});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SubscriptionActions<AccountScreen> {
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

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
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
                  Text(user.fullName,
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
                        _InfoRow(icon: Icons.phone_outlined, label: 'Phone number', value: user.phone),
                        const Divider(height: 1),
                        _InfoRow(icon: Icons.workspace_premium_outlined, label: 'Subscription', value: _planLabel),
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
