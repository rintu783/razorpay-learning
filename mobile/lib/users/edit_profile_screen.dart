import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import 'user_service.dart';

/// "Update profile": optional name and phone. Pops with the saved [UserProfile].
class EditProfileScreen extends StatefulWidget {
  final UserProfile user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // Same rule as the server, so most mistakes are caught before sending.
  static final _phonePattern = RegExp(r'^\+?[0-9 ()\-]{7,30}$');

  final _form = GlobalKey<FormState>();
  late final _first = TextEditingController(text: widget.user.firstName ?? '');
  late final _last = TextEditingController(text: widget.user.lastName ?? '');
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  String? _validateName(String? v) => (v ?? '').trim().length > 60 ? 'Use at most 60 characters' : null;

  String? _validatePhone(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null; // optional
    return _phonePattern.hasMatch(value) ? null : 'Enter 7 to 30 digits. You can use spaces, +, - and ()';
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // All three are sent every time. An empty value clears the field on the server.
      final updated = await UserService().updateProfile(
        firstName: _first.text.trim(),
        lastName: _last.text.trim(),
        phone: _phone.text.trim(),
      );
      if (mounted) Navigator.pop(context, updated);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) =>
      InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _first,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('First name', Icons.person_outline),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _last,
                      enabled: !_saving,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration('Last name', Icons.person_outline),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phone,
                      enabled: !_saving,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: _decoration('Phone number', Icons.phone_outlined),
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 8),
                    Text('Your email (${widget.user.email}) cannot be changed here.',
                        style: TextStyle(color: Colors.grey.shade600)),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_error!,
                            key: const Key('profile-error'),
                            style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
