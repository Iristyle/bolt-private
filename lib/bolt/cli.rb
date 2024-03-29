require 'uri'
require 'optparse'
require 'benchmark'
require 'logger'
require 'json'
require 'bolt/node'
require 'bolt/version'
require 'bolt/executor'

module Bolt
  class CLIError < RuntimeError
    attr_reader :error_code

    def initialize(msg, error_code: 1)
      super(msg)
      @error_code = error_code
    end
  end

  class CLIExit < StandardError; end

  class CLI
    BANNER = <<-HELP.freeze
Usage: bolt <subcommand> <action> [options]

Available subcommands:
    bolt command run <command>       Run a command remotely
    bolt script run <script>         Upload a local script and run it remotely
    bolt task run <task> [params]    Run a Puppet Task
    bolt plan run <plan> [params]    Run a plan
    bolt file upload <src> <dest>    Upload a local file

where [options] are:
HELP

    TASK_HELP = <<-HELP.freeze
Usage: bolt task <action> [options] [parameters]

Available actions are:
    run                              Run a task

Parameters are of the form <parameter>=<value>.

Available options are:
HELP

    COMMAND_HELP = <<-HELP.freeze
Usage: bolt command <action> <command> [options]

Available actions are:
    run                              Run a command remotely

Available options are:
HELP

    SCRIPT_HELP = <<-HELP.freeze
Usage: bolt script <action> <script> [options]

Available actions are:
    run                              Upload a local script and run it remotely

Available options are:
HELP

    PLAN_HELP = <<-HELP.freeze
Usage: bolt plan <action> <plan> [options] [parameters]

Available actions are:
    run                              Run a plan

Parameters are of the form <parameter>=<value>.

Available options are:
HELP

    FILE_HELP = <<-HELP.freeze
Usage: bolt file <action> [options]

Available actions are:
    upload <src> <dest>              Upload local file <src> to <dest> on each node

