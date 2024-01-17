import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:line_icons/line_icons.dart';
// import 'package:filesaverz/filesaverz.dart';

import 'language.dart';
import 'utils.dart';

const String githubUrl = 'https://github.com/doraemonkeys/WindSend';
const String donateUrl = 'https://doraemonkeys.github.io/donate_page';
const String downloadUrl = 'https://github.com/doraemonkeys/WindSend/releases';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.formatString(AppLocale.about, [])),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(LineIcons.github),
            title: const Text('Github'),
            subtitle: Text(context.formatString(AppLocale.openSource, [])),
            onTap: () {
              launchInBrowser(Uri.parse(githubUrl));
            },
          ),
          ListTile(
            leading: const Icon(LineIcons.donate),
            title: Text(context.formatString(AppLocale.donate, [])),
            subtitle: Text(context.formatString(AppLocale.donateAuthor, [])),
            onTap: () {
              launchInBrowser(Uri.parse(donateUrl));
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text("Release"),
            subtitle:
                Text(context.formatString(AppLocale.downloadLatestVersion, [])),
            onTap: () {
              launchInBrowser(Uri.parse(downloadUrl));
            },
          ),
        ],
      ),
    );
  }
}
