part of stagedive;

class Application {
    final Logger _logger = new Logger("stagedive.Application");

    static const String TEMPLATENAME = "templatename";


    /// Commandline options
    final Options options;

    Application() : options = new Options();

    void run(List<String> args) {
        try {
            final ArgResults argResults = options.parse(args);
            final Config config = new Config(argResults);

            _configLogging(config.loglevel);

            if (argResults.wasParsed(Options._ARG_HELP) || (config.dirstoscan.length == 0 && args.length == 0)) {
                options.showUsage();
                return;
            }

            if (argResults.wasParsed(Options._ARG_SETTINGS)) {
                config.printSettings();
                return;
            }

            if (argResults.wasParsed(Options._ARG_LIST_TEMPLATES)) {
                _listTemplates(config.loglevel);
                return;
            }

            bool foundOptionToWorkWith = false;

            if (config.projectdir.isNotEmpty && config.dirstoscan.length == 1) {
                foundOptionToWorkWith = true;
                _generateTemplate(config);
            }

            if (!foundOptionToWorkWith) {
                options.showUsage();
            }
        }

        on FormatException
        catch (error) {
            _logger.shout(error);
            options.showUsage();
        }
    }


    // -- private -------------------------------------------------------------

    void _listTemplates(final String loglevel) {
        Validate.notBlank(loglevel);


        Directory packages;
        try {
            packages = new Directory(_getPackagesFolder());
        } on ArgumentError catch(e) {
            _logger.shout(e.message);
            return;
        }

        packages.listSync().where((final FileSystemEntity entity) => FileSystemEntity.isDirectorySync(entity.path))
            .forEach((final FileSystemEntity entity) {

            _logger.fine("Checking: ${entity.path}");
            final Directory templates = new Directory("${entity.path}/_templates");
            if(templates.existsSync()) {
                templates.listSync().where((final FileSystemEntity entity) => FileSystemEntity.isDirectorySync(entity.path))
                    .forEach((final FileSystemEntity entity) {

                    final File manifest = new File("${entity.path}/manifest.yaml");
                    if(manifest.existsSync()) {
                        final yaml.YamlMap map = yaml.loadYaml(manifest.readAsStringSync());

                        final String indention = loglevel == "debug" ? "    " : "";
                        final String name = map[TEMPLATENAME];
                        final String sampleName = ("'${name}'").padRight(30);
                        _logger.info("${indention}${sampleName} found in ${entity.path}");
                    }
                });
            }
        });
    }

    void _generateTemplate(final Config config) {
        Validate.notNull(config);

        final String templateFolder = config.dirstoscan.first;
        final String targetFolder = config.projectdir;

        final Directory dirTemplate = new Directory(templateFolder.replaceFirst(new RegExp(r"/$"), ""));
        if (!dirTemplate.existsSync()) {
            _logger.shout("$templateFolder does not exist!");
            return;
        }

        final File manifest = new File("${dirTemplate.path}/manifest.yaml");
        if (!manifest.existsSync()) {
            _logger.shout("Could not find a manifest.yaml in ${dirTemplate.path}");
        }

        if (targetFolder.isEmpty) {
            _logger.shout("Please specify your target folder (option -d)");
            return;
        }

        // e.g. example/sample1
        final Directory dirTargetBase = new Directory(targetFolder.replaceFirst(new RegExp(r"/$"), ""));
        if (!dirTargetBase.existsSync()) {
            dirTargetBase.createSync(recursive: true);
        }

        final List<Setting> settings = new List<Setting>();
        final String basename = path.basename(dirTargetBase.path);

        settings.add(new Setting("basename",basename));
        settings.addAll((new SettingsFromManifest(manifest)).settings);

        Setting name;
        try {
            name = settings.firstWhere((final Setting setting) => setting.key == TEMPLATENAME);
        } on Error {
            _logger.shout("Invalid manifest-file. (No name specified!)");
            return;
        }

        final List<Question> questions = (new QuestionsFromManifest(manifest)).questions;
        final Prompter prompter = new Prompter();

        try {
            prompter.ask(questions);

        } on ArgumentError catch(e) {
            _logger.shout(e.message);
            return;
        }

        settings.addAll(prompter.settings);

        _logger.fine("Source-BaseFolder ${dirTemplate.path}");
        _logger.fine("Target-BaseFolder ${dirTargetBase.path}");

        dirTemplate.listSync(recursive: true)
            // exclude manifest
            .where((final FileSystemEntity entity) => !entity.path.endsWith("/manifest.yaml"))
                .forEach((final FileSystemEntity entity) {

                    final String entityPath = entity.path.replaceFirst("${dirTemplate.path}/", "");
                    //_logger.info("EntityPath: ${entityPath} (Orig: ${entity.path})");

                    if (FileSystemEntity.isDirectorySync(entity.path)) {
                        final Directory dirTarget = new Directory("${dirTargetBase.path}/$entityPath");
                        //_logger.info("DirTarget: ${dirTarget.path}");

                        if (!dirTarget.existsSync()) {
                            dirTarget.createSync(recursive: true);
                            //_logger.info("${dirTarget.path} created...");
                        }
                    }
                    else {
                        final File src = new File(entity.path);
                        final String targetFilename = _setVarInTargetFilename(settings,"${dirTargetBase.path}/${entityPath}");
                        final File target = new File(targetFilename);

                        _logger.fine("Copy: ${src.path} -> ${target.path}");
                        String contents = src.readAsStringSync();

                        settings.forEach((final Setting setting) {
                            contents = contents.replaceAll(new RegExp("<%= ${setting.key} %>",multiLine: true,caseSensitive: false),setting.value);
                        });

                        target.writeAsStringSync(contents);
                    }
        });

        _logger.info("'${name.value}' created! (${dirTargetBase.path})");
    }

    void _configLogging(final String loglevel) {
        Validate.notBlank(loglevel);

        hierarchicalLoggingEnabled = false; // set this to true - its part of Logging SDK

        // now control the logging.
        // Turn off all logging first
        switch (loglevel) {
            case "fine":
            case "debug":
                Logger.root.level = Level.FINE;
                break;

            case "warning":
                Logger.root.level = Level.SEVERE;
                break;

            default:
                Logger.root.level = Level.INFO;
        }

        Logger.root.onRecord.listen(new LogPrintHandler(messageFormat: "%m"));
    }

    String _setVarInTargetFilename(final List<Setting> settings, String filename) {
        settings.forEach((final Setting setting) {
            if(filename.indexOf("{${setting.key}") != -1) {
                filename = filename.replaceAll("{${setting.key}}",setting.value);
            }
        });

        return filename;
    }

    String _getPackagesFolder() {
        Directory packages = new Directory("packages");
        if(!packages.existsSync()) {
            _logger.warning("'packages' folder not found!");
            //return;
        }
        packages = new Directory("../../hosted/pub.dartlang.org/stagedive-0.0.2");
        if(!packages.existsSync()) {
            throw new ArgumentError("${packages.path} not available. Gave up!");
        }
        return packages.path;
    }
}
