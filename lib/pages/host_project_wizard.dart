import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/embedded_backend.dart';
import '../providers/ai_server_provider.dart';
import '../services/guided_tour_service.dart';
import '../widgets/guided_tour_overlay.dart';
import '../services/git_service.dart';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class _WizardPalette {
  static const surfaceBody = Color(0xFF131312); // Matches dashboard
  static const primary = Color(0xFFFFFFFF);
  static const textDim = Color(0xFF8E9192);
  static const outline = Color(0xFF333333);
  static const hoverCard = Color(0x6620201F);
}

// ==========================================
// STEP 1: Host Source Picker
// ==========================================
class HostProjectSourcePage extends ConsumerStatefulWidget {
  const HostProjectSourcePage({super.key});

  @override
  ConsumerState<HostProjectSourcePage> createState() =>
      _HostProjectSourcePageState();
}

class _HostProjectSourcePageState
    extends ConsumerState<HostProjectSourcePage> {
  bool _isHoveringGit = false;
  bool _extracting = false;
  final _gitRepoKey = GlobalKey();
  final _localUploadKey = GlobalKey();
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final steps = [
        GuidedTourStep(
          title: 'Import Git Repository',
          description:
              'Connect your GitHub account to import and auto-deploy your source code.',
          targetKey: _gitRepoKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Upload Local Folder / Zip',
          description:
              'Drag & drop a local project directory or .zip file for instant offline hosting.',
          targetKey: _localUploadKey,
          tooltipPosition: TooltipPosition.top,
        ),
      ];
      ref.read(guidedTourNotifierProvider.notifier).startTour(steps);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _WizardPalette.surfaceBody,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  Text(
                    'Let\'s build something new.',
                    style: GoogleFonts.spaceMono(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.0,
                      color: _WizardPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'To deploy a new Project, import an existing Git Repository or upload local files.',
                    style: GoogleFonts.spaceMono(
                      fontSize: 14,
                      color: _WizardPalette.textDim,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 56),

                  // --- Git Section ---
                  Text(
                    'Import a Git repository',
                    style: GoogleFonts.spaceMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: _WizardPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  MouseRegion(
                    onEnter: (_) => setState(() => _isHoveringGit = true),
                    onExit: (_) => setState(() => _isHoveringGit = false),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GithubOAuthSimulationPage(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        key: _gitRepoKey,
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: _isHoveringGit ? _WizardPalette.hoverCard : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isHoveringGit ? Colors.white54 : _WizardPalette.outline,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _GitHubLogo(size: 20, color: _WizardPalette.primary),
                            const SizedBox(width: 12),
                            Text(
                              'GitHub',
                              style: GoogleFonts.spaceMono(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: _WizardPalette.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: _WizardPalette.outline)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'OR',
                          style: GoogleFonts.spaceMono(
                            fontSize: 12,
                            color: _WizardPalette.textDim,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider(color: _WizardPalette.outline)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Paste Repo URL Input
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _WizardPalette.outline),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.link, color: _WizardPalette.textDim, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            style: GoogleFonts.spaceMono(fontSize: 14, color: _WizardPalette.primary),
                            decoration: InputDecoration(
                              hintText: 'https://github.com/owner/repo',
                              hintStyle: GoogleFonts.spaceMono(color: _WizardPalette.textDim),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (val) => _handleUrlSubmit(val, context),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward, color: _WizardPalette.primary),
                          onPressed: () => _handleUrlSubmit(_urlController.text, context),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 56),

                  // --- Upload Section ---
                  Text(
                    'Upload your project files',
                    style: GoogleFonts.spaceMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: _WizardPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomPaint(
                    key: _localUploadKey,
                    painter: _DashedBorderPainter(
                      color: _WizardPalette.outline,
                      radius: 8,
                      dashWidth: 6,
                      dashSpace: 6,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                      alignment: Alignment.center,
                      child: Column(
                        children: [
                          Text(
                            'Drag and drop your project folder',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceMono(
                              fontSize: 16,
                              color: _WizardPalette.primary.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              Text(
                                'Or ',
                                style: GoogleFonts.spaceMono(
                                  color: _WizardPalette.textDim,
                                  fontSize: 13,
                                ),
                              ),
                              InkWell(
                                onTap: _extracting ? null : _handleZipUpload,
                                child: Text(
                                  'upload a .zip file',
                                  style: GoogleFonts.spaceMono(
                                    color: _WizardPalette.textDim,
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                    decorationColor: _WizardPalette.textDim,
                                  ),
                                ),
                              ),
                              Text(
                                ' or ',
                                style: GoogleFonts.spaceMono(
                                  color: _WizardPalette.textDim,
                                  fontSize: 13,
                                ),
                              ),
                              InkWell(
                                onTap: _extracting ? null : _handleFolderPick,
                                child: Text(
                                  'choose a folder.',
                                  style: GoogleFonts.spaceMono(
                                    color: _WizardPalette.textDim,
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                    decorationColor: _WizardPalette.textDim,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  Future<void> _handleFolderPick() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null || !mounted) return;
    final folderName = p.basename(result);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostProjectSettingsPage(
          repoName: folderName.isNotEmpty ? folderName : 'local-project',
          existingLocalPath: result,
        ),
      ),
    );
  }

  Future<void> _handleZipUpload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final zipPath = result.files.single.path;
    if (zipPath == null) return;

    setState(() => _extracting = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: Color(0xFF20201F),
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(width: 20),
                Text('Extracting zip…', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final destPath = p.join(docsDir.path, 'projects', const Uuid().v4());
      await Directory(destPath).create(recursive: true);

      final inputStream = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(inputStream);
      extractArchiveToDisk(archive, destPath);
      await inputStream.close();

      // If zip had a single top-level directory, use that as the project root
      final entries = Directory(destPath).listSync();
      final localPath =
          entries.length == 1 && entries.first is Directory
              ? entries.first.path
              : destPath;

      final zipName = result.files.single.name.replaceAll('.zip', '');
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => HostProjectSettingsPage(
            repoName: zipName.isEmpty ? 'local-project' : zipName,
            existingLocalPath: localPath,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to extract zip: $e')),
      );
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  void _handleUrlSubmit(String url, BuildContext context) {
    url = url.trim();
    if (url.isEmpty) return;

    // Very basic parsing to get a repo name
    String repoName = 'my-project';
    try {
      final uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty) {
        repoName = uri.pathSegments.last.replaceAll('.git', '');
      }
    } catch (_) {}

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostProjectSettingsPage(
          repoName: repoName,
          repoUrl: url,
        ),
      ),
    );
  }
}

// ==========================================
// DASHED BORDER PAINTER
// ==========================================
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({
    required this.color,
    this.dashWidth = 5.0,
    this.dashSpace = 5.0,
    this.radius = 8.0,
  });

  final Color color;
  final double dashWidth;
  final double dashSpace;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius),
        ),
      );

    final PathMetrics pathMetrics = path.computeMetrics();
    final Path dashedPath = Path();

    for (final PathMetric metric in pathMetrics) {
      double distance = 0.0;
      bool draw = true;
      while (distance < metric.length) {
        final double length = draw ? dashWidth : dashSpace;
        if (draw) {
          dashedPath.addPath(
            metric.extractPath(distance, distance + length),
            Offset.zero,
          );
        }
        distance += length;
        draw = !draw;
      }
    }

    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// GITHUB LOGO SVG WIDGET
// ==========================================
class _GitHubLogo extends StatelessWidget {
  const _GitHubLogo({required this.size, required this.color});
  
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/github.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

// ==========================================
// STEP 2 (SIMULATED): GitHub OAuth Login & Authorization
// ==========================================
class GithubOAuthSimulationPage extends StatefulWidget {
  const GithubOAuthSimulationPage({super.key});

  @override
  State<GithubOAuthSimulationPage> createState() =>
      _GithubOAuthSimulationPageState();
}

class _GithubOAuthSimulationPageState extends State<GithubOAuthSimulationPage> {
  bool _isAuthorizing = false;

  void _handleAuthorize() {
    setState(() {
      _isAuthorizing = true;
    });

    // Simulate OAuth API Token Exchange delay
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const GithubAppInstallSimulationPage(),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117), // GitHub Dark BG
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF161B22),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _GitHubLogo(size: 24, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'GitHub OAuth',
                style: GoogleFonts.spaceMono(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Interlocking avatars
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF21262D),
                          ),
                          child: const Icon(Icons.architecture,
                              size: 32, color: Colors.white),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.swap_horiz,
                              color: Colors.green, size: 28),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF21262D),
                          ),
                          child: const _GitHubLogo(size: 32, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Authorize Buildify',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceMono(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Buildify by sujith8257 wants access to your GitHub account to import repositories and set up automated deployments.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceMono(
                        fontSize: 12,
                        color: const Color(0xFF8B949E),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Color(0xFF30363D)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Read access to public & private repositories',
                            style: GoogleFonts.spaceMono(
                                fontSize: 11, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: Colors.green, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Permission to configure webhooks for rebuilds',
                            style: GoogleFonts.spaceMono(
                                fontSize: 11, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (_isAuthorizing)
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Exchanging authorization codes...',
                              style: TextStyle(
                                  color: Color(0xFF8B949E), fontSize: 11),
                            )
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFF0F6FC),
                                side: const BorderSide(color: Color(0xFF30363D)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF238636),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _handleAuthorize,
                              child: const Text('Authorize'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// STEP 3 (SIMULATED): GitHub App Installation / Repo Access Setup
// ==========================================
class GithubAppInstallSimulationPage extends ConsumerStatefulWidget {
  const GithubAppInstallSimulationPage({super.key});

  @override
  ConsumerState<GithubAppInstallSimulationPage> createState() =>
      _GithubAppInstallSimulationPageState();
}

class _GithubAppInstallSimulationPageState
    extends ConsumerState<GithubAppInstallSimulationPage> {
  bool _allRepos = true;
  final _repoChoiceKey = GlobalKey();
  final _installKey = GlobalKey();
  final List<String> _repos = const [
    'Sujith8257/mass',
    'Sujith8257/buildify',
    'Sujith8257/portfolio-v2',
    'Sujith8257/react-dashboard',
    'Sujith8257/node-express-api',
  ];
  final Set<String> _selectedRepos = {};

  @override
  void initState() {
    super.initState();
    _selectedRepos.addAll(_repos);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final steps = [
        GuidedTourStep(
          title: 'Repository Permissions',
          description:
              'Select whether Buildify can access all your repositories or specific ones.',
          targetKey: _repoChoiceKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Install & Authorize',
          description:
              'Tap Install & Authorize to connect your selected repositories.',
          targetKey: _installKey,
          tooltipPosition: TooltipPosition.top,
        ),
      ];
      ref.read(guidedTourNotifierProvider.notifier).startTour(steps);
    });
  }

  void _toggleRepo(String repo) {
    setState(() {
      if (_selectedRepos.contains(repo)) {
        _selectedRepos.remove(repo);
      } else {
        _selectedRepos.add(repo);
      }
    });
  }

  void _handleInstall() {
    final finalRepos = _allRepos ? _repos : _selectedRepos.toList();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HostProjectSelectPage(allowedRepos: finalRepos),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117), // GitHub Dark BG
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF161B22),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Install Buildify App',
              style: GoogleFonts.spaceMono(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Configure Repository Access',
                        style: GoogleFonts.spaceMono(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose which repositories Buildify has permission to see and deploy.',
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          color: const Color(0xFF8B949E),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Divider(color: Color(0xFF30363D)),
                      const SizedBox(height: 12),

                      Column(
                        key: _repoChoiceKey,
                        children: [
                          RadioListTile<bool>(
                            value: true,
                            groupValue: _allRepos,
                            onChanged: (val) {
                              if (val != null) setState(() => _allRepos = val);
                            },
                            title: Text(
                              'All repositories',
                              style: GoogleFonts.spaceMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                            subtitle: Text(
                              'Access all current and future repositories.',
                              style: GoogleFonts.spaceMono(
                                  fontSize: 11, color: const Color(0xFF8B949E)),
                            ),
                            activeColor: const Color(0xFF238636),
                            contentPadding: EdgeInsets.zero,
                          ),
                          RadioListTile<bool>(
                            value: false,
                            groupValue: _allRepos,
                            onChanged: (val) {
                              if (val != null) setState(() => _allRepos = val);
                            },
                            title: Text(
                              'Only select repositories',
                              style: GoogleFonts.spaceMono(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white),
                            ),
                            subtitle: Text(
                              'Choose specific repositories to deploy.',
                              style: GoogleFonts.spaceMono(
                                  fontSize: 11, color: const Color(0xFF8B949E)),
                            ),
                            activeColor: const Color(0xFF238636),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),

                      if (!_allRepos) ...[
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF30363D)),
                            color: const Color(0xFF0D1117),
                          ),
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: _repos.map((repo) {
                              final isChecked = _selectedRepos.contains(repo);
                              return CheckboxListTile(
                                value: isChecked,
                                onChanged: (_) => _toggleRepo(repo),
                                title: Text(
                                  repo,
                                  style: GoogleFonts.spaceMono(
                                      fontSize: 12, color: Colors.white),
                                ),
                                activeColor: const Color(0xFF238636),
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                      ElevatedButton(
                        key: _installKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF238636),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onPressed: !_allRepos && _selectedRepos.isEmpty
                            ? null
                            : _handleInstall,
                        child: Text(
                          'Install & Authorize',
                          style: GoogleFonts.spaceMono(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PAGE 4: Select Repository
// ==========================================
class HostProjectSelectPage extends StatefulWidget {
  const HostProjectSelectPage({super.key, required this.allowedRepos});
  final List<String> allowedRepos;

  @override
  State<HostProjectSelectPage> createState() => _HostProjectSelectPageState();
}

class _HostProjectSelectPageState extends State<HostProjectSelectPage> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredRepos = widget.allowedRepos
        .where((repo) => repo.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _WizardPalette.surfaceBody,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Import Git Repository',
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _WizardPalette.primary,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    hintText: 'Search repositories...',
                    hintStyle: GoogleFonts.spaceMono(color: _WizardPalette.textDim),
                    prefixIcon: const Icon(Icons.search, color: _WizardPalette.textDim),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ...filteredRepos.map((repo) {
                  final name = repo.split('/').last;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _WizardPalette.outline),
                    ),
                    child: Row(
                      children: [
                        const _GitHubLogo(size: 24, color: _WizardPalette.primary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            repo,
                            style: GoogleFonts.spaceMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _WizardPalette.primary,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _WizardPalette.primary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    HostProjectSettingsPage(repoName: name),
                              ),
                            );
                          },
                          child: Text(
                            'Import',
                            style: GoogleFonts.spaceMono(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (filteredRepos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'No repositories found',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceMono(color: _WizardPalette.textDim),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// PAGE 5: Build Settings & Configuration
// ==========================================
class HostProjectSettingsPage extends ConsumerStatefulWidget {
  const HostProjectSettingsPage({
    super.key,
    required this.repoName,
    this.repoUrl,
    this.existingLocalPath,
  });
  final String repoName;
  final String? repoUrl;
  final String? existingLocalPath;

  @override
  ConsumerState<HostProjectSettingsPage> createState() =>
      _HostProjectSettingsPageState();
}

class _HostProjectSettingsPageState
    extends ConsumerState<HostProjectSettingsPage> {
  late final TextEditingController _nameController;
  final _branchController = TextEditingController(text: 'main');
  final _baseDirController = TextEditingController();
  final _buildCommandController = TextEditingController();
  final _publishDirController = TextEditingController();

  final List<MapEntry<TextEditingController, TextEditingController>> _envVars = [];

  final _nameKey = GlobalKey();
  final _branchKey = GlobalKey();
  final _deployKey = GlobalKey();

  bool _isDeploying = false;
  String _deployProgress = '';
  String _selectedFramework = 'Static HTML';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.repoName);
    _nameController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final steps = [
        GuidedTourStep(
          title: 'Project Name & Subdomain',
          description:
              'Specify your project name to generate your custom local hosting URL.',
          targetKey: _nameKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Target Branch',
          description:
              'Choose which branch to compile and serve (e.g. main or release).',
          targetKey: _branchKey,
          tooltipPosition: TooltipPosition.bottom,
        ),
        GuidedTourStep(
          title: 'Deploy Application',
          description:
              'Tap Deploy to start building and hosting your application session.',
          targetKey: _deployKey,
          tooltipPosition: TooltipPosition.top,
        ),
      ];
      ref.read(guidedTourNotifierProvider.notifier).startTour(steps);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _branchController.dispose();
    _baseDirController.dispose();
    _buildCommandController.dispose();
    _publishDirController.dispose();
    for (final pair in _envVars) {
      pair.key.dispose();
      pair.value.dispose();
    }
    super.dispose();
  }

  void _addEnvVar() {
    setState(() {
      _envVars.add(MapEntry(TextEditingController(), TextEditingController()));
    });
  }

  void _removeEnvVar(int index) {
    setState(() {
      final pair = _envVars.removeAt(index);
      pair.key.dispose();
      pair.value.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final projName = _nameController.text.trim().isEmpty
        ? 'project'
        : _nameController.text.trim().toLowerCase().replaceAll(' ', '-');
    final previewUrl = 'https://$projName.buildify.app';

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _WizardPalette.surfaceBody,
        textTheme: GoogleFonts.spaceMonoTextTheme(ThemeData.dark().textTheme),
      ),
      child: GuidedTourOverlay(
        child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'build - ${widget.repoName}',
            style: GoogleFonts.spaceMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _WizardPalette.primary,
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              children: [
                // Source info card for local deployments
                if (widget.existingLocalPath != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_open,
                            color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.existingLocalPath!,
                            style: GoogleFonts.spaceMono(
                              fontSize: 11,
                              color: const Color(0xFF10B981),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Project Name Input
                Text(
                  'Project name',
                  style: GoogleFonts.spaceMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _WizardPalette.primary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: _nameKey,
                  controller: _nameController,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  previewUrl,
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 32),

                // Build Settings Header
                Text(
                  'Build settings',
                  style: GoogleFonts.spaceMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _WizardPalette.primary,
                  ),
                ),
                const SizedBox(height: 16),

                // Framework / runtime selector
                Text(
                  'Framework',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedFramework,
                  dropdownColor: _WizardPalette.surfaceBody,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                  items: ['Static HTML', 'Node.js', 'Python FastAPI', 'Flask']
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedFramework = val!),
                ),
                const SizedBox(height: 16),

                // Branch to deploy
                Text(
                  'Branch to deploy',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  key: _branchKey,
                  controller: _branchController,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Base directory
                Text(
                  'Base directory',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _baseDirController,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    hintText: '/',
                    hintStyle: GoogleFonts.spaceMono(color: Colors.white30),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'The directory where Buildify installs dependencies and runs your build command.',
                  style: GoogleFonts.spaceMono(
                    fontSize: 10,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 16),

                // Build command
                Text(
                  'Build command',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _buildCommandController,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    hintText: 'Examples: jekyll build, gulp build, make all',
                    hintStyle: GoogleFonts.spaceMono(
                      color: Colors.white30,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Publish directory
                Text(
                  'Publish directory',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _publishDirController,
                  style: GoogleFonts.spaceMono(color: _WizardPalette.primary),
                  decoration: InputDecoration(
                    hintText: 'Examples: _site, dist, public',
                    hintStyle: GoogleFonts.spaceMono(
                      color: Colors.white30,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.outline),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _WizardPalette.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Environment Variables Header
                Text(
                  'Environment variables',
                  style: GoogleFonts.spaceMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _WizardPalette.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Define environment variables for more control and flexibility over your build.',
                  style: GoogleFonts.spaceMono(
                    fontSize: 12,
                    color: _WizardPalette.textDim,
                  ),
                ),
                const SizedBox(height: 16),

                // Environment Variable List
                ...List.generate(_envVars.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _envVars[index].key,
                            style: GoogleFonts.spaceMono(
                              color: _WizardPalette.primary,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Key',
                              hintStyle: GoogleFonts.spaceMono(
                                color: Colors.white30,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _envVars[index].value,
                            style: GoogleFonts.spaceMono(
                              color: _WizardPalette.primary,
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Value',
                              hintStyle: GoogleFonts.spaceMono(
                                color: Colors.white30,
                                fontSize: 12,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.05),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: () => _removeEnvVar(index),
                        ),
                      ],
                    ),
                  );
                }),

                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: _WizardPalette.primary,
                    ),
                    onPressed: _addEnvVar,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      'Add environment variables',
                      style: GoogleFonts.spaceMono(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Deploy Button
                ElevatedButton(
                  key: _deployKey,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _WizardPalette.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isDeploying ? null : () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;

                    setState(() {
                      _isDeploying = true;
                      _deployProgress = 'Initializing...';
                    });

                    try {
                      final envMap = <String, String>{};
                      for (final entry in _envVars) {
                        final k = entry.key.text.trim();
                        final v = entry.value.text.trim();
                        if (k.isNotEmpty) {
                          envMap[k] = v;
                        }
                      }

                      // Create the project in the backend (this allocates port and path)
                      final project = await ref.read(embeddedBackendProvider).createProject(
                            name: name,
                            sourceType: _selectedFramework,
                            customUrl: previewUrl,
                            customLocalPath: widget.existingLocalPath,
                            hostingMode: HostingMode.persistent,
                            branch: _branchController.text.trim().isNotEmpty ? _branchController.text.trim() : 'main',
                            buildCommand: _buildCommandController.text.trim(),
                            publishDir: _publishDirController.text.trim(),
                            baseDir: _baseDirController.text.trim(),
                            envVars: envMap,
                          );

                      // Clone the repo if we have a URL and no local path already provided
                      if (widget.repoUrl != null && widget.repoUrl!.isNotEmpty && widget.existingLocalPath == null) {
                        await GitService.cloneRepository(
                          repoUrl: widget.repoUrl!,
                          localPath: project.localPath,
                          onProgress: (status) {
                            if (context.mounted) {
                              setState(() => _deployProgress = status);
                            }
                          },
                        );
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Successfully deployed $name',
                              style: GoogleFonts.spaceMono(),
                            ),
                          ),
                        );
                        // Go back to projects home page dashboard
                        Navigator.popUntil(context, (route) => route.isFirst);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to deploy project: $e'),
                          ),
                        );
                      }
                    } finally {
                      if (context.mounted) {
                        setState(() {
                          _isDeploying = false;
                        });
                      }
                    }
                  },
                  child: _isDeploying
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _deployProgress,
                              style: GoogleFonts.spaceMono(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          'Deploy $projName',
                          style: GoogleFonts.spaceMono(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}
