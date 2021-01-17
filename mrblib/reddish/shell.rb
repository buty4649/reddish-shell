module Reddish
  class Shell
    PS1 = "reddish> "
    PS2 = "         "

    def initialize(opts)
      @opts = opts
      @job = JobControl.new
      @executor = Executor.new
      @data_home = File.join(File.expand_path(XDG["CONFIG_HOME"]), "reddish")
    end

    def self.getopts(args)
      class << args; include Getopts; end
      opts = args.getopts("ic:", "version")
      if opts["?"]
        # Invalid option
        exit(2)
      end
      opts
    end

    def read_from_tty(prompt)
      if @opts["i"]
        STDOUT.write(prompt)
        STDIN.gets
      else
        begin
          linenoise(prompt)
        rescue Errno::ENOTTY => e
          # bugs:
          # Errono::NOTTY occurs unintentionally.
          # (e.g. `echo hoge | reddish` )
        end
      end
    end

    def run
      if ENV["REDDISH_PARSER_DEBUG"]
        ReddishParser.debug = true
      end

      if File.exists?(history_file_path)
        Linenoise::History.load(history_file_path)
      elsif Dir.exists?(@data_home).!
        Dir.mkdir(@data_home)
      end

      BuiltinCommands.define_commands(@executor)

      if cmd = @opts["c"]
        parse_and_exec(cmd)
      else
        cmdline = []
        need_next_list = false
        loop do
          line = read_from_tty(need_next_list ? PS2 : PS1)
          break if line.nil? && need_next_list.!
          cmdline << line
          parse_and_exec(cmdline.join("\n"))
          need_next_list = false
        rescue ReddishParser::UnterminatedString, ReddishParser::UnexpectedKeyword => e
          if line.nil?
            need_next_list = false
            STDERR.puts "Unterminated string."
          else
            need_next_list = true
          end
        rescue Errno::EWOULDBLOCK => e
          # reset command line
          need_next_list = false
        rescue => e
          need_next_list = false
          STDERR.puts "#{e.class} #{e.message}"
          if ENV['REDDISH_DEBUG']
            STDERR.puts
            STDERR.puts "backtrace:"
            e.backtrace.each_with_index do |t, i|
              STDERR.puts " [#{i}] #{t}"
            end
          end
        ensure
          unless need_next_list
            cmdline = []
          end
        end
      end
    end

    def parse_and_exec(line)
      parse_result = ReddishParser.parse(line, ENV["IFS"])

      if parse_result
        @job.run(@executor, parse_result)

        if $?.success?
          Linenoise::History.add(line)
          Linenoise::History.save(history_file_path)
        end
      end
    end

    def history_file_path
      File.join(@data_home, "history.txt")
    end
  end
end