Available options are:
HELP

    MODES = %w[command script task plan file].freeze
    ACTIONS = %w[run upload download].freeze

    attr_reader :parser
    attr_accessor :options

    def initialize(argv)
      @argv = argv
      @options = {}

      @parser = create_option_parser(@options)
    end

    def create_option_parser(results)
      OptionParser.new('') do |opts|
        opts.on('-n', '--nodes x,y,z', Array, 'Nodes to connect to') do |nodes|
          results[:nodes] = nodes
        end
        opts.on('-u', '--user USER',
                "User to authenticate as (Optional)") do |user|
          results[:user] = user
        end
        opts.on('-p', '--password PASSWORD',
                "Password to authenticate as (Optional)") do |password|
          results[:password] = password
        end
        opts.on('--modules MODULES', "Path to modules directory") do |modules|
          results[:modules] = modules
        end
        opts.on('--params PARAMETERS',
                "Parameters to a task or plan") do |params|
          results[:task_options] = parse_params(params)
        end
        opts.on_tail('--[no-]tty',
                     "Request a pseudo TTY on nodes that support it") do |tty|
          results[:tty] = tty
        end
        opts.on_tail('-h', '--help', 'Display help') do |_|
          results[:help] = true
        end
        opts.on_tail('--verbose', 'Display verbose logging') do |_|
          Bolt.log_level = Logger::INFO
        end
        opts.on_tail('--debug', 'Display debug logging') do |_|
          Bolt.log_level = Logger::DEBUG
        end
        opts.on_tail('--version', 'Display the version') do |_|
          puts Bolt::VERSION
          raise Bolt::CLIExit
        end
      end
    end

    def parse
      Bolt.log_level = Logger::WARN

      if @argv.empty?
        options[:help] = true
      end

      remaining = handle_parser_errors do
        parser.permute(@argv)
      end

      options[:mode] = remaining.shift

      if options[:mode] == 'help'
        options[:help] = true
        options[:mode] = remaining.shift
      end

      options[:action] = remaining.shift
      options[:object] = remaining.shift

      if options[:help]
        print_help(options[:mode])
        raise Bolt::CLIExit
      end

      task_options, remaining = remaining.partition { |s| s =~ /.+=/ }
      if options[:task_options]
        unless task_options.empty?
          raise Bolt::CLIError,
                "Parameters must be specified through either the --params " \
                "option or param=value pairs, not both"
        end
      else
        options[:task_options] = Hash[task_options.map { |a| a.split('=', 2) }]
      end

      options[:leftovers] = remaining

      validate(options)

      options
    end

    def print_help(mode)
      parser.banner = case mode
                      when 'task'
                        TASK_HELP
                      when 'command'
                        COMMAND_HELP
                      when 'script'
                        SCRIPT_HELP
                      when 'file'
                        FILE_HELP
                      when 'plan'
                        PLAN_HELP
                      else
                        BANNER
                      end
      puts parser.help
    end

    def parse_params(params)
      json = get_arg_input(params)
      JSON.parse(json)
    rescue JSON::ParserError => err
      raise Bolt::CLIError, "Unable to parse --params value as JSON: #{err}"
    end

    def get_arg_input(value)
      if value.start_with?('@')
        file = value.sub(/^@/, '')
        read_arg_file(file)
      elsif value == '-'
        STDIN.read
      else
        value
      end
    end

    def read_arg_file(file)
      File.read(file)
    rescue StandardError => err
      raise Bolt::CLIError, "Error attempting to read #{file}: #{err}"
    end

    def validate(options)
      unless MODES.include?(options[:mode])
        raise Bolt::CLIError, "Expected mode to be one of #{MODES.join(', ')}"
      end

      unless ACTIONS.include?(options[:action])
        raise Bolt::CLIError,
              "Expected action to be one of #{ACTIONS.join(', ')}"
      end

      if options[:mode] != 'file' && !options[:leftovers].empty?
        raise Bolt::CLIError,
              "unknown argument(s) #{options[:leftovers].join(', ')}"
      end

      unless options[:nodes] || options[:mode] == 'plan'
        raise Bolt::CLIError, "option --nodes must be specified"
      end
    end

    def handle_parser_errors
      yield
    rescue OptionParser::MissingArgument => e
      raise Bolt::CLIError, "option '#{e.args.first}' needs a parameter"
    rescue OptionParser::InvalidOption => e
      raise Bolt::CLIError, "unknown argument '#{e.args.first}'"
    end

    def execute(options)
      if options[:mode] == 'plan' || options[:mode] == 'task'
        begin
          require_relative '../../vendored/require_vendored'
        rescue LoadError
          raise Bolt::CLIError, "Puppet must be installed to execute tasks"
        end
      end

      if options[:mode] == 'plan'
        execute_plan(options)
      else
        nodes = options[:nodes].map do |node|
          Bolt::Node.from_uri(node, options[:user], options[:password],
                              tty: options[:tty])
        end

        results = nil
        elapsed_time = Benchmark.realtime do
          executor = Bolt::Executor.new(nodes)
          results =
            case options[:mode]
            when 'command'
              executor.run_command(options[:object])
            when 'script'
              executor.run_script(options[:object])
            when 'task'
              path = options[:object]
              input_method = nil

              unless file_exist?(path)
                path, metadata = load_task_data(path, options[:modules])
                input_method = metadata['input_method']
              end

              input_method ||= 'both'
              executor.run_task(path, input_method, options[:task_options])
            when 'file'
              src = options[:object]
              dest = options[:leftovers].first

              if dest.nil?
                raise Bolt::CLIError, "A destination path must be specified"
              elsif !file_exist?(src)
                raise Bolt::CLIError, "The source file '#{src}' does not exist"
              end

              executor.file_upload(src, dest)
            end
        end

        print_results(results, elapsed_time)
      end
    end

    def execute_plan(options)
      Bolt.config = options
      result = run_plan(options[:object],
                        options[:task_options],
                        options[:modules])
      puts result
    end

    def colorize(result, stream)
      color = result.success? ? "\033[32m" : "\033[31m"
      stream.print color if stream.isatty
      yield
      stream.print "\033[0m" if stream.isatty
    end

    def print_results(results, elapsed_time)
      results.each_pair do |node, result|
        colorize(result, $stdout) { $stdout.puts "#{node.host}:" }
        $stdout.puts
        $stdout.puts result.message
        $stdout.puts
      end

      $stdout.puts format("Ran on %d node%s in %.2f seconds",
                          results.size,
                          results.size > 1 ? 's' : '',
                          elapsed_time)
    end

    def file_exist?(path)
      File.exist?(path)
    end

    def load_task_data(name, modules)
      if modules.nil?
        raise Bolt::CLIError,
              "The '--modules' option must be specified to run a task"
      end

      module_name, file_name = name.split('::', 2)
      file_name ||= 'init'

      env = Puppet::Node::Environment.create('bolt', [modules])
      Puppet.override(environments: Puppet::Environments::Static.new(env)) do
        data = Puppet::InfoService::TaskInformationService.task_data(
          env.name, module_name, name
        )

        file = data[:files].find { |f| File.basename(f, '.*') == file_name }
        if file.nil?
          raise Bolt::CLIError, "Failed to load task file for '#{name}'"
        end

        metadata =
          if data[:metadata_file]
            JSON.parse(File.read(data[:metadata_file]))
          else
            {}
          end

        [file, metadata]
      end
    end

    def run_plan(plan, args, modules)
      modulepath = modules ? [modules] : []

      Dir.mktmpdir('bolt') do |dir|
        cli = []
        Puppet::Settings::REQUIRED_APP_SETTINGS.each do |setting|
          cli << "--#{setting}" << dir
        end
        Puppet.initialize_settings(cli)
        Puppet::Pal.in_tmp_environment('bolt', modulepath: modulepath) do |pal|
          puts pal.run_plan(plan, plan_args: args)
        end
      end
    end
  end
end
