import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/server_base_url_provider.dart';


class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isWorkerMode = false;
  bool _otpRequested = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    if (_isWorkerMode) {
      if (!_otpRequested) {
        final (success, _) = await ref
            .read(authStateProvider.notifier)
            .requestWorkerOtp(_phoneController.text.trim());
        if (success && mounted) {
          setState(() {
            _otpRequested = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('OTP sent. Please verify to continue.')),
          );
        } else {
          _showErrorIfAny();
        }
        return;
      }

      final success = await ref
          .read(authStateProvider.notifier)
          .verifyWorkerOtp(
              _phoneController.text.trim(), _otpController.text.trim());
      if (success && mounted) {
        context.go('/');
      } else {
        _showErrorIfAny();
      }
      return;
    }

    final success = await ref
        .read(authStateProvider.notifier)
        .login(_emailController.text.trim(), _passwordController.text);

    if (success && mounted) {
      context.go('/');
    } else {
      _showErrorIfAny();
    }
  }

  void _showErrorIfAny() {
    final error = ref.read(authStateProvider).error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: AppTheme.danger,
        ),
      );
    }
  }

  void _showDeveloperOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link_rounded),
              title: const Text('Server Configuration'),
              onTap: () {
                Navigator.pop(context);
                context.push('/server');
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Debug Logs'),
              onTap: () {
                Navigator.pop(context);
                context.push('/debug-logs');
              },
            ),
            const SizedBox(height: AppTheme.sp16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isBootstrapping = authState.isLoading && authState.user == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: Center(
          child: isBootstrapping
              ? const Padding(
                  padding: EdgeInsets.all(AppTheme.sp24),
                  child: CircularProgressIndicator(),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.sp24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GestureDetector(
                          onLongPress: _showDeveloperOptions,
                          child: const Icon(
                            Icons.inventory_2_rounded,
                            size: 64,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: AppTheme.sp16),
                        Text(
                          AppConstants.appName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontSize: 28,
                                letterSpacing: -1,
                              ),
                        ),
                        const SizedBox(height: AppTheme.sp4),
                        Text(
                          AppConstants.appTagline,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                        ),
                        const SizedBox(height: 48),

                        if (ref.watch(serverBaseUrlProvider).isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppTheme.sp24),
                            child: InkWell(
                              onTap: () => context.push('/server'),
                              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                              child: Container(
                                padding: const EdgeInsets.all(AppTheme.sp12),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                                  border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline, color: AppTheme.danger, size: 20),
                                    const SizedBox(width: AppTheme.sp12),
                                    Expanded(
                                      child: Text(
                                        'Server not configured. Tap here to set up.',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppTheme.danger,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('Admin Login'),
                              icon: Icon(Icons.admin_panel_settings_outlined),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Worker Login'),
                              icon: Icon(Icons.phone_android_rounded),
                            ),
                          ],
                          selected: {_isWorkerMode},
                          onSelectionChanged: (value) {
                            setState(() {
                              _isWorkerMode = value.first;
                              _otpRequested = false;
                              _otpController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: AppTheme.sp16),

                        if (!_isWorkerMode) ...[
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'Enter your email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (val) {
                              if (_isWorkerMode) {
                                return null;
                              }
                              if (val == null || val.isEmpty) {
                                return 'Email is required';
                              }
                              if (!val.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppTheme.sp16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (val) {
                              if (_isWorkerMode) {
                                return null;
                              }
                              if (val == null || val.isEmpty) {
                                return 'Password is required';
                              }
                              if (val.length < 6) {
                                return 'Password too short';
                              }
                              return null;
                            },
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              hintText: 'Enter registered worker phone',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (val) {
                              if (!_isWorkerMode) return null;
                              final v = (val ?? '').trim();
                              if (v.isEmpty) return 'Phone number is required';
                              if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: AppTheme.sp16),
                          if (_otpRequested) ...[
                            TextFormField(
                              controller: _otpController,
                              decoration: const InputDecoration(
                                labelText: 'OTP',
                                hintText: 'Enter 6-digit OTP',
                                prefixIcon: Icon(Icons.password_outlined),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (val) {
                                if (!_isWorkerMode || !_otpRequested) {
                                  return null;
                                }
                                final v = (val ?? '').trim();
                                if (v.isEmpty) {
                                  return 'OTP is required';
                                }
                                if (v.length < 6) {
                                  return 'Enter valid OTP';
                                }
                                return null;
                              },
                            ),
                          ],
                        ],
                        const SizedBox(height: AppTheme.sp32),

                        // Login Button
                        ElevatedButton(
                          onPressed: authState.isLoading ? null : _handleLogin,
                          child: authState.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  !_isWorkerMode
                                      ? 'Log In'
                                      : (_otpRequested
                                          ? 'Verify OTP'
                                          : 'Send OTP'),
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
}
